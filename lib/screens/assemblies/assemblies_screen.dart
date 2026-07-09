import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../providers/providers.dart';
import '../../theme/order_status_colors.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/editorial_screen_title.dart';

class AssembliesScreen extends ConsumerStatefulWidget {
  const AssembliesScreen({super.key});

  @override
  ConsumerState<AssembliesScreen> createState() => _AssembliesScreenState();
}

class _AssembliesScreenState extends ConsumerState<AssembliesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _t(AppLocalizations? l10n, String key, String fallback) {
    final v = l10n?.tr(key);
    if (v == null || v.isEmpty || v == key) return fallback;
    return v;
  }

  String get _q => _searchCtrl.text.trim().toLowerCase();

  List<Order> _filter(List<Order> orders) {
    if (_q.isEmpty) return orders;
    return orders.where((o) {
      final numStr = (o.orderNumber?.toString() ?? '').toLowerCase();
      final card = (o.cardName ?? '').toLowerCase();
      final name = (o.customerName ?? '').toLowerCase();
      if (numStr.contains(_q) || card.contains(_q) || name.contains(_q)) {
        return true;
      }
      for (final it in o.items) {
        if (it.name.toLowerCase().contains(_q)) return true;
        if ((it.itemNumber ?? '').toLowerCase().contains(_q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assembliesAsync = ref.watch(assemblyOrdersProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: l10n?.tr('assemblies') ?? 'Assemblies',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Material(
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.assistant(color: AppTheme.onSurface),
                decoration: InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                  labelText: _t(
                    l10n,
                    'searchAssembliesHint',
                    'Search by order #, customer, card, item…',
                  ),
                  labelStyle: GoogleFonts.assistant(
                    color: AppTheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  floatingLabelStyle: GoogleFonts.assistant(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.secondary,
                  ),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: _t(l10n, 'clear', 'Clear'),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                  filled: true,
                  fillColor: AppTheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: AppTheme.secondary,
                      width: 1.6,
                    ),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(8, 14, 12, 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: assembliesAsync.when(
              data: (orders) {
                final filtered = _filter(orders);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.build_outlined,
                          size: 80,
                          color: AppTheme.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _q.isEmpty
                              ? (l10n?.tr('noData') ?? 'No assemblies')
                              : _t(
                                  l10n,
                                  'noMatchingAssemblies',
                                  'No assemblies match your search',
                                ),
                          style: GoogleFonts.assistant(
                            color: AppTheme.onSurfaceVariant,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    return _AssemblyCard(
                      order: filtered[index],
                      l10n: l10n,
                      ref: ref,
                      listIndex: index,
                    );
                  },
                );
              },
              loading: () => const AppLoadingOverlay(
                isLoading: true,
                child: SizedBox.expand(),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.error,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${l10n?.tr('error') ?? 'Error'}: $e',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.assistant(
                          color: AppTheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => ref.invalidate(assemblyOrdersProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          l10n?.tr('retry') ?? 'Retry',
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.secondaryContainer
                              .withValues(alpha: 0.45),
                          foregroundColor: AppTheme.secondary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAssemblyDate(DateTime d) => AppDateFormat.table(d);

String _daysUntilSnippet(BuildContext context, int? daysUntil) {
  if (daysUntil == null) return '';
  final lang = Localizations.localeOf(context).languageCode;
  if (lang == 'he') return ' · $daysUntil ימים';
  if (lang == 'ar') return ' · $daysUntil أيام';
  return ' · ${daysUntil}d';
}

class _AssemblyCard extends StatelessWidget {
  final Order order;
  final AppLocalizations? l10n;
  final WidgetRef ref;
  final int listIndex;

  const _AssemblyCard({
    required this.order,
    required this.l10n,
    required this.ref,
    required this.listIndex,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = orderStatusColor(order.status);
    final statusLabel =
        orderStatusLocalizedLabel(order.status, l10n);

    final daysUntil = order.assemblyDate?.difference(DateTime.now()).inDays;
    final isUrgent = daysUntil != null && daysUntil <= 2;

    final card = order.cardName?.trim() ?? '';
    final cust = order.customerName?.trim() ?? '';
    final displayTitle = (card.isEmpty && cust.isEmpty)
        ? ''
        : card.isEmpty
            ? cust
            : cust.isEmpty
                ? card
                : '$card — $cust';

    Widget statusChip() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            orderStatusDot(statusColor, size: 8),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.assistant(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget? dateChip() {
      if (order.assemblyDate == null) return null;
      final dateStr = _formatAssemblyDate(order.assemblyDate!);
      final extra = _daysUntilSnippet(context, daysUntil);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isUrgent
              ? AppTheme.error.withValues(alpha: 0.1)
              : AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUrgent
                ? AppTheme.error.withValues(alpha: 0.35)
                : AppTheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_rounded,
              size: 15,
              color: isUrgent ? AppTheme.error : AppTheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '$dateStr$extra',
              style: GoogleFonts.assistant(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isUrgent ? AppTheme.error : AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUrgent
              ? AppTheme.error.withValues(alpha: 0.45)
              : AppTheme.outlineVariant.withValues(alpha: 0.2),
          width: isUrgent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isUrgent ? 0.06 : 0.04),
            blurRadius: isUrgent ? 20 : 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: listIndex == 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppTheme.secondary,
          collapsedIconColor: AppTheme.onSurfaceVariant,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.secondary.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.handyman_rounded,
              color: AppTheme.secondary,
              size: 24,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '#${order.orderNumber ?? '—'}',
                  style: GoogleFonts.assistant(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.secondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.assistant(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                statusChip(),
                if (dateChip() != null) dateChip()!,
              ],
            ),
          ),
          children: [
            if (order.items.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < order.items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: AppTheme.outlineVariant.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      _AssemblyLineTile(
                        item: order.items[i],
                        l10n: l10n,
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (order.status == OrderStatus.active ||
                order.status == OrderStatus.inAssembly)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n?.tr('changeStatus') ?? 'Change status',
                    style: GoogleFonts.assistant(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (order.status == OrderStatus.active)
                        FilledButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            order,
                            OrderStatus.inAssembly.dbValue,
                          ),
                          icon: const Icon(Icons.build_rounded, size: 18),
                          label: Text(
                            orderStatusLocalizedLabel(
                              OrderStatus.inAssembly,
                              l10n,
                            ),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.warning,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      if (order.status == OrderStatus.inAssembly)
                        FilledButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            order,
                            OrderStatus.handled.dbValue,
                          ),
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: Text(
                            orderStatusLocalizedLabel(
                              OrderStatus.handled,
                              l10n,
                            ),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    Order order,
    String newStatus,
  ) async {
    final username = ref.read(currentUsernameProvider);
    await ref
        .read(orderServiceProvider)
        .updateStatus(order.id, newStatus, username);
    ref.invalidate(assemblyOrdersProvider);
    ref.invalidate(ordersProvider);
  }
}

class _AssemblyLineTile extends StatelessWidget {
  final OrderItem item;
  final AppLocalizations? l10n;

  const _AssemblyLineTile({
    required this.item,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isAssembly = item.assemblyRequired;
    return Opacity(
      opacity: isAssembly ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isAssembly ? Icons.build_circle_rounded : Icons.remove_circle_outline_rounded,
              size: 22,
              color: isAssembly
                  ? AppTheme.secondary
                  : AppTheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.assistant(
                    fontWeight:
                        isAssembly ? FontWeight.w800 : FontWeight.w600,
                    color: isAssembly
                        ? AppTheme.onSurface
                        : AppTheme.onSurfaceVariant,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
                if (item.roomName?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.roomName!,
                    style: GoogleFonts.assistant(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              '${l10n?.tr('quantity') ?? 'Qty'}: ${formatQty(item.quantity)}',
              style: GoogleFonts.assistant(
                color: AppTheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
