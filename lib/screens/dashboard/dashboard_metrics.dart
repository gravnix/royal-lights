import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/quote.dart';
import '../../providers/providers.dart' show DashboardPeriod;

/// Pure aggregation helpers for the dashboard.
///
/// Everything here is a plain function over already-fetched lists — no widgets,
/// no Riverpod, no I/O — so the numbers can be reasoned about (and corrected)
/// without touching the layout.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ─────────────────────────────────────────────────────────────────
// Period windows
// ─────────────────────────────────────────────────────────────────

/// The current reporting window plus the immediately preceding one, so every
/// KPI can show a delta. `end` bounds are exclusive.
class PeriodWindow {
  final DateTime start;
  final DateTime end;
  final DateTime previousStart;
  final DateTime previousEnd;

  const PeriodWindow({
    required this.start,
    required this.end,
    required this.previousStart,
    required this.previousEnd,
  });
}

PeriodWindow windowFor(DashboardPeriod period, DateTime now) {
  switch (period) {
    case DashboardPeriod.monthly:
      // DateTime normalises month 0 and 13, so no manual year rollover needed.
      final start = DateTime(now.year, now.month, 1);
      return PeriodWindow(
        start: start,
        end: DateTime(now.year, now.month + 1, 1),
        previousStart: DateTime(now.year, now.month - 1, 1),
        previousEnd: start,
      );
    case DashboardPeriod.yearly:
      final start = DateTime(now.year, 1, 1);
      return PeriodWindow(
        start: start,
        end: DateTime(now.year + 1, 1, 1),
        previousStart: DateTime(now.year - 1, 1, 1),
        previousEnd: start,
      );
  }
}

bool _inRange(DateTime? d, DateTime start, DateTime end) {
  if (d == null) return false;
  return !d.isBefore(start) && d.isBefore(end);
}

int countInRange(
  Iterable<DateTime?> dates,
  DateTime start,
  DateTime end,
) =>
    dates.where((d) => _inRange(d, start, end)).length;

/// Percentage change against the previous window.
/// Returns null when there is no baseline to compare against (previous == 0),
/// which the UI renders as "חדש" rather than a misleading ∞%.
double? deltaPercent(num current, num previous) {
  if (previous == 0) return current == 0 ? 0 : null;
  return (current - previous) / previous * 100;
}

// ─────────────────────────────────────────────────────────────────
// Orders
// ─────────────────────────────────────────────────────────────────

/// "בטיפול" — started but not yet delivered. Excludes `active` (not started)
/// and the terminal `delivered` / `canceled`.
const Set<OrderStatus> inProgressStatuses = {
  OrderStatus.preparing,
  OrderStatus.sentToSupplier,
  OrderStatus.inAssembly,
  OrderStatus.awaitingShipping,
  OrderStatus.handled,
};

int activeOrderCount(List<Order> orders) =>
    orders.where((o) => o.status == OrderStatus.active).length;

int inProgressOrderCount(List<Order> orders) =>
    orders.where((o) => inProgressStatuses.contains(o.status)).length;

/// Count per status, in canonical display order, skipping empty buckets so the
/// pipeline bar doesn't render zero-width segments.
Map<OrderStatus, int> ordersByStatus(List<Order> orders) {
  final counts = <OrderStatus, int>{};
  for (final status in OrderStatusExtension.all) {
    final n = orders.where((o) => o.status == status).length;
    if (n > 0) counts[status] = n;
  }
  return counts;
}

double revenueInRange(List<Order> orders, DateTime start, DateTime end) {
  return orders
      .where((o) =>
          o.status != OrderStatus.canceled && _inRange(o.createdAt, start, end))
      .fold<double>(0, (sum, o) => sum + o.totalPrice);
}

// ─────────────────────────────────────────────────────────────────
// Quotes
// ─────────────────────────────────────────────────────────────────

/// Share of quotes in the window that turned into an order, 0–100.
/// Null when no quotes were issued in the window.
double? quoteConversionRate(List<Quote> quotes, DateTime start, DateTime end) {
  final inWindow =
      quotes.where((q) => _inRange(q.createdAt, start, end)).toList();
  if (inWindow.isEmpty) return null;
  final converted =
      inWindow.where((q) => q.status == QuoteStatus.converted).length;
  return converted / inWindow.length * 100;
}

// ─────────────────────────────────────────────────────────────────
// Debt — by amount
// ─────────────────────────────────────────────────────────────────

class DebtBand {
  final int count;
  final double total;
  const DebtBand({this.count = 0, this.total = 0});

  DebtBand _add(double debt) => DebtBand(count: count + 1, total: total + debt);
}

class DebtByAmount {
  final DebtBand below5k;
  final DebtBand from5kTo10k;
  final DebtBand above10k;

  const DebtByAmount({
    this.below5k = const DebtBand(),
    this.from5kTo10k = const DebtBand(),
    this.above10k = const DebtBand(),
  });

  int get totalCount => below5k.count + from5kTo10k.count + above10k.count;
  double get totalAmount => below5k.total + from5kTo10k.total + above10k.total;
}

DebtByAmount debtByAmount(List<Customer> customers) {
  var below = const DebtBand();
  var mid = const DebtBand();
  var above = const DebtBand();

  for (final c in customers) {
    final debt = c.remainingDebt;
    if (debt <= 0) continue;
    if (debt < 5000) {
      below = below._add(debt);
    } else if (debt < 10000) {
      mid = mid._add(debt);
    } else {
      above = above._add(debt);
    }
  }
  return DebtByAmount(below5k: below, from5kTo10k: mid, above10k: above);
}

