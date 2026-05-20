import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_animations.dart';
import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../providers/providers.dart';
import '../../services/whatsapp_service.dart';
import '../../theme/order_status_colors.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/app_round_checkbox.dart';
import '../../widgets/confirm_send_customer_wa.dart';
import '../../widgets/editorial_screen_title.dart';
import 'order_form_screen.dart';

class _WorkflowActionDef {
  const _WorkflowActionDef({
    required this.label,
    required this.onPressed,
  });

  final String Function(AppLocalizations? l10n) label;
  final Future<void> Function() onPressed;
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _statusFilter = 'All';
  String _createdByFilter = 'All';
  int _sortColumnIndex = 4;
  bool _sortAscending = false;
  String? _updatingOrderId;
  int _currentPage = 1;
  final int _rowsPerPage = 15;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _searchQuery => _searchCtrl.text.trim().toLowerCase();

  void _resetFilters() {
    ref.read(ordersCustomerFilterProvider.notifier).setFilter(null);
    setState(() {
      _searchCtrl.clear();
      _statusFilter = 'All';
      _createdByFilter = 'All';
      _currentPage = 1;
    });
  }

  /// Localized orders search label; falls back if ARB key is missing (e.g. stale bundle).
  String _ordersSearchFieldLabel() {
    final l10n = AppLocalizations.of(context);
    final t = l10n?.tr('searchOrdersHint');
    if (t != null && t.isNotEmpty && t != 'searchOrdersHint') return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'ar' => 'بحث برقم الطلب أو البطاقة أو اسم العميل…',
      'en' => 'Search by order #, card name, customer…',
      _ => 'חיפוש לפי מספר הזמנה, כרטיס, שם לקוח…',
    };
  }

  String _t(AppLocalizations? l10n, String key, String fallback) {
    final v = l10n?.tr(key);
    if (v != null && v.isNotEmpty && v != key) return v;
    return fallback;
  }

  /// Like [_t] but when ARB is missing/stale, uses [context] language — not English-only.
  String _trLocale(
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

  String _formatOrderDate(DateTime? d) => AppDateFormat.tableOrDash(d);

  String _displayCreatedBy(
      BuildContext context, AppLocalizations? l10n, String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s.toLowerCase() == 'unknown') {
      return _trLocale(
        context,
        l10n,
        'createdByUnknown',
        en: 'Unknown',
        he: 'לא ידוע',
        ar: 'غير معروف',
      );
    }
    return s;
  }

  String _cancelSupplierMessageTemplate({
    required String languageCode,
    required Order order,
    required String itemsText,
  }) {
    final orderNo = order.orderNumber?.toString() ?? '-';
    return switch (languageCode) {
      'en' =>
        'Order cancellation notice\nOrder #$orderNo\n\n$itemsText\n\nPlease confirm cancellation.',
      'ar' =>
        'إشعار إلغاء الطلب\nرقم الطلب #$orderNo\n\n$itemsText\n\nيرجى تأكيد الإلغاء.',
      _ => 'הודעת ביטול הזמנה\nהזמנה #$orderNo\n\n$itemsText\n\nנא לאשר ביטול.',
    };
  }

  Future<void> _notifySuppliersOrderCanceled(Order order) async {
    final lang = Localizations.localeOf(context).languageCode;

    // Group items by supplier phone (one WhatsApp message per supplier).
    final Map<String, List<dynamic>> byPhone = {};
    for (final item in order.items) {
      final phone = (item.supplierPhone ?? '').trim();
      if (phone.isEmpty) continue;
      (byPhone[phone] ??= []).add(item);
    }

    bool isFirst = true;
    for (final entry in byPhone.entries) {
      final phone = entry.key.replaceAll(RegExp(r'[^\d+]'), '');
      if (phone.isEmpty) continue;

      final itemsText = entry.value.map((dynamic it) {
        final item = it as dynamic;
        final code = (item.itemNumber as String?)?.trim();
        final name = (item.name as String?)?.trim() ?? '';
        final qty = formatQty((item.quantity as num?)?.toDouble() ?? 1);
        final codePart = (code != null && code.isNotEmpty) ? '($code)\n' : '';
        return '$codePart$name\nQty: $qty';
      }).join('\n\n');

      final message = _cancelSupplierMessageTemplate(
        languageCode: lang,
        order: order,
        itemsText: itemsText,
      );

      if (!isFirst) {
        await Future.delayed(const Duration(seconds: 10));
      }
      await WhatsAppService.sendMessage(phone, message);
      isFirst = false;
    }
  }

  bool _shouldNotifySupplierOnCancel(Order order) {
    switch (order.status) {
      case OrderStatus.sentToSupplier:
      case OrderStatus.inAssembly:
        return true;
      case OrderStatus.preparing:
      case OrderStatus.awaitingShipping:
      case OrderStatus.handled:
        return order.items.any((i) {
          final sid = (i.supplierId ?? '').trim();
          return sid.isNotEmpty && !i.existingInStore;
        });
      case OrderStatus.active:
      case OrderStatus.delivered:
      case OrderStatus.canceled:
        return false;
    }
  }

  String _orderCancelDialogBody(
    BuildContext context,
    AppLocalizations? l10n,
    bool notifySupplier,
  ) {
    final lead = _trLocale(
      context,
      l10n,
      'orderCancelConfirmLead',
      en: 'The order will be marked as canceled. This cannot be undone.',
      he: 'ההזמנה תסומן כמבוטלת. לא ניתן לבטל פעולה זו.',
      ar: 'سيتم تعليم الطلب كملغى. لا يمكن التراجع.',
    );
    final supplierParagraph = notifySupplier
        ? _trLocale(
            context,
            l10n,
            'orderCancelConfirmSupplierNotify',
            en: 'Suppliers will be notified automatically with a cancellation message.',
            he: 'סוכנים יקבלו עדכון ביטול אוטומטית.',
            ar: 'سيتم إبلاغ الموردين تلقائيًا برسالة إلغاء.',
          )
        : _trLocale(
            context,
            l10n,
            'orderCancelConfirmNoSupplierWa',
            en: 'Suppliers will not be notified — this order was not sent to suppliers (or has no supplier lines).',
            he: 'לא תישלח הודעה לסוכנים — ההזמנה לא נשלחה לסוכנים (או שאין שורות סוכן).',
            ar: 'لن يُبلَّغ الموردون — لم يُرسَ الطلب للموردين (أو لا توجد بنود بمورد).',
          );
    return '$lead\n\n$supplierParagraph';
  }

  String _waCustomerOrderCanceled(String lang, Order order) {
    final n = order.orderNumber?.toString() ?? '?';
    return switch (lang) {
      'en' =>
        'Hello — we are canceling order #$n. If you have any questions, please contact us.',
      'ar' => 'مرحبًا — نُلغي الطلب رقم $n. لأي استفسار يُرجى التواصل معنا.',
      _ => 'שלום — אנו מבטלים את הזמנה מספר $n. לשאלות ניתן לפנות אלינו.',
    };
  }

  Future<void> _confirmAndCancelOrder(Order order) async {
    final l10n = AppLocalizations.of(context);
    if (_updatingOrderId != null) return;

    final notifySupplier = _shouldNotifySupplierOnCancel(order);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _trLocale(
            context,
            l10n,
            'orderCancelConfirmTitle',
            en: 'Cancel this order?',
            he: 'לבטל את ההזמנה?',
            ar: 'إلغاء هذا الطلب؟',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Text(
            _orderCancelDialogBody(context, l10n, notifySupplier),
            style: GoogleFonts.assistant(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t(l10n, 'cancel', 'Cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(
              _trLocale(
                context,
                l10n,
                'orderCancelConfirmAction',
                en: 'Yes, cancel order',
                he: 'כן, בטל הזמנה',
                ar: 'نعم، إلغاء الطلب',
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _updatingOrderId = order.id);
    try {
      final service = ref.read(orderServiceProvider);
      final fullOrder = await service.getById(order.id);
      if (!mounted) return;

      if (notifySupplier) {
        await _notifySuppliersOrderCanceled(fullOrder);
      }

      final customer =
          await ref.read(customerServiceProvider).getById(fullOrder.customerId);
      if (!mounted) return;
      final phone = customer.phones.isNotEmpty ? customer.phones.first : '';
      final lang = Localizations.localeOf(context).languageCode;
      if (phone.trim().isNotEmpty) {
        if (mounted && await confirmSendCustomerWhatsApp(context)) {
          await _openWhatsAppToPhone(
            phone,
            _waCustomerOrderCanceled(lang, fullOrder),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _trLocale(
                context,
                l10n,
                'orderCancelNoCustomerPhone',
                en: 'Customer has no phone — WhatsApp was not opened.',
                he: 'אין מספר טלפון ללקוח — WhatsApp לא נפתח.',
                ar: 'لا يوجد هاتف للعميل — لم يُفتح واتساب.',
              ),
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final username = ref.read(currentUsernameProvider);
      await service.cancelOrder(order.id, username);

      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(totalUnpaidDebtsProvider);
      final fc = ref.read(ordersCustomerFilterProvider);
      if (fc != null) {
        ref.invalidate(customerOrdersProvider(fc.id));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(l10n, 'canceled', 'Canceled'),
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_t(l10n, 'error', 'Error')}: $e',
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ordersCustomerFilter = ref.watch(ordersCustomerFilterProvider);
    final ordersAsync = ordersCustomerFilter != null
        ? ref.watch(customerOrdersProvider(ordersCustomerFilter.id))
        : ref.watch(ordersProvider);

    ref.listen<Customer?>(ordersCustomerFilterProvider, (previous, next) {
      if (previous?.id == next?.id || !mounted) return;
      setState(() => _currentPage = 1);
    });

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 0, // Hide standard appbar to use custom header
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.onPrimary,
        elevation: 2,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OrderFormScreen()),
          );
        },
        tooltip: l10n?.tr('newOrder') ?? 'New Order',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: l10n?.tr('orders') ?? 'Orders',
          ),

          // ─── Orders Table ─────────────────────────────
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                var filtered = orders.where((o) {
                  final isClosedStatusSelected = _statusFilter == 'Canceled' ||
                      _statusFilter == 'Delivered';
                  if (!isClosedStatusSelected &&
                      (o.status == OrderStatus.canceled ||
                          o.status == OrderStatus.delivered)) {
                    return false;
                  }
                  if (_statusFilter != 'All' &&
                      o.status.dbValue != _statusFilter) {
                    return false;
                  }
                  if (_createdByFilter != 'All' &&
                      (o.createdBy ?? '-') != _createdByFilter) {
                    return false;
                  }
                  if (_searchQuery.isNotEmpty) {
                    return (o.cardName ?? '')
                            .toLowerCase()
                            .contains(_searchQuery) ||
                        (o.customerName ?? '')
                            .toLowerCase()
                            .contains(_searchQuery) ||
                        (o.orderNumber?.toString() ?? '')
                            .contains(_searchQuery);
                  }
                  return true;
                }).toList();

                filtered.sort((a, b) {
                  int comp = 0;
                  switch (_sortColumnIndex) {
                    case 1:
                      comp = (a.orderNumber ?? 0).compareTo(b.orderNumber ?? 0);
                      break;
                    case 2:
                      comp = (a.cardName ?? '')
                          .toLowerCase()
                          .compareTo((b.cardName ?? '').toLowerCase());
                      break;
                    case 3:
                      comp = (a.customerName ?? '')
                          .toLowerCase()
                          .compareTo((b.customerName ?? '').toLowerCase());
                      break;
                    case 4:
                      final aDate =
                          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final bDate =
                          b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                      comp = aDate.compareTo(bDate);
                      break;
                    case 5:
                      comp = (a.createdBy ?? '')
                          .toLowerCase()
                          .compareTo((b.createdBy ?? '').toLowerCase());
                      break;
                    case 6:
                      comp = (a.assemblyRequired ? 1 : 0)
                          .compareTo(b.assemblyRequired ? 1 : 0);
                      break;
                    case 7:
                      comp = a.status.dbValue.compareTo(b.status.dbValue);
                      break;
                    case 8:
                      comp = a.totalPrice.compareTo(b.totalPrice);
                      break;
                    default:
                      comp = (a.orderNumber ?? 0).compareTo(b.orderNumber ?? 0);
                  }
                  return _sortAscending ? comp : -comp;
                });

                final uniqueCreators = [
                  'All',
                  ...orders
                      .map((o) => o.createdBy ?? '-')
                      .where((e) => e != '-')
                      .toSet()
                ];
                final totalItems = filtered.length;
                final totalPages = (totalItems / _rowsPerPage).ceil();
                int validCurrentPage = _currentPage;
                if (validCurrentPage > totalPages && totalPages > 0) {
                  validCurrentPage = totalPages;
                }
                final startIndex = (validCurrentPage - 1) * _rowsPerPage;
                final endIndex =
                    (startIndex + _rowsPerPage).clamp(0, totalItems);
                final paginatedFiltered = filtered.isEmpty
                    ? <Order>[]
                    : filtered.sublist(startIndex, endIndex);

                return AnimatedFadeIn(
                  duration: AppAnimations.durationMedium,
                  scaleBegin: 0.98,
                  child: Column(
                    children: [
                      // ─── Search & Filter Control Bar ──────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (ordersCustomerFilter != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_pin_circle_outlined,
                                      size: 22,
                                      color: AppTheme.secondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${ordersCustomerFilter.cardName} — ${ordersCustomerFilter.customerName}',
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: AppTheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        ref
                                            .read(
                                              ordersCustomerFilterProvider
                                                  .notifier,
                                            )
                                            .setFilter(null);
                                        setState(() {
                                          _currentPage = 1;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        l10n?.tr('clearFilter') ??
                                            'Clear filter',
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.secondary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Material(
                                    elevation: 2,
                                    shadowColor:
                                        Colors.black.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    child: TextField(
                                      controller: _searchCtrl,
                                      onChanged: (_) => setState(() {
                                        _currentPage = 1;
                                      }),
                                      style: GoogleFonts.assistant(
                                        color: AppTheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        floatingLabelBehavior:
                                            FloatingLabelBehavior.auto,
                                        floatingLabelAlignment:
                                            FloatingLabelAlignment.start,
                                        labelText: _ordersSearchFieldLabel(),
                                        labelStyle: GoogleFonts.assistant(
                                          color: AppTheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        floatingLabelStyle:
                                            GoogleFonts.assistant(
                                          color: AppTheme.secondary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: AppTheme.secondary,
                                        ),
                                        filled: true,
                                        fillColor:
                                            AppTheme.surfaceContainerLowest,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          borderSide: BorderSide(
                                            color: AppTheme.outlineVariant
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          borderSide: BorderSide(
                                            color: AppTheme.outlineVariant
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          borderSide: const BorderSide(
                                            color: AppTheme.secondary,
                                            width: 1.6,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.fromLTRB(
                                          8,
                                          14,
                                          12,
                                          14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  onPressed: _resetFilters,
                                  icon: const Icon(Icons.restart_alt_rounded,
                                      size: 22),
                                  label: Text(
                                    l10n?.tr('resetFilters') ?? 'Reset filters',
                                    style: GoogleFonts.assistant(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    backgroundColor: AppTheme.secondaryContainer
                                        .withValues(alpha: 0.45),
                                    foregroundColor: AppTheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 220,
                                  child: _buildCreatedByDropdown(
                                      uniqueCreators, l10n),
                                ),
                                SizedBox(
                                  width: 240,
                                  child: _buildStatusDropdown(l10n),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.shopping_cart_outlined,
                                        size: 64,
                                        color: AppTheme.outline
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 16),
                                    Text(
                                        l10n?.tr('noData') ?? 'לא נמצאו נתונים',
                                        style: GoogleFonts.assistant(
                                            color: AppTheme.onSurfaceVariant,
                                            fontSize: 16)),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 0, 24, 8),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            minWidth: constraints.maxWidth),
                                        child: ClipRRect(
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                            ),
                                            child: DataTable(
                                              showCheckboxColumn: false,
                                              horizontalMargin: 10,
                                              headingRowHeight: 52,
                                              dataRowMinHeight: 50,
                                              dataRowMaxHeight: 88,
                                              columnSpacing: 12,
                                              headingTextStyle:
                                                  GoogleFonts.assistant(
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    AppTheme.onSurfaceVariant,
                                                fontSize: 13,
                                              ),
                                              dataTextStyle:
                                                  GoogleFonts.assistant(
                                                color: AppTheme.onSurface,
                                                fontSize: 14,
                                              ),
                                              sortColumnIndex: _sortColumnIndex,
                                              sortAscending: _sortAscending,
                                              columns: [
                                                DataColumn(
                                                  label: Text(
                                                    _trLocale(
                                                      context,
                                                      l10n,
                                                      'orderWorkflowAction',
                                                      en: 'Action',
                                                      he: 'פעולה',
                                                      ar: 'إجراء',
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                      l10n?.tr('orderNumber') ??
                                                          'מספר הזמנה'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                      l10n?.tr('cardName') ??
                                                          'שם כרטיס'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(l10n?.tr(
                                                          'customerName') ??
                                                      'לקוח'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(l10n?.tr(
                                                          'creationDate') ??
                                                      'תאריך יצירה'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                      l10n?.tr('createdBy') ??
                                                          'נוצר ע״י'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(l10n?.tr(
                                                          'assemblyRequired') ??
                                                      'הרכבה'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                      l10n?.tr('status') ??
                                                          'סטטוס'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                      l10n?.tr('totalPrice') ??
                                                          'סה"כ'),
                                                  onSort: (col, asc) =>
                                                      setState(() {
                                                    _sortColumnIndex = col;
                                                    _sortAscending = asc;
                                                  }),
                                                ),
                                              ],
                                              rows: paginatedFiltered
                                                  .map((order) {
                                                final statusColor =
                                                    orderStatusColor(
                                                        order.status);
                                                final isUpdating =
                                                    _updatingOrderId ==
                                                        order.id;

                                                return DataRow(
                                                  onSelectChanged: (_) {
                                                    if (_updatingOrderId !=
                                                        null) {
                                                      return;
                                                    }
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            OrderFormScreen(
                                                                orderId:
                                                                    order.id),
                                                      ),
                                                    );
                                                  },
                                                  cells: [
                                                    DataCell(
                                                      _buildOrderWorkflowCell(
                                                        context,
                                                        l10n,
                                                        order,
                                                        isUpdating,
                                                      ),
                                                    ),
                                                    DataCell(
                                                      SizedBox(
                                                        width: 48,
                                                        child: Center(
                                                          child: Text(
                                                            '#${order.orderNumber ?? '-'}',
                                                            style: GoogleFonts
                                                                .assistant(
                                                              color: AppTheme
                                                                  .onSurface,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        order.cardName ?? '-',
                                                        style: GoogleFonts
                                                            .assistant(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600),
                                                      ),
                                                    ),
                                                    DataCell(Text(
                                                        order.customerName ??
                                                            '-')),
                                                    DataCell(
                                                      Text(
                                                        _formatOrderDate(
                                                          order.createdAt,
                                                        ),
                                                        style: GoogleFonts
                                                            .assistant(
                                                                color: AppTheme
                                                                    .onSurfaceVariant),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        _displayCreatedBy(
                                                          context,
                                                          l10n,
                                                          order.createdBy,
                                                        ),
                                                        style: GoogleFonts
                                                            .assistant(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: AppTheme
                                                                    .onSurfaceVariant),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      SizedBox(
                                                        width: 34,
                                                        child: Center(
                                                          child: Icon(
                                                            order.assemblyRequired
                                                                ? Icons
                                                                    .check_circle_rounded
                                                                : Icons
                                                                    .cancel_rounded,
                                                            color: order
                                                                    .assemblyRequired
                                                                ? AppTheme
                                                                    .success
                                                                : AppTheme
                                                                    .outline
                                                                    .withValues(
                                                                        alpha:
                                                                            0.5),
                                                            size: 18,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Tooltip(
                                                        message: _trLocale(
                                                          context,
                                                          l10n,
                                                          'orderWorkflowStatusLocked',
                                                          en: 'Status updates via the action button only.',
                                                          he: 'הסטטוס מתעדכן רק בכפתור הפעולה.',
                                                          ar: 'يتم تحديث الحالة فقط عبر زر الإجراء.',
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Flexible(
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 6,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: statusColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.12),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              20),
                                                                ),
                                                                child: isUpdating
                                                                    ? const SizedBox(
                                                                        width:
                                                                            16,
                                                                        height:
                                                                            16,
                                                                        child:
                                                                            CircularProgressIndicator(
                                                                          strokeWidth:
                                                                              2,
                                                                        ),
                                                                      )
                                                                    : Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.min,
                                                                        children: [
                                                                          orderStatusDot(
                                                                            statusColor,
                                                                            size:
                                                                                8,
                                                                          ),
                                                                          const SizedBox(
                                                                              width: 6),
                                                                          Flexible(
                                                                            child:
                                                                                Text(
                                                                              orderStatusLocalizedLabel(
                                                                                order.status,
                                                                                l10n,
                                                                              ),
                                                                              maxLines: 1,
                                                                              overflow: TextOverflow.ellipsis,
                                                                              style: GoogleFonts.assistant(
                                                                                color: statusColor,
                                                                                fontWeight: FontWeight.w700,
                                                                                fontSize: 12,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        '₪${order.totalPrice.toStringAsFixed(0)}',
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            )),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                      const Divider(height: 1),
                      _buildPaginationControls(
                          validCurrentPage, totalPages, totalItems),
                    ],
                  ),
                );
              },
              loading: () => const AppLoadingOverlay(
                isLoading: true,
                child: SizedBox.expand(),
              ),
              error: (e, _) => Center(
                child: Text(
                  '${l10n?.tr('error') ?? 'Error'}: $e',
                  style: GoogleFonts.assistant(color: AppTheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(
      int currentPage, int totalPages, int totalItems) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: AppTheme.surfaceContainerLowest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'סה״כ $totalItems רשומות',
            style: GoogleFonts.assistant(
              color: AppTheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: currentPage > 1
                    ? () => setState(() => _currentPage = currentPage - 1)
                    : null,
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.primaryGold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$currentPage / $totalPages',
                  style: GoogleFonts.assistant(
                    color: AppTheme.primaryGold,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: currentPage < totalPages
                    ? () => setState(() => _currentPage = currentPage + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreatedByDropdown(
      List<String> creators, AppLocalizations? l10n) {
    final createdByLeading = dropdownLeadingSlot(
      Icon(
        _createdByFilter == 'All'
            ? Icons.people_outline_rounded
            : Icons.person_rounded,
        size: 18,
        color: AppTheme.secondary,
      ),
    );
    return DropdownMenu<String>(
      key: ValueKey('creator_${_createdByFilter}_${creators.length}'),
      initialSelection: _createdByFilter,
      width: 220,
      selectOnly: true,
      enableFilter: false,
      enableSearch: false,
      leadingIcon: createdByLeading,
      decorationBuilder: animatedDropdownDecorationBuilder(
        label: Text(
          l10n?.tr('createdBy') ?? 'Created by',
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        leadingIcon: createdByLeading,
      ),
      menuStyle: appDropdownMenuStyle(),
      inputDecorationTheme:
          appDropdownInputDecorationTheme().copyWith(fillColor: Colors.white),
      textStyle: GoogleFonts.assistant(
        color: AppTheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      onSelected: (v) {
        if (v != null) {
          setState(() {
            _createdByFilter = v;
            _currentPage = 1;
          });
        }
      },
      dropdownMenuEntries: creators.map((f) {
        final label = f == 'All' ? (l10n?.tr('all') ?? 'All') : f;
        return DropdownMenuEntry<String>(
          value: f,
          label: label,
          leadingIcon: dropdownLeadingSlot(
            f == 'All'
                ? Icon(
                    Icons.groups_outlined,
                    size: 16,
                    color: AppTheme.onSurfaceVariant,
                  )
                : Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: AppTheme.secondary,
                  ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatusDropdown(AppLocalizations? l10n) {
    final filters = [
      'All',
      ...OrderStatusExtension.all.map((s) => s.dbValue),
    ];
    final statusLeading = leadingIconForStatusFilterValue(_statusFilter);
    return DropdownMenu<String>(
      key: ValueKey('ord_stat_$_statusFilter'),
      initialSelection: _statusFilter,
      width: 240,
      selectOnly: true,
      enableFilter: false,
      enableSearch: false,
      leadingIcon: statusLeading,
      decorationBuilder: animatedDropdownDecorationBuilder(
        label: Text(
          l10n?.tr('status') ?? 'Status',
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        leadingIcon: statusLeading,
      ),
      menuStyle: appDropdownMenuStyle(),
      inputDecorationTheme:
          appDropdownInputDecorationTheme().copyWith(fillColor: Colors.white),
      textStyle: GoogleFonts.assistant(
        color: AppTheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      onSelected: (v) {
        if (v != null) {
          setState(() {
            _statusFilter = v;
            _currentPage = 1;
          });
        }
      },
      dropdownMenuEntries: filters.map((f) {
        final label = f == 'All'
            ? (l10n?.tr('all') ?? 'All')
            : orderStatusLocalizedLabel(
                OrderStatusExtension.fromString(f),
                l10n,
              );
        return DropdownMenuEntry<String>(
          value: f,
          label: label,
          leadingIcon: leadingIconForStatusFilterValue(f),
        );
      }).toList(),
    );
  }

  /// Line has a supplier on the row — included in send + receive tracking.
  /// (Receive must not skip lines just because [OrderItem.existingInStore] is true;
  /// catalogue/inventory often sets that when stock > 0, but the user still confirms arrival.)
  bool _lineHasSupplierForWorkflow(OrderItem i) =>
      (i.supplierId ?? '').trim().isNotEmpty;

  /// At least one line is tied to a supplier (WhatsApp / send step).
  bool _orderHasLinesRequiringSupplierSend(Order order) {
    for (final i in order.items) {
      if (_lineHasSupplierForWorkflow(i)) return true;
    }
    return false;
  }

  /// After [OrderStatus.sentToSupplier], at least one supplier line still needs receipt.
  bool _orderHasPendingSupplierLines(Order order) {
    for (final i in order.items) {
      if (!_lineHasSupplierForWorkflow(i)) continue;
      if (!i.supplierReceived) return true;
    }
    return false;
  }

  bool _orderHasPendingReadyLines(Order order) {
    for (final i in order.items) {
      if (!i.readyForPickup) return true;
    }
    return false;
  }

  /// Next step button for the order row (null = no action).
  _WorkflowActionDef? _workflowActionForOrder(
    BuildContext context,
    Order order,
  ) {
    switch (order.status) {
      case OrderStatus.canceled:
      case OrderStatus.delivered:
        return null;
      case OrderStatus.active:
        if (!_orderHasLinesRequiringSupplierSend(order)) {
          return _WorkflowActionDef(
            label: (l) => _trLocale(
              context,
              l,
              'orderWorkflowPreparingForCustomer',
              en: 'Preparing for customer',
              he: 'בהכנה ללקוח',
              ar: 'قيد التحضير للعميل',
            ),
            onPressed: () => _workflowAdvanceToPreparing(order),
          );
        }
        return _WorkflowActionDef(
          label: (l) => _trLocale(
            context,
            l,
            'orderWorkflowSendToSupplier',
            en: 'Send to supplier',
            he: 'שליחה לסוכן',
            ar: 'إرسال للمورد',
          ),
          onPressed: () => _workflowSendToSupplier(order),
        );
      case OrderStatus.sentToSupplier:
      case OrderStatus.inAssembly:
        if (_orderHasPendingSupplierLines(order)) {
          return _WorkflowActionDef(
            label: (l) => _trLocale(
              context,
              l,
              'orderWorkflowRecordSupplierDelivery',
              en: 'Record supplier delivery',
              he: 'רישום אספקה מהסוכן',
              ar: 'تسجيل التوريد من المورد',
            ),
            onPressed: () => _workflowReceiveItemsDialog(order),
          );
        }
        return _WorkflowActionDef(
          label: (l) => _trLocale(
            context,
            l,
            'orderWorkflowPreparingForCustomer',
            en: 'Preparing for customer',
            he: 'בהכנה ללקוח',
            ar: 'قيد التحضير للعميل',
          ),
          onPressed: () => _workflowAdvanceToPreparing(order),
        );
      case OrderStatus.preparing:
        return _WorkflowActionDef(
          label: (l) => _trLocale(
            context,
            l,
            'orderWorkflowReadyForPickup',
            en: 'Ready for pickup',
            he: 'מוכן לאיסוף',
            ar: 'جاهز للاستلام',
          ),
          onPressed: () => _workflowReadyForPickup(order),
        );
      case OrderStatus.awaitingShipping:
        return _WorkflowActionDef(
          label: (l) => _trLocale(
            context,
            l,
            'orderWorkflowMarkCompleted',
            en: 'Mark order completed',
            he: 'סימון הזמנה הושלמה',
            ar: 'تعليم الطلب مكتملاً',
          ),
          onPressed: () => _workflowMarkHandled(order),
        );
      case OrderStatus.handled:
        return _WorkflowActionDef(
          label: (l) => _trLocale(
            context,
            l,
            'orderWorkflowPickedUp',
            en: 'Picked up — done',
            he: 'נאסף — סיום',
            ar: 'تم الاستلام — انتهى',
          ),
          onPressed: () => _workflowMarkDelivered(order),
        );
    }
  }

  Widget _buildOrderWorkflowCell(
    BuildContext context,
    AppLocalizations? l10n,
    Order order,
    bool isUpdating,
  ) {
    final action = _workflowActionForOrder(context, order);
    final canCancel = order.status != OrderStatus.canceled &&
        order.status != OrderStatus.delivered;

    if (action == null && !canCancel) {
      return Text(
        '—',
        style: GoogleFonts.assistant(
          color: AppTheme.outlineVariant,
          fontSize: 13,
        ),
      );
    }
    if (isUpdating) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final workflowStyle = OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppTheme.secondary,
      side: BorderSide(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );

    final cancelShort = _trLocale(
      context,
      l10n,
      'orderCancelShort',
      en: 'Cancel',
      he: 'ביטול',
      ar: 'إلغاء',
    );

    final cancelStyle = OutlinedButton.styleFrom(
      foregroundColor: AppTheme.error,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: AppTheme.error.withValues(alpha: 0.42),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (action != null)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => action.onPressed(),
                  style: workflowStyle,
                  child: Text(
                    action.label(l10n),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.assistant(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
              ),
            if (action != null && canCancel) const SizedBox(width: 6),
            if (canCancel)
              Tooltip(
                message: _trLocale(
                  context,
                  l10n,
                  'orderCancelRowLabel',
                  en: 'Cancel order',
                  he: 'ביטול הזמנה',
                  ar: 'إلغاء الطلب',
                ),
                child: OutlinedButton(
                  onPressed: () => _confirmAndCancelOrder(order),
                  style: cancelStyle,
                  child: Text(
                    cancelShort,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.assistant(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _waCustomerReadyPickup(String lang, Order order) {
    final n = order.orderNumber?.toString() ?? '?';
    return switch (lang) {
      'en' =>
        'Good news! Order #$n is ready for pickup. Please visit the store when convenient.',
      'ar' => 'أخبار سارة! الطلب رقم $n جاهز للاستلام. نرحب بزيارتكم للمتجر.',
      _ => 'שמחים לעדכן! הזמנה מספר $n מוכנה לאיסוף. נשמח לראותכם בחנות.',
    };
  }

  String _waCustomerPartialReady(
    String lang,
    Order order, {
    required String itemsBlock,
  }) {
    final n = order.orderNumber?.toString() ?? '?';
    return switch (lang) {
      'en' =>
        'Hello! Part of your order #$n is ready for pickup:\n\n$itemsBlock\n\nWe will update you when the rest is ready.',
      'ar' =>
        'مرحبًا! جزء من طلبك رقم $n جاهز للاستلام:\n\n$itemsBlock\n\nسنُبلغك عند جاهزية الباقي.',
      _ =>
        'שלום! חלק מהזמנה מספר $n מוכן לאיסוף:\n\n$itemsBlock\n\nנעדכן כששאר הפריטים יהיו מוכנים.',
    };
  }

  Future<void> _openWhatsAppToPhone(String rawPhone, String message) async {
    final phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) return;
    await WhatsAppService.sendMessage(phone, message);
  }

  Future<void> _workflowSendToSupplier(Order order) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          orderId: order.id,
          openBottomDrawerInitially: true,
        ),
      ),
    );
    if (!mounted) return;
    ref.invalidate(ordersProvider);
    ref.invalidate(customersProvider);
    final fc = ref.read(ordersCustomerFilterProvider);
    if (fc != null) ref.invalidate(customerOrdersProvider(fc.id));
  }

  Future<void> _workflowReceiveItemsDialog(Order order) async {
    final l10n = AppLocalizations.of(context);
    final pending = order.items
        .where(
          (i) => _lineHasSupplierForWorkflow(i) && !i.supplierReceived,
        )
        .toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trLocale(
              context,
              l10n,
              'orderWorkflowNoPendingItems',
              en: 'No items to mark.',
              he: 'אין פריטים לסימון.',
              ar: 'لا عناصر للتعليم.',
            ),
            style: GoogleFonts.assistant(),
          ),
        ),
      );
      return;
    }

    final supplierLineTotal =
        order.items.where(_lineHasSupplierForWorkflow).length;
    final alreadyReceivedCount = order.items
        .where(
          (i) => _lineHasSupplierForWorkflow(i) && i.supplierReceived,
        )
        .length;

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            void toggleAllPending(bool v) {
              setLocal(() {
                selected.clear();
                if (v) {
                  for (final i in pending) {
                    if (i.id != null) selected.add(i.id!);
                  }
                }
              });
            }

            final mq = MediaQuery.sizeOf(dialogContext);
            final progressLabel = () {
              final code = Localizations.localeOf(context).languageCode;
              final r = alreadyReceivedCount;
              final t = supplierLineTotal;
              return switch (code) {
                'he' => '$r מתוך $t סומנו אצל הסוכן',
                'ar' => '$r من $t تم استلامها من المورد',
                _ => '$r of $t marked from supplier',
              };
            }();

            return Dialog(
              backgroundColor: AppTheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: AppTheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (mq.width - 32).clamp(320.0, 640.0),
                  maxHeight: (mq.height * 0.88).clamp(420.0, 760.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryContainer
                                  .withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.inventory_2_rounded,
                                color: AppTheme.secondary,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _trLocale(
                                    context,
                                    l10n,
                                    'orderWorkflowDeliveryDialogTitle',
                                    en: 'Items received from supplier',
                                    he: 'פריטים שהגיעו מהסוכן',
                                    ar: 'العناصر المستلمة من المورد',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    height: 1.2,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _trLocale(
                                    context,
                                    l10n,
                                    'orderWorkflowDeliveryDialogSubtitle',
                                    en: 'Mark items as they arrive. You can do this in more than one step. The next workflow step unlocks only after every supplier line here is marked received.',
                                    he: 'סמנו פריטים כשהם מגיעים — ניתן לעשות זאת בכמה פעמים. השלב הבא ייפתח רק אחרי שכל שורות הסוכן כאן סומנו כהתקבלו.',
                                    ar: 'علّم العناصر عند وصولها. يمكن القيام بذلك على أكثر من مرة. لا يُفعّل الخطوة التالية في سير العمل إلا بعد تعليم جميع بنود المورد هنا كمستلمة.',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline_rounded,
                                size: 20,
                                color: AppTheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  progressLabel,
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                            side: BorderSide(
                              color: AppTheme.secondary.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => toggleAllPending(
                              selected.length != pending.length),
                          icon: const Icon(Icons.select_all_rounded, size: 18),
                          label: Text(
                            _trLocale(
                              context,
                              l10n,
                              'orderWorkflowSelectAll',
                              en: 'Select all pending',
                              he: 'בחר הכל ממתינים',
                              ar: 'تحديد كل المعلّق',
                            ),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (mq.height * 0.5).clamp(240.0, 520.0),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final it in order.items)
                                if (it.id != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: () {
                                      final id = it.id!;
                                      if (!_lineHasSupplierForWorkflow(it)) {
                                        return DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: AppTheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.45),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: AppTheme.outlineVariant
                                                  .withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.inventory_2_outlined,
                                                  color:
                                                      AppTheme.outlineVariant,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppTheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                      Text(
                                                        _trLocale(
                                                          context,
                                                          l10n,
                                                          'orderWorkflowInStore',
                                                          en: 'In store',
                                                          he: 'במלאי',
                                                          ar: 'في المعرض',
                                                        ),
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontSize: 12,
                                                          color: AppTheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                      if (it.supplierReceived) {
                                        return DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: AppTheme.success
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: AppTheme.success
                                                  .withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle_rounded,
                                                  color: AppTheme.success,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppTheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                      Text(
                                                        it.existingInStore
                                                            ? _trLocale(
                                                                context,
                                                                l10n,
                                                                'orderWorkflowExistsInStock',
                                                                en: 'In stock',
                                                                he: 'קיים במלאי',
                                                                ar: 'متوفر بالمخزون',
                                                              )
                                                            : _trLocale(
                                                                context,
                                                                l10n,
                                                                'orderWorkflowReceivedFromSupplier',
                                                                en: 'Received',
                                                                he: 'התקבל',
                                                                ar: 'مستلم',
                                                              ),
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontSize: 12,
                                                          color:
                                                              AppTheme.success,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                      final checked = selected.contains(id);
                                      return Material(
                                        color: AppTheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () {
                                            setLocal(() {
                                              if (checked) {
                                                selected.remove(id);
                                              } else {
                                                selected.add(id);
                                              }
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child:
                                                      AppAnimatedSquareCheckbox(
                                                    value: checked,
                                                    activeColor:
                                                        AppTheme.secondary,
                                                    onChanged: (v) {
                                                      setLocal(() {
                                                        if (v == true) {
                                                          selected.add(id);
                                                        } else {
                                                          selected.remove(id);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      if (it
                                                          .existingInStore) ...[
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          _trLocale(
                                                            context,
                                                            l10n,
                                                            'orderWorkflowInStore',
                                                            en: 'In store',
                                                            he: 'במלאי',
                                                            ar: 'في المعرض',
                                                          ),
                                                          style: GoogleFonts
                                                              .assistant(
                                                            fontSize: 11,
                                                            color: AppTheme
                                                                .onSurfaceVariant
                                                                .withValues(
                                                              alpha: 0.85,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '×${formatQty(it.quantity)}',
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontSize: 12,
                                                          color: AppTheme
                                                              .onSurfaceVariant,
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
                                    }(),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.onSurfaceVariant,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _t(l10n, 'cancel', 'Cancel'),
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.secondary,
                              foregroundColor: AppTheme.onSecondary,
                              disabledBackgroundColor:
                                  AppTheme.secondary.withValues(alpha: 0.35),
                              disabledForegroundColor:
                                  AppTheme.onSecondary.withValues(alpha: 0.65),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 14,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(ctx, true),
                            child: Text(
                              _trLocale(
                                context,
                                l10n,
                                'orderWorkflowConfirmDelivery',
                                en: 'Confirm received',
                                he: 'אשר קבלה',
                                ar: 'تأكيد الاستلام',
                              ),
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || selected.isEmpty || !mounted) return;

    setState(() => _updatingOrderId = order.id);
    try {
      final username = ref.read(currentUsernameProvider);
      await ref
          .read(orderServiceProvider)
          .markItemsSupplierReceived(selected, username);
      ref.invalidate(ordersProvider);
      final fc = ref.read(ordersCustomerFilterProvider);
      if (fc != null) ref.invalidate(customerOrdersProvider(fc.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.tr('success') ?? 'Success',
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  Future<void> _workflowNotifyReadyItemsDialog(Order order) async {
    final l10n = AppLocalizations.of(context);
    final notReady = order.items.where((i) => !i.readyForPickup).toList();
    if (notReady.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trLocale(
              context,
              l10n,
              'orderWorkflowNoPendingReadyItems',
              en: 'All items are already marked ready.',
              he: 'כל הפריטים כבר מסומנים כמוכנים.',
              ar: 'تم تعليم جميع العناصر كجاهزة.',
            ),
            style: GoogleFonts.assistant(),
          ),
        ),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            void toggleAll(bool v) {
              setLocal(() {
                selected.clear();
                if (v) {
                  for (final i in notReady) {
                    if (i.id != null) selected.add(i.id!);
                  }
                }
              });
            }

            final mq = MediaQuery.sizeOf(dialogContext);
            final readyCount =
                order.items.where((i) => i.readyForPickup).length;
            final totalCount = order.items.length;
            final progressLabel = () {
              final code = Localizations.localeOf(context).languageCode;
              return switch (code) {
                'he' => '$readyCount מתוך $totalCount מוכנים',
                'ar' => '$readyCount من $totalCount جاهزة',
                _ => '$readyCount of $totalCount ready',
              };
            }();

            return Dialog(
              backgroundColor: AppTheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: AppTheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (mq.width - 32).clamp(320.0, 680.0),
                  maxHeight: (mq.height * 0.88).clamp(420.0, 820.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryContainer
                                  .withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.checklist_rounded,
                                color: AppTheme.secondary,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _trLocale(
                                    context,
                                    l10n,
                                    'orderWorkflowReadyItemsDialogTitle',
                                    en: 'Items ready for pickup',
                                    he: 'פריטים שמוכנים לאיסוף',
                                    ar: 'عناصر جاهزة للاستلام',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    height: 1.2,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _trLocale(
                                    context,
                                    l10n,
                                    'orderWorkflowReadyItemsDialogSubtitle',
                                    en: 'Select the items that are ready now. We will mark them ready and send the customer a WhatsApp with the selected items.',
                                    he: 'בחרו את הפריטים שמוכנים עכשיו. נסמן אותם כמוכנים ונשלח ללקוח WhatsApp עם הפריטים שנבחרו.',
                                    ar: 'حدّد العناصر الجاهزة الآن. سنعلّمها كجاهزة ونرسل للعميل واتساب بالعناصر المحددة.',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline_rounded,
                                size: 20,
                                color: AppTheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  progressLabel,
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                            side: BorderSide(
                              color: AppTheme.secondary.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () =>
                              toggleAll(selected.length != notReady.length),
                          icon: const Icon(Icons.select_all_rounded, size: 18),
                          label: Text(
                            _trLocale(
                              context,
                              l10n,
                              'orderWorkflowSelectAll',
                              en: 'Select all pending',
                              he: 'בחר הכל ממתינים',
                              ar: 'تحديد كل المعلّق',
                            ),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (mq.height * 0.5).clamp(240.0, 540.0),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final it in order.items)
                                if (it.id != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: () {
                                      final id = it.id!;
                                      if (it.readyForPickup) {
                                        return Opacity(
                                          opacity: 0.55,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: AppTheme.secondaryContainer
                                                  .withValues(alpha: 0.22),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: AppTheme.secondary
                                                    .withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    color: AppTheme.secondary,
                                                    size: 22,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          it.name,
                                                          style: GoogleFonts
                                                              .assistant(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppTheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          _trLocale(
                                                            context,
                                                            l10n,
                                                            'orderWorkflowReadyItemLabel',
                                                            en: 'Ready',
                                                            he: 'מוכן',
                                                            ar: 'جاهز',
                                                          ),
                                                          style: GoogleFonts
                                                              .assistant(
                                                            fontSize: 12,
                                                            color: AppTheme
                                                                .secondary,
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

                                      final checked = selected.contains(id);
                                      return Material(
                                        color: AppTheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () {
                                            setLocal(() {
                                              if (checked) {
                                                selected.remove(id);
                                              } else {
                                                selected.add(id);
                                              }
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                  ),
                                                  child:
                                                      AppAnimatedSquareCheckbox(
                                                    value: checked,
                                                    activeColor:
                                                        AppTheme.secondary,
                                                    onChanged: (v) {
                                                      setLocal(() {
                                                        if (v == true) {
                                                          selected.add(id);
                                                        } else {
                                                          selected.remove(id);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '×${formatQty(it.quantity)}',
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontSize: 12,
                                                          color: AppTheme
                                                              .onSurfaceVariant,
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
                                    }(),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.onSurfaceVariant,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _t(l10n, 'cancel', 'Cancel'),
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.secondary,
                              foregroundColor: AppTheme.onSecondary,
                              disabledBackgroundColor:
                                  AppTheme.secondary.withValues(alpha: 0.35),
                              disabledForegroundColor:
                                  AppTheme.onSecondary.withValues(alpha: 0.7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 14,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(ctx, true),
                            child: Text(
                              _trLocale(
                                context,
                                l10n,
                                'orderWorkflowNotifyReadyItems',
                                en: 'Notify ready items',
                                he: 'עדכון פריטים מוכנים',
                                ar: 'إبلاغ بالعناصر الجاهزة',
                              ),
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || selected.isEmpty || !mounted) return;

    setState(() => _updatingOrderId = order.id);
    try {
      final username = ref.read(currentUsernameProvider);
      await ref
          .read(orderServiceProvider)
          .markItemsReadyForPickup(selected, username);

      final customer =
          await ref.read(customerServiceProvider).getById(order.customerId);
      if (!mounted) return;
      final phone = customer.phones.isNotEmpty ? customer.phones.first : '';
      if (phone.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _trLocale(
                context,
                l10n,
                'orderWorkflowNoPhoneCustomer',
                en: 'Customer has no phone for WhatsApp.',
                he: 'אין מספר טלפון ללקוח ל-WhatsApp.',
                ar: 'لا يوجد هاتف للعميل لواتساب.',
              ),
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final lang = Localizations.localeOf(context).languageCode;
        final isFinalBatch = selected.length == notReady.length;
        if (isFinalBatch) {
          if (mounted && await confirmSendCustomerWhatsApp(context)) {
            await _openWhatsAppToPhone(
                phone, _waCustomerReadyPickup(lang, order));
          }
          await ref.read(orderServiceProvider).updateStatus(
                order.id,
                OrderStatus.awaitingShipping.dbValue,
                username,
              );
        } else {
          final selectedItems = order.items
              .where((i) => i.id != null && selected.contains(i.id))
              .toList();
          final itemsBlock = selectedItems
              .map((it) => '${it.name}\n×${formatQty(it.quantity)}')
              .join('\n\n');
          if (mounted && await confirmSendCustomerWhatsApp(context)) {
            await _openWhatsAppToPhone(
              phone,
              _waCustomerPartialReady(lang, order, itemsBlock: itemsBlock),
            );
          }
        }
      }

      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      final fc = ref.read(ordersCustomerFilterProvider);
      if (fc != null) ref.invalidate(customerOrdersProvider(fc.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  Future<void> _workflowAdvanceToPreparing(Order order) async {
    final l10n = AppLocalizations.of(context);
    if (!mounted) return;

    final customer =
        await ref.read(customerServiceProvider).getById(order.customerId);
    if (!mounted) return;
    final phone = customer.phones.isNotEmpty ? customer.phones.first : '';
    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trLocale(
              context,
              l10n,
              'orderWorkflowNoPhoneCustomer',
              en: 'Customer has no phone for WhatsApp.',
              he: 'אין מספר טלפון ללקוח ל-WhatsApp.',
              ar: 'لا يوجد هاتف للعميل لواتساب.',
            ),
          ),
        ),
      );
      return;
    }

    await _updateOrderStatus(order.id, OrderStatus.preparing.dbValue);
  }

  Future<void> _workflowReadyForPickup(Order order) async {
    final l10n = AppLocalizations.of(context);
    // If not all lines are ready yet, use the selection popup. Already-ready items
    // are dimmed and cannot be selected again.
    if (_orderHasPendingReadyLines(order)) {
      await _workflowNotifyReadyItemsDialog(order);
      return;
    }
    if (!mounted) return;

    final customer =
        await ref.read(customerServiceProvider).getById(order.customerId);
    if (!mounted) return;
    final phone = customer.phones.isNotEmpty ? customer.phones.first : '';
    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trLocale(
              context,
              l10n,
              'orderWorkflowNoPhoneCustomer',
              en: 'Customer has no phone for WhatsApp.',
              he: 'אין מספר טלפון ללקוח ל-WhatsApp.',
              ar: 'لا يوجد هاتف للعميل لواتساب.',
            ),
          ),
        ),
      );
      return;
    }

    final langPickup = Localizations.localeOf(context).languageCode;
    if (mounted && await confirmSendCustomerWhatsApp(context)) {
      await _openWhatsAppToPhone(
          phone, _waCustomerReadyPickup(langPickup, order));
    }

    if (!mounted) return;
    await _updateOrderStatus(order.id, OrderStatus.awaitingShipping.dbValue);
  }

  Future<void> _workflowMarkHandled(Order order) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _trLocale(
            context,
            l10n,
            'orderWorkflowMarkCompletedConfirmTitle',
            en: 'Mark order completed?',
            he: 'לסמן הזמנה כהושלמה?',
            ar: 'تعليم الطلب كمكتمل؟',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(
          _trLocale(
            context,
            l10n,
            'orderWorkflowMarkCompletedConfirmBody',
            en: 'Mark this order as completed (awaiting customer pickup).',
            he: 'לסמן שההזמנה הושלמה (ממתינה לאיסוף על ידי הלקוח).',
            ar: 'تعليم أن الطلب مكتمل (في انتظار استلام العميل).',
          ),
          style: GoogleFonts.assistant(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t(l10n, 'cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t(l10n, 'confirm', 'Confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _updateOrderStatus(order.id, OrderStatus.handled.dbValue);
  }

  Future<void> _workflowMarkDelivered(Order order) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _trLocale(
            context,
            l10n,
            'orderWorkflowPickedUpConfirmTitle',
            en: 'Order picked up?',
            he: 'ההזמנה נאספה?',
            ar: 'تم استلام الطلب؟',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(
          _trLocale(
            context,
            l10n,
            'orderWorkflowPickedUpConfirmBody',
            en: 'Mark this order as fully completed and delivered.',
            he: 'לסמן שההזמנה הושלמה ונמסרה ללקוח.',
            ar: 'تعليم أن الطلب مكتمل ومُسلَّم للعميل.',
          ),
          style: GoogleFonts.assistant(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t(l10n, 'cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t(l10n, 'confirm', 'Confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _updateOrderStatus(order.id, OrderStatus.delivered.dbValue);
  }

  Future<void> _maybeSendGenericStatusUpdateToCustomer(
      String orderId, String newStatusDb) async {
    // Statuses with their own dedicated workflow message — skip generic.
    // Delivered is fully silent (per shop request: no message at delivery).
    const skip = {
      'Awaiting Shipping',
      'Canceled',
      'Active',
      'Delivered',
    };
    if (skip.contains(newStatusDb)) return;

    final orders = ref.read(ordersProvider).value;
    final order = orders?.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return;

    final customers = ref.read(customersProvider).value;
    final customer =
        customers?.where((c) => c.id == order.customerId).firstOrNull;
    if (customer == null || customer.phones.isEmpty) return;
    final phone = customer.phones.first.trim();
    if (phone.isEmpty) return;

    if (!mounted) return;
    final lang = Localizations.localeOf(context).languageCode;
    final status = OrderStatusExtension.fromString(newStatusDb);
    final message = _buildGenericStatusMessage(
      languageCode: lang,
      customerName: customer.customerName.trim().isNotEmpty
          ? customer.customerName
          : customer.cardName,
      orderNumber: order.orderNumber,
      status: status,
    );

    if (!await confirmSendCustomerWhatsApp(context)) return;
    await WhatsAppService.sendMessage(phone, message);
  }

  String _buildGenericStatusMessage({
    required String languageCode,
    required String customerName,
    required int? orderNumber,
    required OrderStatus status,
  }) {
    final lang =
        (languageCode == 'he' || languageCode == 'ar') ? languageCode : 'en';
    final orderRef = orderNumber != null ? '#$orderNumber' : '';
    final statusLabel = _statusLabelLocalized(status, lang);

    return switch (lang) {
      'he' =>
        'שלום $customerName,\n\nעדכון על הזמנה מספר $orderRef:\nהסטטוס עודכן ל: $statusLabel\n\nתודה שבחרת ב-Royal Lights!',
      'ar' =>
        'مرحبًا $customerName،\n\nتحديث على الطلب رقم $orderRef:\nتم تحديث الحالة إلى: $statusLabel\n\nشكرًا لاختيارك Royal Lights!',
      _ =>
        'Hello $customerName,\n\nUpdate on order $orderRef:\nStatus changed to: $statusLabel\n\nThank you for choosing Royal Lights!',
    };
  }

  String _statusLabelLocalized(OrderStatus s, String lang) {
    switch (lang) {
      case 'he':
        switch (s) {
          case OrderStatus.active:
            return 'פעיל';
          case OrderStatus.preparing:
            return 'בהכנה';
          case OrderStatus.sentToSupplier:
            return 'נשלח לסוכן';
          case OrderStatus.inAssembly:
            return 'בהרכבה';
          case OrderStatus.awaitingShipping:
            return 'ממתין למשלוח';
          case OrderStatus.handled:
            return 'טופל';
          case OrderStatus.delivered:
            return 'נמסר';
          case OrderStatus.canceled:
            return 'בוטל';
        }
      case 'ar':
        switch (s) {
          case OrderStatus.active:
            return 'نشِط';
          case OrderStatus.preparing:
            return 'قيد التحضير';
          case OrderStatus.sentToSupplier:
            return 'أُرسل للمورد';
          case OrderStatus.inAssembly:
            return 'قيد التركيب';
          case OrderStatus.awaitingShipping:
            return 'بانتظار الشحن';
          case OrderStatus.handled:
            return 'تمت المعالجة';
          case OrderStatus.delivered:
            return 'تم التسليم';
          case OrderStatus.canceled:
            return 'ملغي';
        }
      default:
        return s.dbValue;
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    setState(() => _updatingOrderId = orderId);
    try {
      final username = ref.read(currentUsernameProvider);
      await ref
          .read(orderServiceProvider)
          .updateStatus(orderId, newStatus, username);

      // If delivery begins or status becomes Delivered, start warranty counting.
      await ref.read(orderServiceProvider).startWarrantyIfEligible(
            orderId,
            username,
          );

      // Only when the order is fully completed (Delivered), deduct inventory stock once.
      if (newStatus == OrderStatus.delivered.dbValue) {
        await ref
            .read(orderServiceProvider)
            .deductInventoryForOrder(orderId, username);
      }
      // Notify customer for status changes that don't already have a richer
      // workflow-specific message (preparing/awaitingShipping/canceled handled elsewhere).
      await _maybeSendGenericStatusUpdateToCustomer(orderId, newStatus);

      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(totalUnpaidDebtsProvider);
      final fc = ref.read(ordersCustomerFilterProvider);
      if (fc != null) {
        ref.invalidate(customerOrdersProvider(fc.id));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.tr('statusUpdated') ??
                  'סטטוס התעדכן',
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context)?.tr('error') ?? 'שגיאה'}: $e',
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }
}
