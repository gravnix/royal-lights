import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/fixing_ticket_item.dart';
import '../../models/fixing_ticket.dart';
import '../../providers/providers.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/editorial_screen_title.dart';
import 'create_fixing_ticket_dialog.dart';

class FixingScreen extends ConsumerStatefulWidget {
  const FixingScreen({super.key});

  @override
  ConsumerState<FixingScreen> createState() => _FixingScreenState();
}

class _FixingScreenState extends ConsumerState<FixingScreen> {
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

  String _warrantyText(AppLocalizations? l10n, FixingTicketItem it) {
    if (it.warrantyYears <= 0) return _t(l10n, 'noWarranty', 'No warranty');
    if (it.deliveryDate == null) {
      return _t(l10n, 'deliveryDateMissing', 'Delivery date missing');
    }
    final end = it.warrantyEndDate;
    if (end == null) return _t(l10n, 'noWarranty', 'No warranty');
    final now = DateTime.now();
    final daysLeft =
        end.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (daysLeft < 0) return _t(l10n, 'warrantyExpired', 'Warranty expired');
    return '${_t(l10n, 'warrantyLeft', 'Warranty left')}: $daysLeft';
  }

  Color _warrantyColor(FixingTicketItem it) {
    if (it.warrantyYears <= 0) return AppTheme.outline;
    if (it.deliveryDate == null) return AppTheme.warning;
    final end = it.warrantyEndDate;
    if (end == null) return AppTheme.outline;
    final now = DateTime.now();
    final daysLeft =
        end.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (daysLeft < 0) return AppTheme.error;
    if (daysLeft <= 30) return AppTheme.warning;
    return AppTheme.success;
  }

  String get _q => _searchCtrl.text.trim().toLowerCase();

  List<FixingTicket> _filterTickets(List<FixingTicket> tickets) {
    final q = _q;
    if (q.isEmpty) return tickets;
    return tickets.where((t) {
      final card = (t.cardName ?? '').toLowerCase();
      final name = (t.customerName ?? '').toLowerCase();
      if (card.contains(q) || name.contains(q)) return true;
      for (final it in t.items) {
        if (it.name.toLowerCase().contains(q)) return true;
        if ((it.itemNumber ?? '').toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _confirmDelete(BuildContext context, FixingTicket t) async {
    final l10n = AppLocalizations.of(context);
    final title = (t.cardName?.trim().isNotEmpty ?? false)
        ? '${t.cardName} — ${t.customerName ?? ''}'.trim()
        : (t.customerName ?? t.customerId);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t(l10n, 'deleteFixingTicket', 'Delete fixing ticket?'),
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w900,
            color: AppTheme.onSurface,
          ),
        ),
        content: Text(
          '${_t(l10n, 'confirmDeleteFixingTicket', 'This will remove the fixing ticket for')}\n$title',
          style: GoogleFonts.assistant(
            color: AppTheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(l10n, 'cancel', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: AppTheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t(l10n, 'delete', 'Delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ref.read(fixingServiceProvider).deleteTicket(t.id);
    ref.invalidate(fixingTicketsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ticketsAsync = ref.watch(fixingTicketsProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.onPrimary,
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => const CreateFixingTicketDialog(),
          );
        },
        tooltip: _t(l10n, 'newFixingTicket', 'New fixing ticket'),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: _t(l10n, 'fixing', 'Fixing'),
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
                    'searchFixingHint',
                    'Search by customer, card name, item…',
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.secondary,
                  ),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: _t(l10n, 'clear', 'Clear'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _searchCtrl.clear()),
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
            child: ticketsAsync.when(
              data: (tickets) {
                final filtered = _filterTickets(tickets);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _q.isEmpty
                          ? _t(l10n, 'noFixingTickets', 'No fixing orders')
                          : _t(
                              l10n,
                              'noMatchingResults',
                              'No results',
                            ),
                      style: GoogleFonts.assistant(
                        color: AppTheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, idx) {
                    final t = filtered[idx];
                    final title = (t.cardName?.trim().isNotEmpty ?? false)
                        ? '${t.cardName} — ${t.customerName ?? ''}'.trim()
                        : (t.customerName ?? t.customerId);
                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: idx == 0,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          title: Text(
                            title,
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${_t(l10n, 'pendingFixing', 'Pending fixing')} • ${t.items.length} ${_t(l10n, 'itemsShort', 'items')}',
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: _t(l10n, 'actions', 'Actions'),
                            padding: EdgeInsets.zero,
                            onSelected: (value) async {
                              if (value == 'fixed') {
                                final username =
                                    ref.read(currentUsernameProvider);
                                await ref
                                    .read(fixingServiceProvider)
                                    .markFixed(t.id, username);
                                ref.invalidate(fixingTicketsProvider);
                              } else if (value == 'delete') {
                                await _confirmDelete(context, t);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'fixed',
                                child:
                                    Text(_t(l10n, 'markFixed', 'Mark fixed')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  _t(l10n, 'deleteFixingTicket', 'Delete'),
                                  style: GoogleFonts.assistant(
                                    color: AppTheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryContainer
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _t(l10n, 'actions', 'Actions'),
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.secondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: AppTheme.secondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          children: [
                            const SizedBox(height: 4),
                            ...t.items.map((it) {
                              final wc = _warrantyColor(it);
                              return ListTile(
                                title: Text(
                                  it.name,
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  _warrantyText(l10n, it),
                                  style: GoogleFonts.assistant(
                                    color: wc,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
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
                        onPressed: () => ref.invalidate(fixingTicketsProvider),
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