// ─────────────────────────────────────────────────────────────────
// Debt — by age
// ─────────────────────────────────────────────────────────────────

/// A customer carrying a balance, with how long it has been since they paid.
class OverdueCustomer {
  final Customer customer;
  final double debt;

  /// Days since the last payment. When the customer has never paid we fall
  /// back to their oldest still-open order; when even that is unknown the
  /// entry is [ageUnknown] and lands in the oldest band.
  final int days;
  final bool ageUnknown;

  const OverdueCustomer({
    required this.customer,
    required this.debt,
    required this.days,
    this.ageUnknown = false,
  });
}

/// Last payment date per customer id.
Map<String, DateTime> lastPaymentByCustomer(List<Payment> payments) {
  final result = <String, DateTime>{};
  for (final p in payments) {
    final current = result[p.customerId];
    if (current == null || p.date.isAfter(current)) {
      result[p.customerId] = p.date;
    }
  }
  return result;
}

/// Oldest still-open (not delivered, not canceled) order date per customer id.
Map<String, DateTime> oldestOpenOrderByCustomer(List<Order> orders) {
  final result = <String, DateTime>{};
  for (final o in orders) {
    if (o.status == OrderStatus.delivered || o.status == OrderStatus.canceled) {
      continue;
    }
    final created = o.createdAt;
    if (created == null) continue;
    final current = result[o.customerId];
    if (current == null || created.isBefore(current)) {
      result[o.customerId] = created;
    }
  }
  return result;
}

List<OverdueCustomer> buildOverdueCustomers({
  required List<Customer> customers,
  required List<Payment> payments,
  required List<Order> orders,
  required DateTime now,
}) {
  final lastPayments = lastPaymentByCustomer(payments);
  final oldestOrders = oldestOpenOrderByCustomer(orders);
  final today = dateOnly(now);

  final result = <OverdueCustomer>[];
  for (final c in customers) {
    if (c.remainingDebt <= 0) continue;
    final reference = lastPayments[c.id] ?? oldestOrders[c.id];
    if (reference == null) {
      result.add(OverdueCustomer(
        customer: c,
        debt: c.remainingDebt,
        days: 0,
        ageUnknown: true,
      ));
      continue;
    }
    final days = today.difference(dateOnly(reference)).inDays;
    result.add(OverdueCustomer(
      customer: c,
      debt: c.remainingDebt,
      days: days < 0 ? 0 : days,
    ));
  }

  // Oldest debt first; ties broken by the larger balance.
  result.sort((a, b) {
    if (a.ageUnknown != b.ageUnknown) return a.ageUnknown ? -1 : 1;
    final byDays = b.days.compareTo(a.days);
    if (byDays != 0) return byDays;
    return b.debt.compareTo(a.debt);
  });
  return result;
}

class DebtByAge {
  final DebtBand upTo20;
  final DebtBand from20To40;
  final DebtBand over40;

  const DebtByAge({
    this.upTo20 = const DebtBand(),
    this.from20To40 = const DebtBand(),
    this.over40 = const DebtBand(),
  });

  int get totalCount => upTo20.count + from20To40.count + over40.count;
}

/// Bands requested by the user: ≤20 days, 20–40 days, over 40 days.
/// Customers whose age can't be determined count as the oldest band, so a
/// never-paying customer is never quietly dropped from the report.
DebtByAge debtByAge(List<OverdueCustomer> overdue) {
  var upTo20 = const DebtBand();
  var from20To40 = const DebtBand();
  var over40 = const DebtBand();

  for (final entry in overdue) {
    if (entry.ageUnknown || entry.days > 40) {
      over40 = over40._add(entry.debt);
    } else if (entry.days > 20) {
      from20To40 = from20To40._add(entry.debt);
    } else {
      upTo20 = upTo20._add(entry.debt);
    }
  }
  return DebtByAge(
    upTo20: upTo20,
    from20To40: from20To40,
    over40: over40,
  );
}

// ─────────────────────────────────────────────────────────────────
// Trend series
// ─────────────────────────────────────────────────────────────────

/// One bucket of the activity chart. [bucketStart] is kept unformatted so the
/// widget layer can label it in the active locale.
class TrendPoint {
  final DateTime bucketStart;
  final int orders;
  final int customers;
  final double revenue;

  const TrendPoint({
    required this.bucketStart,
    required this.orders,
    required this.customers,
    required this.revenue,
  });
}

/// Last 12 months in monthly mode, last 5 years in yearly mode — oldest first.
List<TrendPoint> buildTrend({
  required DashboardPeriod period,
  required List<Order> orders,
  required List<Customer> customers,
  required DateTime now,
}) {
  final buckets = <({DateTime start, DateTime end})>[];

  if (period == DashboardPeriod.monthly) {
    for (var i = 11; i >= 0; i--) {
      final start = DateTime(now.year, now.month - i, 1);
      buckets.add((start: start, end: DateTime(start.year, start.month + 1, 1)));
    }
  } else {
    for (var i = 4; i >= 0; i--) {
      final start = DateTime(now.year - i, 1, 1);
      buckets.add((start: start, end: DateTime(start.year + 1, 1, 1)));
    }
  }

  return buckets.map((b) {
    return TrendPoint(
      bucketStart: b.start,
      orders: countInRange(orders.map((o) => o.createdAt), b.start, b.end),
      customers:
          countInRange(customers.map((c) => c.createdAt), b.start, b.end),
      revenue: revenueInRange(orders, b.start, b.end),
    );
  }).toList();
}
