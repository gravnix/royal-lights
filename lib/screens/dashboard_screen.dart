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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static String _t(AppLocalizations? l10n, String key, String fallback) {
    final v = l10n?.tr(key);
    if (v != null && v.isNotEmpty && v != key) return v;
    return fallback;
  }

  /// Like [_t] but when ARB is missing/stale, uses [context] language — not English-only.
  static String _tr(
    BuildContext context,
    AppLocalizations? l10n,
    String key, {
    required String en,
    required String he,
    required String ar,
  }) {
    final v = l10n?.tr(key);
    if (v != null && v.isNotEmpty && v != key) return v;
    return switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isOnOrAfter(DateTime? d, DateTime threshold) {
    if (d == null) return false;
    return !d.isBefore(threshold);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final username = ref.watch(currentUsernameProvider);
    final ordersAsync = ref.watch(ordersProvider);
    final customersAsync = ref.watch(customersProvider);
    final fixingAsync = ref.watch(fixingTicketsProvider);
    final assembliesAsync = ref.watch(assemblyOrdersProvider);
    final inventoryAsync = ref.watch(inventoryItemsProvider);

    final now = DateTime.now();
    final today = _dateOnly(now);
    final weekStart = today.subtract(const Duration(days: 6));
    final localeName = Localizations.localeOf(context).toString();
    final dateLabel =
        DateFormat('EEEE, d MMMM y', localeName).format(now);

    final orders = ordersAsync.value ?? const [];
    final customers = customersAsync.value ?? const [];
    final tickets = fixingAsync.value ?? const [];
    final assemblies = assembliesAsync.value ?? const [];
    final inventoryItems = inventoryAsync.value ?? const [];

    final totalStockUnits = inventoryItems.fold<int>(
      0,
      (sum, item) => sum + item.availableStock,
    );
    final stockSkuCount = inventoryItems.length;
    final stockOutCount =
        inventoryItems.where((i) => i.availableStock == 0).length;
    final stockLowCount = inventoryItems
        .where((i) => i.availableStock > 0 && i.availableStock < 3)
        .length;
    final stockOkCount =
        inventoryItems.where((i) => i.availableStock >= 3).length;

    final ordersToday =
        orders.where((o) => _isOnOrAfter(o.createdAt, today)).length;
    final ordersWeek =
        orders.where((o) => _isOnOrAfter(o.createdAt, weekStart)).length;
    final openOrdersCount = orders
        .where(
          (o) =>
              o.status != OrderStatus.delivered &&
              o.status != OrderStatus.canceled,
        )
        .length;
    final sentToSupplierCount =
        orders.where((o) => o.status == OrderStatus.sentToSupplier).length;
    final awaitingShippingCount =
        orders.where((o) => o.status == OrderStatus.awaitingShipping).length;

    final fixingOpen = tickets.length;
    final fixingToday =
        tickets.where((t) => _isOnOrAfter(t.createdAt, today)).length;
    final fixingWeek =
        tickets.where((t) => _isOnOrAfter(t.createdAt, weekStart)).length;

    final debtCustomers =
        customers.where((c) => c.remainingDebt > 0).toList();
    final debtBelow5k = debtCustomers
        .where((c) => c.remainingDebt < 5000)
        .length;
    final debt5to10k = debtCustomers
        .where((c) => c.remainingDebt >= 5000 && c.remainingDebt < 10000)
        .length;
    final debtAbove10k =
        debtCustomers.where((c) => c.remainingDebt >= 10000).length;

    final loading =
        ordersAsync.isLoading ||
        customersAsync.isLoading ||
        fixingAsync.isLoading;

    void go(int index) =>
        ref.read(selectedNavIndexProvider.notifier).setIndex(index);

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
            // ── Header ─────────────────────────────────────────────────
            EditorialScreenTitle(
              title: _t(l10n, 'dashboard', 'Dashboard'),
              subtitle: Text(
                dateLabel,
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
                      child: const Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: AppTheme.secondary,
                      ),
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

            // ── Content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedFadeIn(
                duration: AppAnimations.durationMedium,
                slideUp: true,
                scaleBegin: 0.98,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    const gap = 14.0;

                    // ── Row 1: three hero KPI cards ─────────────────
                    final heroRow = _buildRow(gap, [
                      Expanded(
                        flex: 2,
                        child: _KpiCard(
                          label: _t(l10n, 'openOrders', 'Open orders'),
                          value: loading ? null : openOrdersCount,
                          icon: Icons.pending_actions_rounded,
                          accentColor: AppTheme.secondary,
                          onTap: () => go(2),
                          badge: _t(l10n, 'orders', 'Orders'),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _KpiCard(
                          label: _t(l10n, 'totalUnpaidDebts', 'Customers in debt'),
                          value: loading ? null : debtCustomers.length,
                          icon: Icons.account_balance_wallet_rounded,
                          accentColor: AppTheme.error,
                          onTap: () => go(1),
                          badge: _t(l10n, 'customers', 'Customers'),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _KpiCard(
                          label: _t(
                            l10n,
                            'pendingFixing',
                            'Open repair tickets',
                          ),
                          value: loading ? null : fixingOpen,
                          icon: Icons.build_circle_outlined,
                          accentColor: AppTheme.warning,
                          onTap: () => go(3),
                          badge: _t(l10n, 'fixing', 'Fixing'),
                        ),
                      ),
                      if (wide)
                        Expanded(
                          flex: 2,
                          child: _KpiCard(
                            label: _t(
                              l10n,
                              'upcomingAssemblies',
                              'Upcoming assemblies',
                            ),
                            value:
                                assembliesAsync.isLoading
                                    ? null
                                    : assemblies.length,
                            icon: Icons.build_rounded,
                            accentColor: AppTheme.accentBlue,
                            onTap: () => go(5),
                            badge: _t(l10n, 'assemblies', 'Assemblies'),
                            accentIsDark: true,
                          ),
                        ),
                    ]);

                    // ── Row 2: time-window stats ─────────────────────
                    final statsRow = _buildRow(gap, [
                      Expanded(
                        child: _StatTile(
                          title: _t(l10n, 'orders', 'Orders'),
                          label: _t(l10n, 'today', 'Today'),
                          value: loading ? null : ordersToday,
                          icon: Icons.fiber_new_rounded,
                          color: AppTheme.secondary,
                          onTap: () => go(2),
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          title: _t(l10n, 'orders', 'Orders'),
                          label: _t(l10n, 'thisWeek', 'This week'),
                          value: loading ? null : ordersWeek,
                          icon: Icons.calendar_view_week_rounded,
                          color: AppTheme.secondary,
                          onTap: () => go(2),
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          title: _t(l10n, 'sentToSupplier', 'Sent to supplier'),
                          label: _t(l10n, 'status', 'Status'),
                          value: loading ? null : sentToSupplierCount,
                          icon: Icons.send_rounded,
                          color: AppTheme.warning,
                          onTap: () => go(2),
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          title: _t(
                            l10n,
                            'awaitingShipping',
                            'Ready for pickup',
                          ),
                          label: _t(l10n, 'status', 'Status'),
                          value: loading ? null : awaitingShippingCount,
                          icon: Icons.local_shipping_outlined,
                          color: AppTheme.accentBlue,
                          onTap: () => go(2),
                          colorIsDark: true,
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          title: _t(l10n, 'fixing', 'Fixing'),
                          label: _t(l10n, 'today', 'Today'),
                          value: loading ? null : fixingToday,
                          icon: Icons.today_rounded,
                          color: AppTheme.warning,
                          onTap: () => go(3),
                        ),
                      ),
                      Expanded(
                        child: _StatTile(
                          title: _t(l10n, 'fixing', 'Fixing'),
                          label: _t(l10n, 'thisWeek', 'This week'),
                          value: loading ? null : fixingWeek,
                          icon: Icons.calendar_view_week_rounded,
                          color: AppTheme.warning,
                          onTap: () => go(3),
                        ),
                      ),
                    ]);

                    // ── Row 3: debt breakdown card ────────────────────
                    final debtRow = _DebtCard(
                      loading: loading,
                      below5k: debtBelow5k,
                      mid: debt5to10k,
                      above10k: debtAbove10k,
                      onTap: () => go(1),
                      l10n: l10n,
                    );

                    // ── Row 4: inventory / stock overview ───────────
                    final stockRow = _StockCard(
                      loading: inventoryAsync.isLoading,
                      totalUnits: totalStockUnits,
                      skuCount: stockSkuCount,
                      outCount: stockOutCount,
                      lowCount: stockLowCount,
                      okCount: stockOkCount,
                      onTap: () => go(7),
                      l10n: l10n,
                    );

                    // ── Row 5: quick actions + AI placeholder ─────────
                    final actionsRow = _buildRow(gap, [
                      Expanded(
                        flex: 3,
                        child: _QuickActionsCard(go: go, l10n: l10n),
                      ),
                      Expanded(
                        flex: 2,
                        child: _AiPlaceholderCard(l10n: l10n),
                      ),
                    ]);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heroRow,
                        const SizedBox(height: gap),
                        statsRow,
                        const SizedBox(height: gap),
                        debtRow,
                        const SizedBox(height: gap),
                        stockRow,
                        const SizedBox(height: gap),
                        actionsRow,
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

  Widget _buildRow(double gap, List<Widget> children) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Hero KPI card  (big number + accent top-border)
// ─────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    required this.badge,
    this.accentIsDark = false,
  });

  final String label;
  final int? value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final String badge;
  final bool accentIsDark;

  @override
  Widget build(BuildContext context) {
    final iconBg = accentColor.withValues(alpha: 0.10);
    final iconBorder = accentColor.withValues(alpha: 0.22);

    return Material(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Colored top stripe
                Container(height: 4, color: accentColor),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: iconBorder),
                            ),
                            child: Icon(icon, size: 20, color: accentColor),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              badge,
                              style: GoogleFonts.assistant(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onSurfaceVariant,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      value == null
                          ? SizedBox(
                              height: 36,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              '$value',
                              style: GoogleFonts.assistant(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                color: accentColor,
                                height: 1,
                              ),
                            ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.assistant(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurfaceVariant,
                        ),
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

// ─────────────────────────────────────────────────────────────────
// Stat tile — compact, horizontal layout
// ─────────────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
    this.colorIsDark = false,
  });

  final String title;
  final String label;
  final int? value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool colorIsDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppTheme.outlineVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              value == null
                  ? SizedBox(
                      height: 26,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      '$value',
                      style: GoogleFonts.assistant(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.onSurface,
                        height: 1,
                      ),
                    ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.assistant(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onSurface,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                style: GoogleFonts.assistant(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Debt breakdown card
// ─────────────────────────────────────────────────────────────────
class _DebtCard extends StatelessWidget {
  const _DebtCard({
    required this.loading,
    required this.below5k,
    required this.mid,
    required this.above10k,
    required this.onTap,
    required this.l10n,
  });

  final bool loading;
  final int below5k;
  final int mid;
  final int above10k;
  final VoidCallback onTap;
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    String t(String key, String fallback) =>
        DashboardScreen._t(l10n, key, fallback);

    return Material(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 18,
                      color: AppTheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('totalUnpaidDebts', 'Customers in Debt'),
                        style: GoogleFonts.assistant(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onSurface,
                        ),
                      ),
                      Text(
                        t('openDebtLabel', 'Open balance breakdown'),
                        style: GoogleFonts.assistant(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.outlineVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 1,
                color: AppTheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _DebtBucket(
                        range: '< ₪5,000',
                        count: loading ? null : below5k,
                        color: AppTheme.success,
                        label: t('debtLowToHigh', 'Low'),
                      ),
                    ),
                    Container(
                      width: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    Expanded(
                      child: _DebtBucket(
                        range: '₪5,000 – ₪10,000',
                        count: loading ? null : mid,
                        color: AppTheme.warning,
                        label: t('partial', 'Medium'),
                      ),
                    ),
                    Container(
                      width: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    Expanded(
                      child: _DebtBucket(
                        range: '> ₪10,000',
                        count: loading ? null : above10k,
                        color: AppTheme.error,
                        label: t('debtHighToLow', 'High'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtBucket extends StatelessWidget {
  const _DebtBucket({
    required this.range,
    required this.count,
    required this.color,
    required this.label,
  });

  final String range;
  final int? count;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.assistant(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 8),
        count == null
            ? SizedBox(
                height: 30,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
                ),
              )
            : Text(
                '$count',
                style: GoogleFonts.assistant(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
        const SizedBox(height: 4),
        Text(
          range,
          style: GoogleFonts.assistant(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Stock overview (inventory)
// ─────────────────────────────────────────────────────────────────
class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.loading,
    required this.totalUnits,
    required this.skuCount,
    required this.outCount,
    required this.lowCount,
    required this.okCount,
    required this.onTap,
    required this.l10n,
  });

  final bool loading;
  final int totalUnits;
  final int skuCount;
  final int outCount;
  final int lowCount;
  final int okCount;
  final VoidCallback onTap;
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    String tr(
      String key, {
      required String en,
      required String he,
      required String ar,
    }) =>
        DashboardScreen._tr(context, l10n, key, en: en, he: he, ar: ar);

    return Material(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: AppTheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(
                            'dashboardStockOverview',
                            en: 'Stock overview',
                            he: 'מצב מלאי',
                            ar: 'نظرة عامة على المخزون',
                          ),
                          style: GoogleFonts.assistant(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        Text(
                          tr(
                            'dashboardStockSubtitle',
                            en: 'Units on hand across catalogue items',
                            he: 'יחידות במלאי בכל פריטי הקטלוג',
                            ar: 'الوحدات المتاحة عبر أصناف الكتالوج',
                          ),
                          style: GoogleFonts.assistant(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.outlineVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 1,
                color: AppTheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _StockHeadline(
                        label: tr(
                          'dashboardTotalUnits',
                          en: 'Total units',
                          he: 'סה״כ יחידות',
                          ar: 'إجمالي الوحدات',
                        ),
                        value: loading ? null : totalUnits,
                        color: AppTheme.secondary,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    Expanded(
                      child: _StockHeadline(
                        label: tr(
                          'dashboardCatalogueLines',
                          en: 'Catalogue lines',
                          he: 'מספר פריטים',
                          ar: 'عدد الأصناف',
                        ),
                        value: loading ? null : skuCount,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 1,
                color: AppTheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _StockBucket(
                        title: tr(
                          'dashboardStockOut',
                          en: 'Out of stock',
                          he: 'אזל מהמלאי',
                          ar: 'نفد المخزون',
                        ),
                        count: loading ? null : outCount,
                        color: AppTheme.error,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    Expanded(
                      child: _StockBucket(
                        title: tr(
                          'dashboardStockLow',
                          en: 'Low (1–2)',
                          he: 'מלאי נמוך (1–2)',
                          ar: 'مخزون منخفض (1–2)',
                        ),
                        count: loading ? null : lowCount,
                        color: AppTheme.warning,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    Expanded(
                      child: _StockBucket(
                        title: tr(
                          'dashboardStockOk',
                          en: 'In stock (3+)',
                          he: 'מלאי תקין (3+)',
                          ar: 'مخزون جيد (3+)',
                        ),
                        count: loading ? null : okCount,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockHeadline extends StatelessWidget {
  const _StockHeadline({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.assistant(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        value == null
            ? SizedBox(
                height: 34,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
                ),
              )
            : Text(
                NumberFormat.decimalPattern(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(value!),
                style: GoogleFonts.assistant(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
      ],
    );
  }
}

class _StockBucket extends StatelessWidget {
  const _StockBucket({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int? count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        count == null
            ? SizedBox(
                height: 30,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
                ),
              )
            : Text(
                '$count',
                style: GoogleFonts.assistant(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.assistant(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Quick actions card
// ─────────────────────────────────────────────────────────────────
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.go, required this.l10n});

  final void Function(int) go;
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    String t(String key, String fallback) =>
        DashboardScreen._t(l10n, key, fallback);

    final actions = [
      (Icons.add_shopping_cart_rounded, t('newOrder', 'New Order'), 2),
      (Icons.payment_rounded, t('newPayment', 'New Payment'), 4),
      (Icons.person_add_rounded, t('newCustomer', 'New Customer'), 1),
      (Icons.inventory_2_outlined, t('inventory', 'Inventory'), 7),
      (Icons.build_circle_outlined, t('fixing', 'Fixing'), 3),
      (Icons.build_rounded, t('assemblies', 'Assemblies'), 5),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  size: 18,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                t('quickActions', 'Quick actions'),
                style: GoogleFonts.assistant(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions
                .map(
                  (a) => _ActionChip(
                    icon: a.$1,
                    label: a.$2,
                    onTap: () => go(a.$3),
                  ),
                )
                .toList(),
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

// ─────────────────────────────────────────────────────────────────
// AI placeholder card
// ─────────────────────────────────────────────────────────────────
class _AiPlaceholderCard extends StatelessWidget {
  const _AiPlaceholderCard({required this.l10n});
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    String t(String key, String fallback) =>
        DashboardScreen._t(l10n, key, fallback);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.secondary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.22),
              ),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 20,
              color: AppTheme.secondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t('llmPlaceholder', 'AI Insights'),
            style: GoogleFonts.assistant(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(
              'aiComingSoon',
              'Chat assistant, analytics, and insights powered by AI — coming soon.',
            ),
            style: GoogleFonts.assistant(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              t('comingSoon', 'Coming soon'),
              style: GoogleFonts.assistant(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
