import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/app_animations.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/order.dart';
import '../providers/providers.dart';
import '../widgets/editorial_screen_title.dart';
import 'customers/customer_detail_screen.dart';
import 'dashboard/dashboard_charts.dart';
import 'dashboard/dashboard_metrics.dart';
import 'dashboard/dashboard_ui.dart';
import 'dashboard/timeline_cards.dart';

/// Business overview: customers, orders and quotes over the selected period,
/// the receivables breakdown, the order pipeline, and dated reminders.
///
/// Inventory, repairs and assemblies deliberately have no cards here — they
/// stay one click away in the nav rail and the quick actions.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final username = ref.watch(currentUsernameProvider);
    final period = ref.watch(dashboardPeriodProvider);

    final ordersAsync = ref.watch(ordersProvider);
    final customersAsync = ref.watch(customersProvider);
    final quotesAsync = ref.watch(quotesProvider);
    final paymentsAsync = ref.watch(paymentsProvider(null));
    final notesAsync = ref.watch(timelineNotesProvider);

    final orders = ordersAsync.value ?? const [];
    final customers = customersAsync.value ?? const [];
    final quotes = quotesAsync.value ?? const [];
    final payments = paymentsAsync.value ?? const [];
    final notes = notesAsync.value ?? const [];

    final coreLoading = ordersAsync.isLoading ||
        customersAsync.isLoading ||
        paymentsAsync.isLoading;
    final hasError = ordersAsync.hasError ||
        customersAsync.hasError ||
        quotesAsync.hasError ||
        paymentsAsync.hasError ||
        notesAsync.hasError;

    final now = DateTime.now();
    final localeName = Localizations.localeOf(context).toString();
    final window = windowFor(period, now);

    // ── Period metrics ─────────────────────────────────────────────
    final newCustomers = countInRange(
        customers.map((c) => c.createdAt), window.start, window.end);
    final newCustomersPrev = countInRange(customers.map((c) => c.createdAt),
        window.previousStart, window.previousEnd);

    final periodOrders =
        countInRange(orders.map((o) => o.createdAt), window.start, window.end);
    final periodOrdersPrev = countInRange(orders.map((o) => o.createdAt),
        window.previousStart, window.previousEnd);
    final periodRevenue = revenueInRange(orders, window.start, window.end);

    final periodQuotes =
        countInRange(quotes.map((q) => q.createdAt), window.start, window.end);
    final periodQuotesPrev = countInRange(quotes.map((q) => q.createdAt),
        window.previousStart, window.previousEnd);
    final conversion = quoteConversionRate(quotes, window.start, window.end);

    // ── Receivables ────────────────────────────────────────────────
    final byAmount = debtByAmount(customers);
    final overdue = buildOverdueCustomers(
      customers: customers,
      payments: payments,
      orders: orders,
      now: now,
    );
    final byAge = debtByAge(overdue);

    final trend = buildTrend(
      period: period,
      orders: orders,
      customers: customers,
      now: now,
    );

    void go(int index) =>
        ref.read(selectedNavIndexProvider.notifier).setIndex(index);

    void refresh() {
      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(quotesProvider);
      ref.invalidate(paymentsProvider(null));
      ref.invalidate(timelineNotesProvider);
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorialScreenTitle(
              title: dashTr(context, l10n, 'dashboard',
                  en: 'Dashboard', he: 'לוח בקרה', ar: 'لوحة التحكم'),
              subtitle: Text(
                '${_greeting(context, l10n, now)} · '
                '${DateFormat('EEEE, d MMMM y', localeName).format(now)}',
                style: GoogleFonts.assistant(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PeriodToggle(period: period, l10n: l10n, ref: ref),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppTheme.onSurfaceVariant,
                      tooltip: dashTr(context, l10n, 'refresh',
                          en: 'Refresh', he: 'רענון', ar: 'تحديث'),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.secondary.withValues(alpha: 0.10),
                        border: Border.all(
                          color: AppTheme.secondary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Icon(Icons.person_rounded,
                          size: 18, color: AppTheme.secondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: GoogleFonts.assistant(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedFadeIn(
                duration: AppAnimations.durationMedium,
                slideUp: true,
                scaleBegin: 0.98,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final wide = width >= 1180;
                    final medium = width >= 720;
                    const gap = 14.0;

                    final kpiColumns = wide ? 4 : (medium ? 2 : 1);

                    final kpis = [
                      _KpiCard(
                        label: dashTr(context, l10n, 'newCustomers',
                            en: 'New customers',
                            he: 'לקוחות חדשים',
                            ar: 'عملاء جدد'),
                        value: coreLoading ? null : count(newCustomers),
                        secondary: _periodLabel(context, l10n, period),
                        delta: deltaPercent(newCustomers, newCustomersPrev),
                        icon: Icons.person_add_alt_1_rounded,
                        accent: AppTheme.secondary,
                        onTap: () => go(1),
                      ),
                      _KpiCard(
                        label: dashTr(context, l10n, 'orders',
                            en: 'Orders', he: 'הזמנות', ar: 'الطلبات'),
                        value: coreLoading ? null : count(periodOrders),
                        secondary: money(periodRevenue),
                        delta: deltaPercent(periodOrders, periodOrdersPrev),
                        icon: Icons.receipt_long_rounded,
                        accent: AppTheme.primary,
                        onTap: () => go(2),
                      ),
                      _KpiCard(
                        label: dashTr(context, l10n, 'quotes',
                            en: 'Quotes',
                            he: 'הצעות מחיר',
                            ar: 'عروض الأسعار'),
                        value: quotesAsync.isLoading
                            ? null
                            : count(periodQuotes),
                        secondary: conversion == null
                            ? _periodLabel(context, l10n, period)
                            : '${dashTr(context, l10n, 'conversionRate', en: 'Converted', he: 'הומרו להזמנה', ar: 'تم تحويلها')} '
                                '${conversion.toStringAsFixed(0)}%',
                        delta: deltaPercent(periodQuotes, periodQuotesPrev),
                        icon: Icons.request_quote_rounded,
                        accent: AppTheme.accentBlue,
                        onTap: () => go(2),
                      ),
                      _KpiCard(
                        label: dashTr(context, l10n, 'openDebt',
                            en: 'Open balance',
                            he: 'סה״כ חוב פתוח',
                            ar: 'إجمالي الرصيد المستحق'),
                        value: coreLoading ? null : money(byAmount.totalAmount),
                        secondary:
                            '${count(byAmount.totalCount)} ${dashTr(context, l10n, 'customersInDebt', en: 'customers', he: 'לקוחות', ar: 'عملاء')}',
                        icon: Icons.account_balance_wallet_rounded,
                        accent: AppTheme.error,
                        onTap: () => go(1),
                      ),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasError) ...[
                          _ErrorBanner(l10n: l10n, onRetry: refresh),
                          const SizedBox(height: gap),
                        ],
                        // Calendar + reminders lead the page, side by side.
                        _split(
                          stack: !medium,
                          gap: gap,
                          primaryFlex: 1,
                          secondaryFlex: 1,
                          primary: CalendarCard(
                            notes: notes,
                            loading: notesAsync.isLoading,
                            l10n: l10n,
                            ref: ref,
                          ),
                          secondary: RemindersCard(
                            notes: notes,
                            loading: notesAsync.isLoading,
                            l10n: l10n,
                            ref: ref,
                          ),
                        ),
                        const SizedBox(height: gap),
                        _grid(kpis, kpiColumns, gap),
                        const SizedBox(height: gap),
                        _split(
                          stack: !medium,
                          gap: gap,
                          primary: _TrendCard(
                            trend: trend,
                            period: period,
                            loading: coreLoading,
                            l10n: l10n,
                          ),
                          secondary: _OverdueCustomersCard(
                            overdue: overdue,
                            loading: coreLoading,
                            l10n: l10n,
                          ),
                        ),
                        const SizedBox(height: gap),
                        _split(
                          stack: !medium,
                          gap: gap,
                          primary: _DebtsCard(
                            byAmount: byAmount,
                            byAge: byAge,
                            loading: coreLoading,
                            onTap: () => go(1),
                            l10n: l10n,
                          ),
                          secondary: _PipelineCard(
                            orders: orders,
                            loading: ordersAsync.isLoading,
                            onTap: () => go(2),
                            l10n: l10n,
                          ),
                        ),
                        const SizedBox(height: gap),
                        _QuickActionsCard(go: go, l10n: l10n),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _greeting(
      BuildContext context, AppLocalizations? l10n, DateTime now) {
    if (now.hour < 12) {
      return dashTr(context, l10n, 'goodMorning',
          en: 'Good morning', he: 'בוקר טוב', ar: 'صباح الخير');
    }
    if (now.hour < 17) {
      return dashTr(context, l10n, 'goodAfternoon',
          en: 'Good afternoon', he: 'צהריים טובים', ar: 'ظهر سعيد');
    }
    return dashTr(context, l10n, 'goodEvening',
        en: 'Good evening', he: 'ערב טוב', ar: 'مساء الخير');
  }

  static String _periodLabel(
      BuildContext context, AppLocalizations? l10n, DashboardPeriod period) {
    return period == DashboardPeriod.monthly
        ? dashTr(context, l10n, 'thisMonth',
            en: 'This month', he: 'החודש', ar: 'هذا الشهر')
        : dashTr(context, l10n, 'thisYear',
            en: 'This year', he: 'השנה', ar: 'هذه السنة');
  }
}

// ─────────────────────────────────────────────────────────────────
// Layout helpers
// ─────────────────────────────────────────────────────────────────

/// Fixed-column grid that pads the last row so cards keep their width.
Widget _grid(List<Widget> children, int columns, double gap) {
  if (columns <= 1) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }

  final rows = <Widget>[];
  for (var start = 0; start < children.length; start += columns) {
    final end = (start + columns).clamp(0, children.length);
    final slice = children.sublist(start, end);
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var col = 0; col < columns; col++) ...[
              if (col > 0) SizedBox(width: gap),
              Expanded(
                child: col < slice.length ? slice[col] : const SizedBox(),
              ),
            ],
          ],
        ),
      ),
    );
    if (start + columns < children.length) rows.add(SizedBox(height: gap));
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: rows,
  );
}

/// Two-column split above the breakpoint (3:2 by default), stacked below.
Widget _split({
  required Widget primary,
  required Widget secondary,
  required bool stack,
  required double gap,
  int primaryFlex = 3,
  int secondaryFlex = 2,
}) {
  if (stack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [primary, SizedBox(height: gap), secondary],
    );
  }
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        SizedBox(width: gap),
        Expanded(flex: secondaryFlex, child: secondary),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
// Period toggle
// ─────────────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final DashboardPeriod period;
  final AppLocalizations? l10n;
  final WidgetRef ref;

  const _PeriodToggle({
    required this.period,
    required this.l10n,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context,
            DashboardPeriod.monthly,
            dashTr(context, l10n, 'monthly',
                en: 'Monthly', he: 'חודשי', ar: 'شهري'),
          ),
          _segment(
            context,
            DashboardPeriod.yearly,
            dashTr(context, l10n, 'yearly',
                en: 'Yearly', he: 'שנתי', ar: 'سنوي'),
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, DashboardPeriod value, String label) {
    final selected = period == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => ref.read(dashboardPeriodProvider.notifier).setPeriod(value),
      child: AnimatedContainer(
        duration: AppAnimations.durationFast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.assistant(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppTheme.onPrimary : AppTheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Error banner
// ─────────────────────────────────────────────────────────────────

/// Without this, a failed fetch silently renders every figure as zero — which
/// reads as "no debt, no orders" rather than "no data".
class _ErrorBanner extends StatelessWidget {
  final AppLocalizations? l10n;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.l10n, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 20, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dashTr(context, l10n, 'dashboardLoadError',
                  en: 'Some data could not be loaded. Figures may be incomplete.',
                  he: 'חלק מהנתונים לא נטענו. ייתכן שהמספרים חלקיים.',
                  ar: 'تعذر تحميل بعض البيانات. قد تكون الأرقام غير مكتملة.'),
              style: GoogleFonts.assistant(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              dashTr(context, l10n, 'retry',
                  en: 'Retry', he: 'נסה שוב', ar: 'إعادة المحاولة'),
              style: GoogleFonts.assistant(
                fontWeight: FontWeight.w800,
                color: AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Hero KPI card
// ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;

  /// Null while loading — the card shows a skeleton at the value's size.
  final String? value;
  final String secondary;
  final double? delta;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.secondary,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Container(
          decoration: dashCardDecoration(accent: accent, emphasized: true),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kCardRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 4, color: accent),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DashIconChip(icon: icon, color: accent, size: 34),
                          const Spacer(),
                          if (delta != null) _DeltaPill(delta: delta!),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        label,
                        style: GoogleFonts.assistant(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (value == null)
                        const DashValueSkeleton(width: 84, height: 32)
                      else
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            value!,
                            style: GoogleFonts.assistant(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              letterSpacing: -0.5,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        secondary,
                        style: GoogleFonts.assistant(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final double delta;

  const _DeltaPill({required this.delta});

  @override
  Widget build(BuildContext context) {
    final rising = delta > 0;
    final flat = delta == 0;
    final color = flat
        ? AppTheme.onSurfaceVariant
        : (rising ? AppTheme.success : AppTheme.error);

    return DashPill(
      label: '${delta.abs().toStringAsFixed(0)}%',
      color: color,
      icon: flat
          ? Icons.remove_rounded
          : (rising ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Activity trend
// ─────────────────────────────────────────────────────────────────

/// Orders and new customers as stacked small multiples over a shared x axis.
/// Two measures of different scale never share one frame.
class _TrendCard extends StatelessWidget {
  final List<TrendPoint> trend;
  final DashboardPeriod period;
  final bool loading;
  final AppLocalizations? l10n;

  const _TrendCard({
    required this.trend,
    required this.period,
    required this.loading,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toString();
    final monthly = period == DashboardPeriod.monthly;
    final pattern = monthly ? 'MMM' : 'yyyy';

    final ordersLabel = dashTr(context, l10n, 'orders',
        en: 'Orders', he: 'הזמנות', ar: 'الطلبات');
    final customersLabel = dashTr(context, l10n, 'newCustomers',
        en: 'New customers', he: 'לקוחות חדשים', ar: 'عملاء جدد');

    List<BarDatum> series(
      int Function(TrendPoint) pick,
      String name, {
      bool withRevenue = false,
    }) {
      return trend.map((p) {
        final label = DateFormat(pattern, localeName).format(p.bucketStart);
        final full = DateFormat(monthly ? 'MMMM y' : 'yyyy', localeName)
            .format(p.bucketStart);
        return BarDatum(
          label: label,
          value: pick(p),
          tooltip: '$full\n$name: ${count(pick(p))}'
              '${withRevenue ? '\n${money(p.revenue)}' : ''}',
        );
      }).toList();
    }

    final totalOrders = trend.fold<int>(0, (s, p) => s + p.orders);
    final totalCustomers = trend.fold<int>(0, (s, p) => s + p.customers);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.insights_rounded,
            color: AppTheme.secondary,
            title: dashTr(context, l10n, 'activityTrend',
                en: 'Activity trend', he: 'מגמת פעילות', ar: 'اتجاه النشاط'),
            subtitle: monthly
                ? dashTr(context, l10n, 'last12Months',
                    en: 'Last 12 months',
                    he: '12 החודשים האחרונים',
                    ar: 'آخر 12 شهرًا')
                : dashTr(context, l10n, 'last5Years',
                    en: 'Last 5 years',
                    he: '5 השנים האחרונות',
                    ar: 'آخر 5 سنوات'),
          ),
          const SizedBox(height: 20),
          if (loading)
            const SizedBox(
              height: 220,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            _SeriesHeading(
              label: ordersLabel,
              total: count(totalOrders),
              color: AppTheme.secondary,
            ),
            const SizedBox(height: 8),
            TrendBarChart(
              data: series((p) => p.orders, ordersLabel, withRevenue: true),
              color: AppTheme.secondary,
              height: 92,
              showLabels: false,
            ),
            const SizedBox(height: 14),
            _SeriesHeading(
              label: customersLabel,
              total: count(totalCustomers),
              color: AppTheme.primary,
            ),
            const SizedBox(height: 8),
            TrendBarChart(
              data: series((p) => p.customers, customersLabel),
              color: AppTheme.primary,
              height: 92,
              labelStride: monthly ? 2 : 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeriesHeading extends StatelessWidget {
  final String label;
  final String total;
  final Color color;

  const _SeriesHeading({
    required this.label,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.assistant(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          total,
          style: GoogleFonts.assistant(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Receivables
// ─────────────────────────────────────────────────────────────────

class _DebtsCard extends StatelessWidget {
  final DebtByAmount byAmount;
  final DebtByAge byAge;
  final bool loading;
  final VoidCallback onTap;
  final AppLocalizations? l10n;

  const _DebtsCard({
    required this.byAmount,
    required this.byAge,
    required this.loading,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final ramp = rampSteps(3);

    final amountSegments = [
      BarSegment(
        label: dashTr(context, l10n, 'debtUnder5k',
            en: 'Under ₪5,000', he: 'עד ₪5,000', ar: 'أقل من ₪5,000'),
        count: byAmount.below5k.count,
        color: ramp[0],
        detail: moneyCompact(byAmount.below5k.total),
      ),
      BarSegment(
        label: dashTr(context, l10n, 'debt5kTo10k',
            en: '₪5,000–10,000',
            he: '₪5,000–10,000',
            ar: '₪5,000–10,000'),
        count: byAmount.from5kTo10k.count,
        color: ramp[1],
        detail: moneyCompact(byAmount.from5kTo10k.total),
      ),
      BarSegment(
        label: dashTr(context, l10n, 'debtOver10k',
            en: 'Over ₪10,000', he: 'מעל ₪10,000', ar: 'أكثر من ₪10,000'),
        count: byAmount.above10k.count,
        color: ramp[2],
        detail: moneyCompact(byAmount.above10k.total),
      ),
    ];

    final ageSegments = [
      BarSegment(
        label: dashTr(context, l10n, 'debtAgeUpTo20',
            en: 'Up to 20 days', he: 'עד 20 יום', ar: 'حتى 20 يومًا'),
        count: byAge.upTo20.count,
        color: ramp[0],
        detail: moneyCompact(byAge.upTo20.total),
      ),
      BarSegment(
        label: dashTr(context, l10n, 'debtAge20To40',
            en: '20–40 days', he: '20–40 יום', ar: '20–40 يومًا'),
        count: byAge.from20To40.count,
        color: ramp[1],
        detail: moneyCompact(byAge.from20To40.total),
      ),
      BarSegment(
        label: dashTr(context, l10n, 'debtAgeOver40',
            en: 'Over 40 days', he: 'מעל 40 יום', ar: 'أكثر من 40 يومًا'),
        count: byAge.over40.count,
        color: ramp[2],
        detail: moneyCompact(byAge.over40.total),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.account_balance_wallet_rounded,
            color: AppTheme.error,
            title: dashTr(context, l10n, 'billing',
                en: 'Receivables', he: 'חיובים', ar: 'المستحقات'),
            subtitle:
                '${count(byAmount.totalCount)} ${dashTr(context, l10n, 'customersInDebt', en: 'customers', he: 'לקוחות', ar: 'عملاء')} · ${money(byAmount.totalAmount)}',
            trailing: IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              color: AppTheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 20),
          if (loading)
            const SizedBox(
              height: 180,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            _SubHeading(
              label: dashTr(context, l10n, 'debtByAmount',
                  en: 'By amount', he: 'לפי סכום', ar: 'حسب المبلغ'),
            ),
            const SizedBox(height: 10),
            SegmentedProportionBar(segments: amountSegments, onTap: onTap),
            const SizedBox(height: 20),
            Divider(
              height: 1,
              color: AppTheme.outlineVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 18),
            _SubHeading(
              label: dashTr(context, l10n, 'debtByAge',
                  en: 'By age of debt',
                  he: 'לפי גיל החוב',
                  ar: 'حسب عمر الدين'),
              hint: dashTr(context, l10n, 'debtByAgeHint',
                  en: 'Time since last payment',
                  he: 'זמן שעבר מאז התשלום האחרון',
                  ar: 'الوقت منذ آخر دفعة'),
            ),
            const SizedBox(height: 10),
            SegmentedProportionBar(segments: ageSegments, onTap: onTap),
          ],
        ],
      ),
    );
  }
}

class _SubHeading extends StatelessWidget {
  final String label;
  final String? hint;

  const _SubHeading({required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: GoogleFonts.assistant(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppTheme.onSurface,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint!,
              style: GoogleFonts.assistant(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Overdue customers
// ─────────────────────────────────────────────────────────────────

class _OverdueCustomersCard extends StatelessWidget {
  final List<OverdueCustomer> overdue;
  final bool loading;
  final AppLocalizations? l10n;

  const _OverdueCustomersCard({
    required this.overdue,
    required this.loading,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final top = overdue.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.hourglass_bottom_rounded,
            color: AppTheme.error,
            title: dashTr(context, l10n, 'overdueCustomers',
                en: 'Longest outstanding',
                he: 'לקוחות בפיגור',
                ar: 'العملاء المتأخرون'),
            subtitle: dashTr(context, l10n, 'overdueSubtitle',
                en: 'Longest without a payment',
                he: 'הזמן הרב ביותר ללא תשלום',
                ar: 'الأطول بدون دفع'),
            trailing: overdue.isEmpty
                ? null
                : DashPill(
                    label: count(overdue.length), color: AppTheme.error),
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (top.isEmpty)
            DashEmptyState(
              icon: Icons.check_circle_outline_rounded,
              message: dashTr(context, l10n, 'noOverdueCustomers',
                  en: 'No outstanding balances',
                  he: 'אין חובות פתוחים',
                  ar: 'لا توجد أرصدة مستحقة'),
            )
          else
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _OverdueRow(entry: top[i], l10n: l10n),
            ],
        ],
      ),
    );
  }
}

class _OverdueRow extends StatelessWidget {
  final OverdueCustomer entry;
  final AppLocalizations? l10n;

  const _OverdueRow({required this.entry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final customer = entry.customer;
    final name = customer.cardName.isNotEmpty
        ? customer.cardName
        : customer.customerName;

    final ageLabel = entry.ageUnknown
        ? dashTr(context, l10n, 'noPaymentYet',
            en: 'No payment yet', he: 'טרם שולם', ar: 'لم يتم الدفع بعد')
        : '${dashTr(context, l10n, 'unpaidFor', en: 'Unpaid', he: 'לא שילם', ar: 'لم يدفع')} '
            '${count(entry.days)} ${dashTr(context, l10n, 'days', en: 'days', he: 'ימים', ar: 'أيام')}';

    // The dashboard already holds full Customer objects, so the detail screen
    // can be opened directly instead of bouncing through the customers list.
    void open() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(customer: customer),
          ),
        );

    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.assistant(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ageLabel,
                    style: GoogleFonts.assistant(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              money(entry.debt),
              style: GoogleFonts.assistant(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Order pipeline
// ─────────────────────────────────────────────────────────────────

class _PipelineCard extends StatelessWidget {
  final List<Order> orders;
  final bool loading;
  final VoidCallback onTap;
  final AppLocalizations? l10n;

  const _PipelineCard({
    required this.orders,
    required this.loading,
    required this.onTap,
    required this.l10n,
  });

  static String _statusLabel(
      BuildContext context, AppLocalizations? l10n, OrderStatus status) {
    return switch (status) {
      OrderStatus.active => dashTr(context, l10n, 'active',
          en: 'Active', he: 'פעילה', ar: 'نشطة'),
      OrderStatus.preparing => dashTr(context, l10n, 'preparing',
          en: 'Preparing', he: 'בהכנה', ar: 'قيد التحضير'),
      OrderStatus.sentToSupplier => dashTr(context, l10n, 'sentToSupplier',
          en: 'Sent to supplier', he: 'נשלח לסוכן', ar: 'أُرسل للمورد'),
      OrderStatus.inAssembly => dashTr(context, l10n, 'inAssembly',
          en: 'In assembly', he: 'בהרכבה', ar: 'قيد التركيب'),
      OrderStatus.awaitingShipping => dashTr(context, l10n, 'awaitingShipping',
          en: 'Ready for pickup', he: 'מוכן לאיסוף', ar: 'جاهز للاستلام'),
      OrderStatus.handled => dashTr(context, l10n, 'handled',
          en: 'Handled', he: 'טופל', ar: 'تمت المعالجة'),
      OrderStatus.delivered => dashTr(context, l10n, 'delivered',
          en: 'Delivered', he: 'נמסרה', ar: 'تم التسليم'),
      OrderStatus.canceled => dashTr(context, l10n, 'canceled',
          en: 'Canceled', he: 'מבוטלת', ar: 'ملغاة'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final counts = ordersByStatus(orders);
    // Workflow stages read as an ordered scale; canceled sits outside it.
    final workflow = OrderStatusExtension.all
        .where((s) => s != OrderStatus.canceled)
        .toList();
    final ramp = rampSteps(workflow.length);

    final segments = <BarSegment>[
      for (var i = 0; i < workflow.length; i++)
        if (counts.containsKey(workflow[i]))
          BarSegment(
            label: _statusLabel(context, l10n, workflow[i]),
            count: counts[workflow[i]]!,
            color: ramp[i],
          ),
      if (counts.containsKey(OrderStatus.canceled))
        BarSegment(
          label: _statusLabel(context, l10n, OrderStatus.canceled),
          count: counts[OrderStatus.canceled]!,
          color: AppTheme.outlineVariant,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.conveyor_belt,
            color: AppTheme.secondary,
            title: dashTr(context, l10n, 'orderPipeline',
                en: 'Order pipeline', he: 'צנרת הזמנות', ar: 'مسار الطلبات'),
            subtitle: dashTr(context, l10n, 'orderPipelineSubtitle',
                en: 'All orders by status',
                he: 'כל ההזמנות לפי סטטוס',
                ar: 'جميع الطلبات حسب الحالة'),
            trailing: IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              color: AppTheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const SizedBox(
              height: 160,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _PipelineFigure(
                    label: dashTr(context, l10n, 'activeOrders',
                        en: 'Active orders',
                        he: 'הזמנות פעילות',
                        ar: 'الطلبات النشطة'),
                    value: count(activeOrderCount(orders)),
                    color: AppTheme.secondary,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PipelineFigure(
                    label: dashTr(context, l10n, 'ordersInProgress',
                        en: 'In progress',
                        he: 'הזמנות בטיפול',
                        ar: 'قيد المعالجة'),
                    value: count(inProgressOrderCount(orders)),
                    color: AppTheme.primary,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (segments.isEmpty)
              DashEmptyState(
                icon: Icons.inbox_rounded,
                message: dashTr(context, l10n, 'noOrders',
                    en: 'No orders yet',
                    he: 'אין הזמנות עדיין',
                    ar: 'لا توجد طلبات بعد'),
              )
            else
              SegmentedProportionBar(
                segments: segments,
                stackedLegend: true,
                onTap: onTap,
              ),
          ],
        ],
      ),
    );
  }
}

class _PipelineFigure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _PipelineFigure({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.assistant(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.assistant(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────────────────────────

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.go, required this.l10n});

  final void Function(int) go;
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, int)>[
      (
        Icons.add_shopping_cart_rounded,
        dashTr(context, l10n, 'newOrder',
            en: 'New order', he: 'הזמנה חדשה', ar: 'طلب جديد'),
        2
      ),
      (
        Icons.payment_rounded,
        dashTr(context, l10n, 'newPayment',
            en: 'New payment', he: 'תשלום חדש', ar: 'دفعة جديدة'),
        4
      ),
      (
        Icons.person_add_rounded,
        dashTr(context, l10n, 'newCustomer',
            en: 'New customer', he: 'לקוח חדש', ar: 'عميل جديد'),
        1
      ),
      (
        Icons.storefront_rounded,
        dashTr(context, l10n, 'suppliers',
            en: 'Suppliers', he: 'סוכנים', ar: 'الموردون'),
        6
      ),
      (
        Icons.inventory_2_outlined,
        dashTr(context, l10n, 'inventory',
            en: 'Inventory', he: 'מלאי', ar: 'المخزون'),
        7
      ),
      (
        Icons.build_circle_outlined,
        dashTr(context, l10n, 'fixing',
            en: 'Fixing', he: 'תיקונים', ar: 'الإصلاحات'),
        3
      ),
      (
        Icons.build_rounded,
        dashTr(context, l10n, 'assemblies',
            en: 'Assemblies', he: 'הרכבות', ar: 'التركيبات'),
        5
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashCardHeader(
            icon: Icons.flash_on_rounded,
            color: AppTheme.secondary,
            title: dashTr(context, l10n, 'quickActions',
                en: 'Quick actions',
                he: 'פעולות מהירות',
                ar: 'إجراءات سريعة'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in actions)
                _ActionChip(icon: a.$1, label: a.$2, onTap: () => go(a.$3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.secondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.assistant(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
