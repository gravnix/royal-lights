import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../providers/providers.dart';
import '../../widgets/app_dropdown_styles.dart';

class CreateFixingTicketDialog extends ConsumerStatefulWidget {
  const CreateFixingTicketDialog({super.key});

  @override
  ConsumerState<CreateFixingTicketDialog> createState() =>
      _CreateFixingTicketDialogState();
}

class _CreateFixingTicketDialogState
    extends ConsumerState<CreateFixingTicketDialog> {
  Customer? _selectedCustomer;
  bool _submitting = false;

  /// orderId -> orderItemId set
  final Map<String, Set<String>> _selectedItemIds = {};

  @override
  void dispose() {
    super.dispose();
  }

  bool _isSelected(Order o, OrderItem i) {
    final id = i.id;
    if (id == null) return false;
    return _selectedItemIds[o.id]?.contains(id) ?? false;
  }

  void _toggle(Order o, OrderItem i) {
    final id = i.id;
    if (id == null) return;
    setState(() {
      final set = _selectedItemIds.putIfAbsent(o.id, () => <String>{});
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
  }

  int get _totalSelected {
    var n = 0;
    for (final s in _selectedItemIds.values) {
      n += s.length;
    }
    return n;
  }

  DateTime? _warrantyEndDate(Order order, OrderItem item) {
    final d = _warrantyStartDate(order, item);
    final y = item.warrantyYears;
    if (d == null || y <= 0) return null;
    return DateTime(d.year + y, d.month, d.day);
  }

  DateTime? _warrantyStartDate(Order order, OrderItem item) {
    if (item.warrantyYears <= 0) return null;
    if (item.warrantyStartDate != null) return item.warrantyStartDate;
    final d = order.deliveryDate;
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    if (order.status == OrderStatus.delivered) return dd;
    if (!dd.isAfter(today)) return dd; // delivery date began
    return null;
  }

  String _t(AppLocalizations? l10n, String key, String fallback) {
    final v = l10n?.tr(key);
    if (v == null || v.isEmpty || v == key) return fallback;
    return v;
  }

  String _warrantyLabel(AppLocalizations? l10n, Order order, OrderItem item) {
    if (item.warrantyYears <= 0) {
      return _t(l10n, 'noWarranty', 'No warranty');
    }
    if (_warrantyStartDate(order, item) == null) {
      return _t(l10n, 'deliveryDateMissing', 'Delivery date missing');
    }
    final end = _warrantyEndDate(order, item);
    if (end == null) return _t(l10n, 'noWarranty', 'No warranty');
    final now = DateTime.now();
    final daysLeft = end.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (daysLeft < 0) {
      return _t(l10n, 'warrantyExpired', 'Warranty expired');
    }
    return '${_t(l10n, 'warrantyLeft', 'Warranty left')}: $daysLeft';
  }

  Color _warrantyColor(Order order, OrderItem item) {
    if (item.warrantyYears <= 0) return AppTheme.outline;
    if (_warrantyStartDate(order, item) == null) return AppTheme.warning;
    final end = _warrantyEndDate(order, item);
    if (end == null) return AppTheme.outline;
    final now = DateTime.now();
    final daysLeft = end.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (daysLeft < 0) return AppTheme.error;
    if (daysLeft <= 30) return AppTheme.warning;
    return AppTheme.success;
  }

  Widget _warrantyChip(AppLocalizations? l10n, Order order, OrderItem item) {
    final color = _warrantyColor(order, item);
    final label = _warrantyLabel(l10n, order, item);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: GoogleFonts.assistant(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _submit(List<Order> orders) async {
    final l10n = AppLocalizations.of(context);
    final c = _selectedCustomer;
    if (c == null) return;
    if (_totalSelected == 0) return;

    setState(() => _submitting = true);
    try {
      final username = ref.read(currentUsernameProvider);
      final items = <Map<String, dynamic>>[];
      for (final o in orders) {
        final set = _selectedItemIds[o.id];
        if (set == null || set.isEmpty) continue;
        for (final it in o.items) {
          final id = it.id;
          if (id == null) continue;
          if (!set.contains(id)) continue;
          items.add({
            'source_order_id': o.id,
            'source_order_item_id': id,
            'name': it.name,
            'item_number': it.itemNumber,
            'quantity': it.quantity,
            'notes': it.notes,
            'warranty_years': it.warrantyYears,
            'delivery_date': _warrantyStartDate(o, it)
                ?.toIso8601String()
                .split('T')
                .first,
          });
        }
      }

      await ref.read(fixingServiceProvider).createTicket(
            customerId: c.id,
            username: username,
            items: items,
          );
      ref.invalidate(fixingTicketsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customersAsync = ref.watch(customersProvider);

    final customer = _selectedCustomer;
    final ordersAsync = customer == null
        ? const AsyncValue<List<Order>>.data(<Order>[])
        : ref.watch(customerOrdersWithItemsProvider(customer.id));

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.build_circle_outlined,
                      color: AppTheme.secondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t(l10n, 'newFixingTicket', 'New fixing ticket'),
                      style: GoogleFonts.assistant(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: _t(l10n, 'cancel', 'Cancel'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    customersAsync.when(
                      data: (customers) {
                        final leading = dropdownLeadingSlot(
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: AppTheme.secondary,
                          ),
                        );
                        return SizedBox(
                          width: double.infinity,
                          child: DropdownMenu<Customer>(
                            key: ValueKey(_selectedCustomer?.id ?? 'none'),
                            initialSelection: _selectedCustomer,
                            width: 820,
                            enableFilter: true,
                            requestFocusOnTap: true,
                            leadingIcon: leading,
                            decorationBuilder: animatedDropdownDecorationBuilder(
                              label: Text(
                                _t(l10n, 'customerName', 'Customer'),
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              leadingIcon: leading,
                            ),
                            menuStyle: appDropdownMenuStyle(),
                            inputDecorationTheme:
                                paymentsFilterInputDecorationTheme(),
                            textStyle: GoogleFonts.assistant(
                              color: AppTheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (c) {
                              setState(() {
                                _selectedCustomer = c;
                                _selectedItemIds.clear();
                              });
                            },
                            dropdownMenuEntries: customers
                                .map(
                                  (c) => DropdownMenuEntry<Customer>(
                                    value: c,
                                    label: '${c.cardName} — ${c.customerName}',
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text(
                        '${l10n?.tr('error') ?? 'Error'}: $e',
                        style: GoogleFonts.assistant(color: AppTheme.error),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ordersAsync.when(
                        data: (orders) {
                          if (customer == null) {
                            return Center(
                              child: Text(
                                _t(l10n, 'selectCustomerFixing',
                                    'Select customer for fixing'),
                                style: GoogleFonts.assistant(
                                  color: AppTheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          if (orders.isEmpty) {
                            return Center(
                              child: Text(
                                _t(l10n, 'noOrdersForCustomer',
                                    'This customer has no orders yet.'),
                                style: GoogleFonts.assistant(
                                  color: AppTheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          return Scrollbar(
                            thumbVisibility: true,
                            child: ListView(
                              children: orders.map((o) {
                                final hasDelivery = o.deliveryDate != null;
                                final deliveryLabel = hasDelivery
                                    ? '${_t(l10n, 'deliveryDate', 'Delivery')}: ${AppDateFormat.table(o.deliveryDate!)}'
                                    : _t(l10n, 'deliveryDateMissing',
                                        'Delivery date missing');
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppTheme.outlineVariant
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: true,
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      title: Text(
                                        '#${o.orderNumber ?? o.id.substring(0, 6)}',
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.onSurface,
                                        ),
                                      ),
                                      subtitle: Text(
                                        deliveryLabel,
                                        style: GoogleFonts.assistant(
                                          color: AppTheme.onSurfaceVariant,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      children: o.items.map((it) {
                                        final selected = _isSelected(o, it);
                                        return InkWell(
                                          onTap: () => _toggle(o, it),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              8,
                                              16,
                                              10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Checkbox(
                                                  value: selected,
                                                  onChanged: (_) =>
                                                      _toggle(o, it),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style:
                                                            GoogleFonts.assistant(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              AppTheme.onSurface,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          _warrantyChip(
                                                              l10n, o, it),
                                                          if ((it.itemNumber ??
                                                                  '')
                                                              .trim()
                                                              .isNotEmpty)
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 10,
                                                                vertical: 6,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: AppTheme
                                                                    .surfaceContainerHighest
                                                                    .withValues(
                                                                        alpha: 0.35),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            999),
                                                              ),
                                                              child: Text(
                                                                it.itemNumber!,
                                                                style: GoogleFonts
                                                                    .assistant(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  fontSize: 12,
                                                                  color: AppTheme
                                                                      .onSurfaceVariant,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(
                          child: Text(
                            '${l10n?.tr('error') ?? 'Error'}: $e',
                            style:
                                GoogleFonts.assistant(color: AppTheme.error),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_t(l10n, 'selectedItemsCount', 'Selected')}: $_totalSelected',
                      style: GoogleFonts.assistant(
                        color: AppTheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(false),
                    child: Text(_t(l10n, 'cancel', 'Cancel')),
                  ),
                  const SizedBox(width: 10),
                  ordersAsync.when(
                    data: (orders) => FilledButton.icon(
                      onPressed: (_submitting ||
                              _selectedCustomer == null ||
                              _totalSelected == 0)
                          ? null
                          : () => _submit(orders),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        _t(l10n, 'createFixingOrder', 'Create'),
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

