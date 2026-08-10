import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:uuid/uuid.dart';
import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../services/whatsapp_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/quote_item.dart';
import '../../models/supplier.dart';
import '../../models/inventory_item.dart';
import '../../providers/providers.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/app_round_checkbox.dart';
import '../../widgets/barcode_scan_dialog.dart';

class OrderFormScreen extends ConsumerStatefulWidget {
  final String? orderId;
  final Customer? initialCustomer;

  /// Pre-fills items from an accepted quote (quote → order conversion).
  final List<QuoteItem>? initialQuoteItems;

  /// When converting a quote, link the saved order back to this quote id.
  final String? sourceQuoteId;

  /// Opens the bottom notes/totals drawer after load (e.g. Orders list "Send to supplier").
  final bool openBottomDrawerInitially;
  const OrderFormScreen({
    super.key,
    this.orderId,
    this.initialCustomer,
    this.initialQuoteItems,
    this.sourceQuoteId,
    this.openBottomDrawerInitially = false,
  });

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen>
    with SingleTickerProviderStateMixin {
  Customer? _selectedCustomer;
  bool _assemblyRequired = false;
  DateTime? _assemblyDate;
  final _assemblyPriceController = TextEditingController();
  final _assemblyPriceFocusNode = FocusNode();
  final _notesController = TextEditingController();
  bool _vatEnabled = true;
  String _discountType = 'percentage'; // 'percentage' or 'fixed_amount'
  final _discountPctController = TextEditingController();
  final _discountPctFocusNode = FocusNode();
  List<_ItemRow> _items = [];
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  bool _isInitialLoad = false;
  bool _loadFailed = false;
  bool _isEdit = false;
  Order? _existingOrder;

  /// Fingerprint of line items last reflected in a customer WhatsApp (or DB on load).
  /// Used to avoid re-sending the same summary when saving with no item changes.
  String? _lastNotifiedCustomerItemsSignature;
  bool get _isReadOnly =>
      _existingOrder != null &&
      (_existingOrder!.status == OrderStatus.sentToSupplier ||
          _existingOrder!.status == OrderStatus.preparing ||
          _existingOrder!.status == OrderStatus.canceled);

  bool get _canSendToSupplier =>
      _existingOrder != null &&
      _existingOrder!.status == OrderStatus.active &&
      !_hasUnsavedChanges;

  bool get _waitingSupplierConfirmation =>
      _existingOrder != null &&
      _existingOrder!.status == OrderStatus.sentToSupplier;

  ({String label, Color color, IconData icon}) _orderSaveStatusPill(
    BuildContext context,
    AppLocalizations? l10n,
  ) {
    if (_hasUnsavedChanges) {
      return (
        label: _orderTableColumnLabel(
          context,
          l10n,
          'notSaved',
          en: 'Not saved',
          he: 'לא נשמרה',
          ar: 'غير محفوظ',
        ),
        color: AppTheme.warning,
        icon: Icons.edit_outlined,
      );
    }
    final o = _existingOrder;
    if (o == null) {
      return (
        label: _orderTableColumnLabel(
          context,
          l10n,
          'notSaved',
          en: 'Not saved',
          he: 'לא נשמרה',
          ar: 'غير محفوظ',
        ),
        color: AppTheme.outline,
        icon: Icons.edit_outlined,
      );
    }

    switch (o.status) {
      case OrderStatus.canceled:
        return (
          label: _orderTableColumnLabel(
            context,
            l10n,
            'canceled',
            en: 'Canceled',
            he: 'מבוטלת',
            ar: 'ملغي',
          ),
          color: AppTheme.error,
          icon: Icons.cancel_rounded,
        );
      case OrderStatus.sentToSupplier:
        return (
          label: _orderTableColumnLabel(
            context,
            l10n,
            'sentToSupplier',
            en: 'Sent to supplier',
            he: 'נשלח לסוכן',
            ar: 'تم الإرسال للمورد',
          ),
          color: AppTheme.secondary,
          icon: Icons.send_rounded,
        );
      default:
        return (
          label: _orderTableColumnLabel(
            context,
            l10n,
            'saved',
            en: 'Saved',
            he: 'נשמרה',
            ar: 'تم الحفظ',
          ),
          color: AppTheme.success,
          icon: Icons.check_circle_rounded,
        );
    }
  }

  Widget _orderSaveStatusBadge(BuildContext context, AppLocalizations? l10n) {
    final pill = _orderSaveStatusPill(context, l10n);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: pill.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pill.color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pill.icon, size: 17, color: pill.color),
          const SizedBox(width: 6),
          Text(
            pill.label,
            style: GoogleFonts.assistant(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: pill.color,
            ),
          ),
        ],
      ),
    );
  }

  void _markDirty() {
    if (_isReadOnly) return;
    if (_isInitialLoad) return;
    if (_hasUnsavedChanges) return;
    setState(() => _hasUnsavedChanges = true);
  }

  void _onDiscountChanged() {
    if (!mounted) return;
    setState(() {});
  }

  final _customerSelectorKey = GlobalKey();
  OverlayEntry? _customerOverlayEntry;
  OverlayEntry? _inventoryOverlayEntry;
  final _customerTextController = TextEditingController();
  final _customerFocusNode = FocusNode();
  late final AnimationController _bottomDrawerController;
  final ScrollController _itemsTableHorizontalScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _bottomDrawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 0,
    );
    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
      final c = widget.initialCustomer!;
      _customerTextController.text = '${c.cardName} - ${c.customerName}';
    }
    _notesController.addListener(_markDirty);
    _assemblyPriceController.addListener(_markDirty);
    _discountPctController.addListener(_markDirty);
    _discountPctController.addListener(_onDiscountChanged);
    _bindSelectAllOnNumericFieldFocus(
      _assemblyPriceFocusNode,
      _assemblyPriceController,
    );
    _bindSelectAllOnNumericFieldFocus(
      _discountPctFocusNode,
      _discountPctController,
    );
    _customerFocusNode.addListener(_onCustomerFocusChange);
    if (widget.orderId != null) {
      _isEdit = true;
      _loadOrder();
    } else if (widget.initialQuoteItems != null &&
        widget.initialQuoteItems!.isNotEmpty) {
      _items = widget.initialQuoteItems!.map((qi) {
        final row = _ItemRow();
        row.itemNumberCtrl.text = qi.itemNumber ?? '';
        row.nameCtrl.text = qi.name;
        row.quantityCtrl.text = formatQty(qi.quantity);
        row.extrasCtrl.text = qi.extras ?? '';
        row.priceCtrl.text = qi.price.toString();
        row.extrasPriceCtrl.text =
            qi.extrasPrice == 0 ? '' : qi.extrasPrice.toString();
        return row;
      }).toList();
    } else {
      _items.add(_ItemRow());
    }
  }

  @override
  void didUpdateWidget(covariant OrderFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _bottomDrawerController.reset();
    }
  }

  Future<void> _loadOrder() async {
    setState(() => _isLoading = true);
    try {
      _loadFailed = false;
      final order =
          await ref.read(orderServiceProvider).getById(widget.orderId!);
      _isInitialLoad = true;
      setState(() {
        _existingOrder = order;
        _hasUnsavedChanges = false;
        _assemblyRequired = order.assemblyRequired;
        _assemblyDate = order.assemblyDate;
        _assemblyPriceController.text =
            order.assemblyPrice > 0 ? order.assemblyPrice.toString() : '';
        _vatEnabled = order.vatEnabled;
        _discountType = order.discountType;
        _discountPctController.text = order.discountPercentage > 0
            ? formatQty(order.discountPercentage)
            : '';
        _notesController.text = order.notes ?? '';
        _items = order.items.map((item) {
          final row = _ItemRow();
          row.orderItemId = item.id;
          row.itemNumberCtrl.text = item.itemNumber ?? '';
          row.nameCtrl.text = item.name;
          row.quantityCtrl.text = formatQty(item.quantity);
          row.extrasCtrl.text = item.extras ?? '';
          row.priceCtrl.text = item.price.toString();
          row.extrasPriceCtrl.text =
              item.extrasPrice == 0 ? '' : item.extrasPrice.toString();
          row.assemblyRequired = item.assemblyRequired;
          row.roomCtrl.text =
              (item.roomLabel != null && item.roomLabel!.trim().isNotEmpty)
                  ? item.roomLabel!.trim()
                  : (item.roomName ?? '');
          row.supplierId = item.supplierId;
          row.existingInStore = item.existingInStore;
          row.inventoryItemId = item.inventoryItemId;
          row.warrantyYears = item.warrantyYears;
          row.imageUrl = item.imageUrl;
          row.deliveryDate = item.deliveryDate ?? order.deliveryDate;
          row.supplierReceived = item.supplierReceived;
          row.readyForPickup = item.readyForPickup;
          row.inventoryDeducted = item.inventoryDeducted;
          row.supplierNote = item.notes ?? '';
          return row;
        }).toList();
        // If any line item requires assembly, force the order-level switch on.
        if (!_assemblyRequired && _items.any((r) => r.assemblyRequired)) {
          _assemblyRequired = true;
        }
        if (_items.isEmpty) _items.add(_ItemRow());
        _isLoading = false;
        _lastNotifiedCustomerItemsSignature =
            _signatureForOrderItems(order.items);
        _isInitialLoad = false;
      });
      _bottomDrawerController.reset();
      if (widget.openBottomDrawerInitially && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _bottomDrawerController.forward();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        final lang = Localizations.localeOf(context).languageCode;
        final message = switch (lang) {
          'he' => 'שגיאה בטעינת ההזמנה. חזור ונסה שוב.',
          'ar' => 'فشل تحميل الطلب. ارجع وحاول مرة أخرى.',
          _ => 'Failed to load order. Please go back and try again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  double _parseQty(String raw) {
    final v = parseDecimalInput(raw, fallback: 1);
    if (v <= 0) return 1;
    return v;
  }

  double _lineTotal(_ItemRow item) {
    final qty = _parseQty(item.quantityCtrl.text);
    final unit = parseDecimalInput(item.priceCtrl.text);
    final extrasAmt = parseDecimalInput(item.extrasPriceCtrl.text);

    // Both unit price and add-ons price should scale with quantity.
    return qty * (unit + extrasAmt);
  }

  double get _linesSubtotal {
    double total = 0;
    for (final item in _items) {
      total += _lineTotal(item);
    }
    return total;
  }

  /// Installation fee when assembly is required (admin input).
  double get _assemblyInstallPrice {
    if (!_assemblyRequired) return 0;
    return parseDecimalInput(_assemblyPriceController.text);
  }

  /// Line items + installation (when required).
  double get _totalPrice => _linesSubtotal + _assemblyInstallPrice;

  /// Pre-VAT, pre-discount amount for display.
  double get _subtotalExVat => _totalPrice;
  static const double _vatRate = 0.18;
  double get _vatAmount => _vatEnabled ? _subtotalExVat * _vatRate : 0;
  double get _totalWithVat => _subtotalExVat + _vatAmount;

  /// Discount percentage (0–100), parsed from controller and clamped.
  double get _discountPercentage {
    if (_discountType == 'fixed_amount') return 0;
    final v = parseDecimalInput(_discountPctController.text);
    if (v <= 0) return 0;
    return v > 100 ? 100 : v;
  }

  /// Fixed discount in shekels (stored in [Order.discountPercentage] when type is fixed_amount).
  double get _discountFixedAmount {
    if (_discountType != 'fixed_amount') return 0;
    final amt = parseDecimalInput(_discountPctController.text);
    return amt > 0 ? amt : 0;
  }

  /// Discount amount in shekels (applied to the VAT-inclusive total).
  double get _discountAmount {
    if (_discountType == 'percentage') {
      return _totalWithVat * (_discountPercentage / 100);
    }
    return _discountFixedAmount;
  }

  /// Value persisted in `discount_percentage` (percent or fixed ₪ depending on type).
  double get _discountStoredValue =>
      _discountType == 'percentage' ? _discountPercentage : _discountFixedAmount;

  /// Final amount stored in DB as `total_price`.
  double get _grandTotalWithVat => _totalWithVat - _discountAmount;

  /// Synced to [Order.delivery_date] for DB triggers / warranty helpers (latest line date).
  DateTime? _orderDeliveryDateAggregate() {
    final dates = _items
        .map((r) => r.deliveryDate)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> _pickFromInventory(_ItemRow row) async {
    if (_isReadOnly) return;

    final l10n = AppLocalizations.of(context);
    try {
      final items = await ref.read(inventoryItemsProvider.future);
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.tr('noData') ?? 'No Data',
            ),
          ),
        );
        return;
      }

      final suppliers = await ref.read(suppliersProvider.future);
      final supplierById = <String, Supplier>{
        for (final s in suppliers) s.id: s,
      };

      if (!mounted) return;
      final picked = await showDialog<InventoryItem>(
        context: context,
        builder: (ctx) {
          final searchCtrl = TextEditingController();
          var q = '';
          return StatefulBuilder(
            builder: (context, setLocal) {
              final filtered = items.where((it) {
                if (q.isEmpty) return true;
                final qq = q.toLowerCase();
                return it.description.toLowerCase().contains(qq) ||
                    (it.brand ?? '').toLowerCase().contains(qq) ||
                    (it.barcode ?? '').toLowerCase().contains(qq);
              }).toList();

              return AlertDialog(
                backgroundColor: AppTheme.surfaceContainerLowest,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                title: Text(
                  _orderTableColumnLabel(
                    context,
                    l10n,
                    'inventory',
                    en: 'Inventory',
                    he: 'מלאי',
                    ar: 'المخزون',
                  ),
                  style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: 720,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        onChanged: (v) => setLocal(() => q = v.trim()),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: _orderTableColumnLabel(
                            context,
                            l10n,
                            'searchItemsHint',
                            en: 'Search by description, brand, barcode…',
                            he: 'חיפוש לפי תיאור, מותג, ברקוד…',
                            ar: 'ابحث بالوصف، الماركة، الباركود…',
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Material(
                            color: Colors.white,
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                thickness: 1,
                                color: AppTheme.outlineVariant
                                    .withValues(alpha: 0.14),
                              ),
                              itemBuilder: (context, index) {
                                final it = filtered[index];
                                final supplier = it.supplierId != null
                                    ? supplierById[it.supplierId!]
                                    : null;
                                final subtitleParts = <String>[
                                  if (supplier != null &&
                                      supplier.companyName.trim().isNotEmpty)
                                    supplier.companyName.trim(),
                                  if ((it.brand ?? '').trim().isNotEmpty)
                                    it.brand!.trim(),
                                  if ((it.barcode ?? '').trim().isNotEmpty)
                                    it.barcode!.trim(),
                                ];
                                return ListTile(
                                  dense: false,
                                  leading: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.outlineVariant
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: (it.imageUrl != null &&
                                            it.imageUrl!.trim().isNotEmpty)
                                        ? CachedNetworkImage(
                                            imageUrl: it.imageUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : Icon(
                                            Icons.image_outlined,
                                            size: 22,
                                            color: AppTheme.outline
                                                .withValues(alpha: 0.55),
                                          ),
                                  ),
                                  title: Text(
                                    it.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.assistant(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: subtitleParts.isEmpty
                                      ? null
                                      : Text(
                                          subtitleParts.join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.assistant(
                                            color: AppTheme.onSurfaceVariant,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                  trailing: Text(
                                    it.consumerPrice == null
                                        ? '—'
                                        : '₪${it.consumerPrice!.toStringAsFixed(0)}',
                                    style: GoogleFonts.assistant(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, it),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n?.tr('cancel') ?? 'Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (picked == null || !mounted) return;

      setState(() {
        _markDirty();
        row.inventoryItemId = picked.id;
        // Auto-assign fields from inventory.
        row.nameCtrl.text = picked.description;
        row.itemNumberCtrl.text = picked.barcode ?? '';
        if (picked.consumerPrice != null) {
          row.priceCtrl.text = picked.consumerPrice!.toStringAsFixed(0);
        }
        row.supplierId = picked.supplierId;
        row.imageUrl = picked.imageUrl;

        // If stock exists, default the "existing in store" flag on (user can override).
        if (picked.availableStock > 0) {
          row.existingInStore = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _hideCustomerDropdown() {
    _customerOverlayEntry?.remove();
    _customerOverlayEntry = null;
    setState(() {});
  }

  void _hideInventoryDropdown() {
    _inventoryOverlayEntry?.remove();
    _inventoryOverlayEntry = null;
  }

  void _applyInventoryToRow(_ItemRow row, InventoryItem picked) {
    // Auto-assign fields from inventory.
    row.inventoryItemId = picked.id;
    row.nameCtrl.text = picked.description;
    row.itemNumberCtrl.text = picked.barcode ?? '';
    if (picked.consumerPrice != null) {
      row.priceCtrl.text = picked.consumerPrice!.toStringAsFixed(0);
    }
    row.supplierId = picked.supplierId;
    row.imageUrl = picked.imageUrl;
    row.warrantyYears = picked.warrantyYears;

    // If stock exists, default the "existing in store" flag on (user can override).
    if (picked.availableStock > 0) {
      row.existingInStore = true;
    }
  }

  void _resetRowInventoryLink(_ItemRow row) {
    row.inventoryItemId = null;
    row.supplierId = null;
    row.existingInStore = false;
    row.warrantyYears = 0;
    row.imageUrl = null;
  }

  /// True when this row was entered manually and is NOT linked to an
  /// inventory item — only such rows can have an image uploaded.
  bool _rowIsManualEntry(_ItemRow row) =>
      row.inventoryItemId == null || row.inventoryItemId!.isEmpty;

  Future<void> _onItemImageTapped(_ItemRow row, AppLocalizations? l10n) async {
    final hasImage =
        row.imageUrl != null && row.imageUrl!.trim().isNotEmpty;

    // For inventory-linked items or read-only orders: only preview.
    if (_isReadOnly || !_rowIsManualEntry(row)) {
      if (hasImage) _showImagePreview(row.imageUrl!, l10n);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(_orderTableColumnLabel(
                  context,
                  l10n,
                  'view',
                  en: 'View',
                  he: 'הצג',
                  ar: 'عرض',
                )),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(_orderTableColumnLabel(
                context,
                l10n,
                'takePhoto',
                en: 'Take photo',
                he: 'צילום תמונה',
                ar: 'التقاط صورة',
              )),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_orderTableColumnLabel(
                context,
                l10n,
                'chooseFromGallery',
                en: 'Choose from gallery',
                he: 'בחירה מהגלריה',
                ar: 'اختيار من المعرض',
              )),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasImage)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.error),
                title: Text(
                  _orderTableColumnLabel(
                    context,
                    l10n,
                    'removeImage',
                    en: 'Remove image',
                    he: 'הסרת תמונה',
                    ar: 'إزالة الصورة',
                  ),
                  style: TextStyle(color: AppTheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'view' && hasImage) {
      _showImagePreview(row.imageUrl!, l10n);
      return;
    }
    if (action == 'remove') {
      setState(() {
        row.imageUrl = null;
        _markDirty();
      });
      return;
    }
    if (action == 'camera' || action == 'gallery') {
      await _pickImageForRow(
        row,
        action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
    }
  }

  Future<void> _pickImageForRow(_ItemRow row, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (xFile == null || !mounted) return;
      final bytes = await xFile.readAsBytes();
      final fileKey = (row.orderItemId != null && row.orderItemId!.isNotEmpty)
          ? row.orderItemId!
          : 'tmp/${DateTime.now().microsecondsSinceEpoch}-${row.hashCode}';
      final url = await ref
          .read(orderServiceProvider)
          .uploadOrderItemPhoto(fileKey, bytes);
      if (!mounted) return;
      setState(() {
        row.imageUrl = url;
        _markDirty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text(
            '${AppLocalizations.of(context)?.tr('error') ?? 'Error'}: $e',
          ),
        ),
      );
    }
  }

  void _showImagePreview(String imageUrl, AppLocalizations? l10n) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppTheme.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IconButton(
                      tooltip: l10n?.tr('close') ?? 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInventorySuggestions({
    required BuildContext context,
    required GlobalKey anchorKey,
    required _ItemRow row,
    required List<InventoryItem> items,
    required AppLocalizations? l10n,
    required bool fromNameField,
  }) {
    if (_isReadOnly) return;
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final overlay = Overlay.of(context);
    final screenW = MediaQuery.sizeOf(context).width;
    const screenMargin = 8.0;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final query = (fromNameField
            ? row.nameCtrl.text.trim()
            : row.itemNumberCtrl.text.trim())
        .toLowerCase();
    if (query.isEmpty) {
      _hideInventoryDropdown();
      return;
    }

    final filtered = items
        .where((it) {
          final desc = it.description.toLowerCase();
          final brand = (it.brand ?? '').toLowerCase();
          final barcode = (it.barcode ?? '').toLowerCase();
          final matches = desc.contains(query) ||
              brand.contains(query) ||
              barcode.contains(query);
          if (!matches) return false;
          // When searching by name, show "items that there is" (in stock) first/only.
          if (fromNameField) return it.availableStock > 0;
          return true;
        })
        .take(12)
        .toList();

    _hideInventoryDropdown();
    _inventoryOverlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideInventoryDropdown,
            ),
          ),
          Positioned(
            left: () {
              final desiredW = (size.width + 220).clamp(360.0, 560.0);
              final minLeft = screenMargin;
              final maxLeft = (screenW - screenMargin - desiredW).clamp(
                screenMargin,
                double.infinity,
              );

              // In RTL, align the menu's right edge to the field's right edge.
              final rawLeft = isRtl ? (pos.dx + size.width - desiredW) : pos.dx;
              return rawLeft.clamp(minLeft, maxLeft);
            }(),
            top: pos.dy + size.height + 4,
            width: (size.width + 220).clamp(360.0, 560.0),
            child: Material(
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.surfaceContainerLowest,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          l10n?.tr('noMatchingResults') ?? 'No matches',
                          style: GoogleFonts.assistant(
                            color: AppTheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 1,
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, i) {
                          final it = filtered[i];
                          final subtitleParts = <String>[
                            if ((it.brand ?? '').trim().isNotEmpty)
                              it.brand!.trim(),
                            if ((it.barcode ?? '').trim().isNotEmpty)
                              it.barcode!.trim(),
                          ];
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _markDirty();
                                _applyInventoryToRow(row, it);
                              });
                              _hideInventoryDropdown();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppTheme.outlineVariant
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: (it.imageUrl != null &&
                                            it.imageUrl!.trim().isNotEmpty)
                                        ? CachedNetworkImage(
                                            imageUrl: it.imageUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : Icon(
                                            Icons.image_outlined,
                                            size: 22,
                                            color: AppTheme.outline
                                                .withValues(alpha: 0.55),
                                          ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          it.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.assistant(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.onSurface,
                                          ),
                                        ),
                                        if (subtitleParts.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitleParts.join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.assistant(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    it.consumerPrice == null
                                        ? '—'
                                        : '₪${it.consumerPrice!.toStringAsFixed(0)}',
                                    style: GoogleFonts.assistant(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_inventoryOverlayEntry!);
  }

  void _onCustomerFocusChange() {
    if (!_customerFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || _customerFocusNode.hasFocus) return;
        _hideCustomerDropdown();
      });
    }
  }

  Future<void> _pickAssemblyDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 365));
    final last = today.add(const Duration(days: 365 * 3));
    var initial = _assemblyDate ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null && mounted) {
      _markDirty();
      setState(() => _assemblyDate = date);
    }
  }

  Future<void> _pickItemDeliveryDate(_ItemRow row) async {
    if (_isReadOnly) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 365 * 2));
    final last = today.add(const Duration(days: 365 * 5));
    var initial = row.deliveryDate ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null && mounted) {
      _markDirty();
      setState(() => row.deliveryDate = date);
    }
  }

  void _showCustomerPicker(
    BuildContext context,
    List<Customer> customers,
    AppLocalizations? l10n,
  ) {
    if (_customerOverlayEntry != null) return;
    final box =
        _customerSelectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final overlay = Overlay.of(context);

    _customerOverlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideCustomerDropdown,
            ),
          ),
          Positioned(
            left: pos.dx,
            top: pos.dy + size.height + 4,
            width: size.width,
            height: 320,
            child: Material(
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.surfaceContainerLowest,
              child: Builder(
                builder: (ctx) {
                  final query =
                      _customerTextController.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? customers
                      : customers.where((c) {
                          return c.cardName.toLowerCase().contains(query) ||
                              c.customerName.toLowerCase().contains(query) ||
                              c.phones.any(
                                (p) => p.toLowerCase().contains(query),
                              );
                        }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    l10n?.tr('noMatchingResults') ??
                                        'No matches',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final c = filtered[i];
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedCustomer = c;
                                        _customerTextController.text =
                                            '${c.cardName} - ${c.customerName}';
                                      });
                                      _hideCustomerDropdown();
                                      _customerFocusNode.unfocus();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        '${c.cardName} - ${c.customerName}',
                                        style: const TextStyle(
                                          color: AppTheme.onSurface,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_customerOverlayEntry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customersAsync = ref.watch(customersProvider);
    final suppliersAsync = ref.watch(suppliersProvider);
    final inventoryAsync = ref.watch(inventoryItemsProvider);

    // On tablet (e.g. iPad), avoid shrinking the body for the keyboard so the
    // bottom notes/totals drawer stays at the screen bottom instead of jumping
    // above the keyboard. Phones keep the default so fields can scroll clear.
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTabletLayout = shortestSide >= 600;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final action = await _confirmLeaveUnsaved(l10n);
        if (action == _LeaveAction.cancel || !mounted) return;
        if (action == _LeaveAction.save) {
          final saved = await _saveOrder();
          if (!mounted) return;
          if (!saved) return;
        }
        navigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: !isTabletLayout,
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _orderFormAppBarTitle(context, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _orderSaveStatusBadge(context, l10n),
            ],
          ),
          actions: const [],
        ),
        body: AppLoadingOverlay(
          isLoading: _isLoading,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order header — one row, full width of scroll content
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: customersAsync.when(
                                    data: (customers) {
                                      if (_isEdit &&
                                          _existingOrder != null &&
                                          _selectedCustomer == null) {
                                        final c = customers
                                            .where(
                                              (x) =>
                                                  x.id ==
                                                  _existingOrder!.customerId,
                                            )
                                            .firstOrNull;
                                        _selectedCustomer = c;
                                        if (c != null) {
                                          _customerTextController.text =
                                              '${c.cardName} - ${c.customerName}';
                                        }
                                      }
                                      return KeyedSubtree(
                                        key: _customerSelectorKey,
                                        child: TextField(
                                          controller: _customerTextController,
                                          focusNode: _customerFocusNode,
                                          enabled: !_isReadOnly,
                                          readOnly: _isReadOnly,
                                          onChanged: (value) {
                                            final sel = _selectedCustomer;
                                            if (sel != null) {
                                              final expected =
                                                  '${sel.cardName} - ${sel.customerName}';
                                              if (value != expected) {
                                                _selectedCustomer = null;
                                              }
                                            }
                                            setState(() {});
                                            _customerOverlayEntry
                                                ?.markNeedsBuild();
                                            if (_customerOverlayEntry == null) {
                                              _showCustomerPicker(
                                                context,
                                                customers,
                                                l10n,
                                              );
                                            }
                                          },
                                          onTap: () {
                                            if (_customerOverlayEntry == null) {
                                              _showCustomerPicker(
                                                context,
                                                customers,
                                                l10n,
                                              );
                                            }
                                          },
                                          style: GoogleFonts.assistant(
                                            fontSize: 15,
                                            color: AppTheme.onSurface,
                                          ),
                                          decoration: InputDecoration(
                                            labelText: _orderTableColumnLabel(
                                              context,
                                              l10n,
                                              'customerName',
                                              en: 'Customer Name',
                                              he: 'שם לקוח',
                                              ar: 'اسم العميل',
                                            ),
                                            labelStyle: GoogleFonts.assistant(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.onSurfaceVariant,
                                            ),
                                            floatingLabelStyle:
                                                GoogleFonts.assistant(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.secondary,
                                            ),
                                            prefixIcon: dropdownLeadingSlot(
                                              const Icon(
                                                Icons.person_outline,
                                                size: 18,
                                                color: AppTheme.secondary,
                                              ),
                                            ),
                                            suffixIcon: Icon(
                                              Icons.arrow_drop_down_rounded,
                                              color: AppTheme.secondary
                                                  .withValues(alpha: 0.85),
                                            ),
                                            filled: true,
                                            fillColor: AppTheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.55),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide(
                                                color: AppTheme.outlineVariant
                                                    .withValues(alpha: 0.22),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: BorderSide(
                                                color: AppTheme.outlineVariant
                                                    .withValues(alpha: 0.22),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              borderSide: const BorderSide(
                                                color: AppTheme.secondary,
                                                width: 1.8,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    loading: () =>
                                        const CircularProgressIndicator(),
                                    error: (_, __) =>
                                        const Text('Error loading customers'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 210,
                                  child: SwitchListTile.adaptive(
                                    value: _assemblyRequired,
                                    onChanged: _isReadOnly
                                        ? null
                                        : (v) {
                                            setState(() {
                                              _assemblyRequired = v;
                                              for (final item in _items) {
                                                item.assemblyRequired = v;
                                              }
                                            });
                                          },
                                    title: Text(
                                      _orderTableColumnLabel(
                                        context,
                                        l10n,
                                        'assemblyRequired',
                                        en: 'Assembly Required',
                                        he: 'דרוש הרכבה',
                                        ar: 'يتطلب تركيب',
                                      ),
                                      style: GoogleFonts.assistant(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.onSurface,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 4,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _assemblyRequired ? 1 : 0,
                                    child: IgnorePointer(
                                      ignoring:
                                          !_assemblyRequired || _isReadOnly,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: InkWell(
                                              onTap: _pickAssemblyDate,
                                              child: InputDecorator(
                                                isEmpty: _assemblyDate == null,
                                                decoration: InputDecoration(
                                                  labelText:
                                                      _orderTableColumnLabel(
                                                    context,
                                                    l10n,
                                                    'assemblyDate',
                                                    en: 'Assembly Date',
                                                    he: 'תאריך הרכבה',
                                                    ar: 'تاريخ التركيب',
                                                  ),
                                                  labelStyle:
                                                      GoogleFonts.assistant(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  floatingLabelStyle:
                                                      GoogleFonts.assistant(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.secondary,
                                                  ),
                                                  prefixIcon: const Icon(
                                                    Icons
                                                        .calendar_today_outlined,
                                                    color: AppTheme.secondary,
                                                  ),
                                                  filled: true,
                                                  fillColor: AppTheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.55),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18),
                                                    borderSide: BorderSide(
                                                      color: AppTheme
                                                          .outlineVariant
                                                          .withValues(
                                                              alpha: 0.22),
                                                    ),
                                                  ),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18),
                                                    borderSide: BorderSide(
                                                      color: AppTheme
                                                          .outlineVariant
                                                          .withValues(
                                                              alpha: 0.22),
                                                    ),
                                                  ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18),
                                                    borderSide:
                                                        const BorderSide(
                                                      color: AppTheme.secondary,
                                                      width: 1.8,
                                                    ),
                                                  ),
                                                  hintText: _assemblyDate ==
                                                          null
                                                      ? _orderTableColumnLabel(
                                                          context,
                                                          l10n,
                                                          'selectDate',
                                                          en: 'Select date',
                                                          he: 'בחר תאריך',
                                                          ar: 'اختر التاريخ',
                                                        )
                                                      : null,
                                                  hintStyle:
                                                      GoogleFonts.assistant(
                                                    fontSize: 16,
                                                    color: AppTheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 12,
                                                    vertical: 14,
                                                  ),
                                                ),
                                                child: Text(
                                                  AppDateFormat.tableOrEmpty(
                                                      _assemblyDate),
                                                  style: GoogleFonts.assistant(
                                                    fontSize: 16,
                                                    color: AppTheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: TextField(
                                              controller:
                                                  _assemblyPriceController,
                                              focusNode:
                                                  _assemblyPriceFocusNode,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                                signed: false,
                                              ),
                                              enableSuggestions: false,
                                              autocorrect: false,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .allow(
                                                  RegExp(r'[0-9.,]'),
                                                ),
                                              ],
                                              onChanged: (_) {
                                                _markDirty();
                                                setState(() {});
                                              },
                                              style: GoogleFonts.assistant(
                                                fontSize: 16,
                                                color: AppTheme.onSurface,
                                              ),
                                              decoration: InputDecoration(
                                                labelText:
                                                    _orderTableColumnLabel(
                                                  context,
                                                  l10n,
                                                  'assemblyInstallationPrice',
                                                  en: 'Installation price',
                                                  he: 'מחיר התקנה',
                                                  ar: 'سعر التركيب',
                                                ),
                                                hintText:
                                                    _orderTableColumnLabel(
                                                  context,
                                                  l10n,
                                                  'assemblyInstallationPriceHint',
                                                  en: '0',
                                                  he: '0',
                                                  ar: '0',
                                                ),
                                                labelStyle:
                                                    GoogleFonts.assistant(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      AppTheme.onSurfaceVariant,
                                                ),
                                                floatingLabelStyle:
                                                    GoogleFonts.assistant(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.secondary,
                                                ),
                                                prefixText: '₪ ',
                                                prefixStyle:
                                                    GoogleFonts.assistant(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.secondary,
                                                ),
                                                filled: true,
                                                fillColor: AppTheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.55),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide(
                                                    color: AppTheme
                                                        .outlineVariant
                                                        .withValues(
                                                            alpha: 0.22),
                                                  ),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: BorderSide(
                                                    color: AppTheme
                                                        .outlineVariant
                                                        .withValues(
                                                            alpha: 0.22),
                                                  ),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  borderSide: const BorderSide(
                                                    color: AppTheme.secondary,
                                                    width: 1.8,
                                                  ),
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          l10n?.tr('orderItems') ?? 'Order Items',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Scrollbar(
                                controller: _itemsTableHorizontalScrollCtrl,
                                thumbVisibility: true,
                                interactive: true,
                                child: SingleChildScrollView(
                                  controller: _itemsTableHorizontalScrollCtrl,
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 16,
                                    end: 16,
                                    top: 6,
                                    bottom: 12,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: (constraints.maxWidth - 32)
                                          .clamp(0.0, double.infinity),
                                    ),
                                    child: suppliersAsync.when(
                                      data: (suppliers) => _buildItemsTable(
                                        context,
                                        l10n,
                                        suppliers,
                                        inventoryAsync.value ??
                                            const <InventoryItem>[],
                                        readOnly: _isReadOnly,
                                      ),
                                      loading: () => const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(24),
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      error: (_, __) => const Text('Error'),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (!_isReadOnly && !_isLoading) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.icon(
                            onPressed: () {
                              _markDirty();
                              setState(() => _items.add(_ItemRow()));
                            },
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: Text(
                              l10n?.tr('addItem') ?? 'Add item',
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.secondary,
                              foregroundColor: AppTheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: const StadiumBorder(),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _buildOrderBottomDrawer(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapsible bottom panel: peek shows tops of notes + totals; expanded fills height.
  Widget _buildOrderBottomDrawer(
    BuildContext context,
    AppLocalizations? l10n,
  ) {
    final media = MediaQuery.sizeOf(context);
    // Room for VAT/discount rows + totals + Save/Send (was capped at 292px → overflow).
    final expandedContentH = (media.height * 0.34).clamp(260.0, 420.0);
    const peekContentH = 52.0;
    final range = expandedContentH - peekContentH;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 6),
          child: AnimatedBuilder(
            animation: _bottomDrawerController,
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(
                _bottomDrawerController.value,
              );
              final contentH = lerpDouble(peekContentH, expandedContentH, t)!;
              final drawerOpen = _bottomDrawerController.value > 0.5;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if (range <= 0) return;
                        _bottomDrawerController.value =
                            (_bottomDrawerController.value -
                                    details.delta.dy / range)
                                .clamp(0.0, 1.0);
                      },
                      onVerticalDragEnd: (details) {
                        final v = details.velocity.pixelsPerSecond.dy;
                        if (v < -240) {
                          _bottomDrawerController.forward();
                        } else if (v > 240) {
                          _bottomDrawerController.reverse();
                        } else if (_bottomDrawerController.value > 0.5) {
                          _bottomDrawerController.forward();
                        } else {
                          _bottomDrawerController.reverse();
                        }
                      },
                      onTap: () {
                        if (_bottomDrawerController.value < 0.5) {
                          _bottomDrawerController.forward();
                        } else {
                          _bottomDrawerController.reverse();
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 0),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppTheme.outlineVariant
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          Icon(
                            drawerOpen
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            size: 22,
                            color: AppTheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: contentH,
                    child: ClipRect(
                      child: SingleChildScrollView(
                        physics: drawerOpen
                            ? const ClampingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: _buildOrderBottomBar(
                            context,
                            l10n,
                            stretchForDrawer: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Notes (gray) + totals/VAT/save (black). Drawer mode uses fixed height + stretched notes.
  Widget _buildOrderBottomBar(
    BuildContext context,
    AppLocalizations? l10n, {
    bool stretchForDrawer = false,
  }) {
    final notesCard = _buildOrderNotesBottomCard(
      context,
      l10n,
      expands: stretchForDrawer,
    );
    final summaryCard = _buildOrderSummaryBottomCard(
      context,
      l10n,
      fillVertical: stretchForDrawer,
    );

    if (stretchForDrawer) {
      // Fixed notes height so the summary column is not squeezed (overflow).
      const drawerNotesH = 96.0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              height: drawerNotesH,
              child: notesCard,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: summaryCard),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summaryCard,
              const SizedBox(height: 16),
              notesCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: notesCard),
              const SizedBox(width: 20),
              Expanded(child: summaryCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderNotesBottomCard(
    BuildContext context,
    AppLocalizations? l10n, {
    bool expands = false,
  }) {
    final decoration = InputDecoration(
      labelText: _orderTableColumnLabel(
        context,
        l10n,
        'orderNotesTitle',
        en: 'Order notes',
        he: 'הערות להזמנה',
        ar: 'ملاحظات الطلب',
      ),
      labelStyle: GoogleFonts.assistant(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppTheme.onSurfaceVariant,
      ),
      floatingLabelStyle: GoogleFonts.assistant(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppTheme.secondary,
      ),
      hintText: _orderTableColumnLabel(
        context,
        l10n,
        'orderNotesHint',
        en: 'Internal notes, delivery details…',
        he: 'הערות פנימיות, אספקה…',
        ar: 'ملاحظات داخلية، التسليم…',
      ),
      hintStyle: GoogleFonts.assistant(
        color: AppTheme.onSurfaceVariant.withValues(alpha: 0.55),
        fontSize: 14,
      ),
      alignLabelWithHint: true,
      filled: true,
      fillColor: AppTheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: AppTheme.secondary,
          width: 1.8,
        ),
      ),
      contentPadding: EdgeInsets.all(expands ? 8 : 16),
    );

    final field = TextField(
      controller: _notesController,
      expands: expands,
      enabled: !_isReadOnly,
      minLines: expands ? null : 5,
      maxLines: expands ? null : 8,
      textAlignVertical: expands ? TextAlignVertical.top : null,
      style: GoogleFonts.assistant(
        fontSize: 15,
        color: AppTheme.onSurface,
        height: 1.4,
      ),
      decoration: decoration,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      padding: EdgeInsets.all(expands ? 8 : 20),
      child: expands ? SizedBox.expand(child: field) : field,
    );
  }

  Future<void> _showLineSupplierNoteDialog(
    BuildContext context,
    AppLocalizations? l10n,
    _ItemRow row,
  ) async {
    final ctrl = TextEditingController(text: row.supplierNote);
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final size = MediaQuery.sizeOf(ctx);
          final dialogWidth = (size.width - 32).clamp(300.0, 760.0);
          final editorHeight = (size.height * 0.42).clamp(240.0, 520.0);
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            title: Text(
              _orderTableColumnLabel(
                context,
                l10n,
                'orderLineSupplierNoteDialogTitle',
                en: 'Note for supplier',
                he: 'הערה לסוכן',
                ar: 'ملاحظة للمورد',
              ),
              style: GoogleFonts.assistant(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            content: SizedBox(
              width: dialogWidth,
              height: editorHeight + 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _orderTableColumnLabel(
                      context,
                      l10n,
                      'orderLineSupplierNoteDialogHint',
                      en: 'Sent only to this line\'s supplier in WhatsApp.',
                      he: 'תישלח רק לסוכן של שורה זו בוואטסאפ.',
                      ar: 'تُرسل فقط لمورد هذا السطر عبر واتساب.',
                    ),
                    style: GoogleFonts.assistant(
                      fontSize: 14,
                      color: AppTheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      enabled: !_isReadOnly,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: orderTableCellDecoration().copyWith(
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: GoogleFonts.assistant(fontSize: 16, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!_isReadOnly)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      setState(() {
                        row.supplierNote = '';
                        _hasUnsavedChanges = true;
                      });
                    }
                  },
                  child: Text(
                    _orderTableColumnLabel(
                      context,
                      l10n,
                      'orderLineSupplierNoteDelete',
                      en: 'Delete note',
                      he: 'מחק הערה',
                      ar: 'حذف الملاحظة',
                    ),
                    style: GoogleFonts.assistant(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  _isReadOnly
                      ? MaterialLocalizations.of(ctx).closeButtonLabel
                      : (l10n?.tr('cancel') ?? 'Cancel'),
                ),
              ),
              if (!_isReadOnly)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (mounted) {
                      setState(() {
                        row.supplierNote = ctrl.text.trim();
                        _hasUnsavedChanges = true;
                      });
                    }
                  },
                  child: Text(
                    _orderTableColumnLabel(
                      context,
                      l10n,
                      'orderLineSupplierNoteSave',
                      en: 'Save',
                      he: 'שמור',
                      ar: 'حفظ',
                    ),
                  ),
                ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Widget _buildOrderSummaryBottomCard(
    BuildContext context,
    AppLocalizations? l10n, {
    bool fillVertical = false,
  }) {
    final subtle = AppTheme.onPrimary.withValues(alpha: 0.72);
    final sub = _subtotalExVat;
    final vat = _vatAmount;
    final discountPct = _discountPercentage;
    final discount = _discountAmount;
    final grand = _grandTotalWithVat;
    final vatToggleLabel = _vatEnabled
        ? _orderTableColumnLabel(
            context,
            l10n,
            'vatRemove',
            en: 'Disable VAT',
            he: 'הורדת מע״מ',
            ar: 'إلغاء الضريبة',
          )
        : _orderTableColumnLabel(
            context,
            l10n,
            'vatEnable',
            en: 'Enable VAT',
            he: 'הפעלת מע״מ',
            ar: 'تفعيل الضريبة',
          );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: fillVertical
          ? const EdgeInsets.fromLTRB(14, 8, 14, 8)
          : const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _isReadOnly
                      ? null
                      : () {
                          setState(() {
                            _vatEnabled = !_vatEnabled;
                            _hasUnsavedChanges = true;
                          });
                        },
                  icon: Icon(
                    _vatEnabled ? Icons.percent : Icons.do_not_disturb_alt,
                    size: 16,
                    color: AppTheme.onPrimary,
                  ),
                  label: Text(
                    vatToggleLabel,
                    style: GoogleFonts.assistant(
                      fontSize: fillVertical ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onPrimary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        AppTheme.onPrimary.withValues(alpha: 0.10),
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: fillVertical ? 4 : 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _discountPctController,
                  focusNode: _discountPctFocusNode,
                  enabled: !_isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: fillVertical ? 6 : 10,
                    ),
                    filled: true,
                    fillColor: AppTheme.onPrimary.withValues(alpha: 0.10),
                    hintText: _discountType == 'percentage'
                        ? _orderTableColumnLabel(
                            context,
                            l10n,
                            'discountPercent',
                            en: 'Discount %',
                            he: 'הנחה %',
                            ar: 'خصم %',
                          )
                        : _orderTableColumnLabel(
                            context,
                            l10n,
                            'discountAmount',
                            en: 'Discount ₪',
                            he: 'הנחה ₪',
                            ar: 'خصم ₪',
                          ),
                    hintStyle: GoogleFonts.assistant(
                      fontSize: fillVertical ? 11 : 12,
                      color: subtle,
                    ),
                    suffixText: _discountType == 'percentage' ? '%' : '₪',
                    suffixStyle: GoogleFonts.assistant(
                      color: subtle,
                      fontWeight: FontWeight.w700,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'percentage',
                    label: Text(
                      '%',
                      style: GoogleFonts.assistant(
                        fontWeight: FontWeight.w700,
                        fontSize: fillVertical ? 11 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.percent_rounded, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'fixed_amount',
                    label: Text(
                      '₪',
                      style: GoogleFonts.assistant(
                        fontWeight: FontWeight.w700,
                        fontSize: fillVertical ? 11 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.attach_money_rounded, size: 16),
                  ),
                ],
                selected: <String>{_discountType},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _discountType = newSelection.first;
                    _markDirty();
                  });
                },
                style: ButtonStyle(
                  side: WidgetStateProperty.all(
                    BorderSide(
                      color: AppTheme.secondary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.secondary;
                    }
                    return AppTheme.onPrimary.withValues(alpha: 0.05);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.onSecondary;
                    }
                    return AppTheme.onPrimary;
                  }),
                ),
              ),
            ],
          ),
          SizedBox(height: fillVertical ? 8 : 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  _orderTableColumnLabel(
                    context,
                    l10n,
                    'totalBeforeVat',
                    en: 'Total before VAT',
                    he: 'סה"כ לפני מע"מ',
                    ar: 'الإجمالي قبل الضريبة',
                  ),
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: subtle,
                  ),
                ),
              ),
              Text(
                '₪${sub.toStringAsFixed(2)}',
                style: GoogleFonts.assistant(
                  fontSize: fillVertical ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onPrimary,
                ),
              ),
            ],
          ),
          if (_vatEnabled) ...[
            SizedBox(height: fillVertical ? 6 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _orderTableColumnLabel(
                      context,
                      l10n,
                      'vatWithRate',
                      en: 'VAT (18%)',
                      he: 'מע"מ (18%)',
                      ar: 'ضريبة القيمة المضافة (18٪)',
                    ),
                    style: GoogleFonts.assistant(
                      fontSize: fillVertical ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: subtle,
                    ),
                  ),
                ),
                Text(
                  '₪${vat.toStringAsFixed(2)}',
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onPrimary,
                  ),
                ),
              ],
            ),
          ],
          if (discount > 0) ...[
            SizedBox(height: fillVertical ? 6 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _discountType == 'percentage'
                        ? '${_orderTableColumnLabel(
                            context,
                            l10n,
                            'discountLabel',
                            en: 'Discount',
                            he: 'הנחה',
                            ar: 'خصم',
                          )} (-${formatQty(discountPct)}%)'
                        : _orderTableColumnLabel(
                            context,
                            l10n,
                            'discountLabel',
                            en: 'Discount',
                            he: 'הנחה',
                            ar: 'خصم',
                          ),
                    style: GoogleFonts.assistant(
                      fontSize: fillVertical ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
                Text(
                  '-₪${discount.toStringAsFixed(2)}',
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 11 : 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: fillVertical ? 8 : 12),
          Divider(
            height: 1,
            color: AppTheme.onPrimary.withValues(alpha: 0.2),
          ),
          SizedBox(height: fillVertical ? 10 : 14),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: fillVertical ? 10 : 12,
              vertical: fillVertical ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.08),
              border: Border(
                left: BorderSide(
                  color: AppTheme.secondary,
                  width: 3,
                ),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _orderTableColumnLabel(
                          context,
                          l10n,
                          'totalToPay',
                          en: 'Total to pay',
                          he: 'סה"כ לתשלום',
                          ar: 'الإجمالي للدفع',
                        ),
                        style: GoogleFonts.assistant(
                          fontSize: fillVertical ? 14 : 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onPrimary,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: fillVertical ? 2 : 4),
                      Text(
                        _orderTableColumnLabel(
                          context,
                          l10n,
                          'includesEverything',
                          en: 'Includes everything',
                          he: 'כולל הכל',
                          ar: 'شامل كل شيء',
                        ),
                        style: GoogleFonts.assistant(
                          fontSize: fillVertical ? 10 : 11,
                          fontWeight: FontWeight.w400,
                          color: subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₪${grand.toStringAsFixed(2)}',
                      style: GoogleFonts.assistant(
                        fontSize: fillVertical ? 20 : 32,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.secondary,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: fillVertical ? 6 : 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading || _isReadOnly ? null : _saveOrder,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                foregroundColor: AppTheme.onSecondary,
                disabledBackgroundColor:
                    AppTheme.secondary.withValues(alpha: 0.5),
                padding: EdgeInsets.symmetric(
                  vertical: fillVertical ? 7 : 16,
                  horizontal: fillVertical ? 12 : 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                _orderTableColumnLabel(
                  context,
                  l10n,
                  'saveOrder',
                  en: 'Save order',
                  he: 'שמור הזמנה',
                  ar: 'حفظ الطلب',
                ),
                style: GoogleFonts.assistant(
                  fontSize: fillVertical ? 15 : 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (!_waitingSupplierConfirmation) ...[
            SizedBox(height: fillVertical ? 8 : 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_isLoading || !_canSendToSupplier)
                    ? null
                    : _sendOrderToSuppliers,
                icon: Icon(
                  Icons.send_rounded,
                  size: 18,
                  color: _canSendToSupplier
                      ? AppTheme.onPrimary
                      : AppTheme.onPrimary.withValues(alpha: 0.45),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _canSendToSupplier
                      ? AppTheme.onPrimary
                      : AppTheme.onPrimary.withValues(alpha: 0.45),
                  side: BorderSide(
                    color: AppTheme.secondary.withValues(
                      alpha: _canSendToSupplier ? 0.95 : 0.4,
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: fillVertical ? 6 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  _orderTableColumnLabel(
                    context,
                    l10n,
                    'sendToSupplier',
                    en: 'Send to supplier',
                    he: 'שלח לסוכן',
                    ar: 'إرسال إلى المورد',
                  ),
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 14 : 15,
                    fontWeight: FontWeight.w800,
                    color: _canSendToSupplier
                        ? null
                        : AppTheme.onPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ],
          if (_waitingSupplierConfirmation) ...[
            SizedBox(height: fillVertical ? 8 : 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _cancelSupplierWaitingOrder,
                icon: const Icon(Icons.cancel_rounded, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side:
                      BorderSide(color: AppTheme.error.withValues(alpha: 0.75)),
                  padding: EdgeInsets.symmetric(
                    vertical: fillVertical ? 6 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  l10n?.tr('cancel') ?? 'Cancel',
                  style: GoogleFonts.assistant(
                    fontSize: fillVertical ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Resolves ARB labels; if the bundle is stale and returns the key, use locale fallbacks.
  String _orderTableColumnLabel(
    BuildContext context,
    AppLocalizations? l10n,
    String key, {
    required String en,
    required String he,
    required String ar,
  }) {
    final t = l10n?.tr(key) ?? '';
    if (t.isNotEmpty && t != key) return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
  }

  String _orderFormAppBarTitle(BuildContext context, AppLocalizations? l10n) {
    if (_isEdit) {
      final n = _existingOrder?.orderNumber ?? '';
      final word = _orderTableColumnLabel(
        context,
        l10n,
        'order',
        en: 'Order',
        he: 'הזמנה',
        ar: 'طلب',
      );
      return '$word #$n';
    }
    return _orderTableColumnLabel(
      context,
      l10n,
      'newOrder',
      en: 'New Order',
      he: 'הזמנה חדשה',
      ar: 'طلب جديد',
    );
  }

  /// Same rule as orders list workflow: line counts for supplier send/receive.
  bool _lineHasSupplierOnRow(_ItemRow r) =>
      (r.supplierId ?? '').trim().isNotEmpty;

  void _syncItemRowIdsAndFlagsFromOrder(Order order) {
    if (order.items.length != _items.length) return;
    for (var i = 0; i < _items.length; i++) {
      final src = order.items[i];
      _items[i].orderItemId = src.id;
      _items[i].supplierReceived = src.supplierReceived;
      _items[i].readyForPickup = src.readyForPickup;
      _items[i].inventoryDeducted = src.inventoryDeducted;
      _items[i].supplierNote = src.notes ?? '';
    }
  }

  WidgetStateProperty<Color>? _orderItemRowHighlight(_ItemRow item) {
    if (_lineHasSupplierOnRow(item)) {
      if (item.supplierReceived) {
        return WidgetStateProperty.all(
          AppTheme.success.withValues(alpha: 0.12),
        );
      }
      if (item.readyForPickup) {
        return WidgetStateProperty.all(
          AppTheme.secondary.withValues(alpha: 0.12),
        );
      }
    }
    return null;
  }

  /// Stock-based status for a row: compares the inventory's available stock to the
  /// quantity entered on the line. Returns one of:
  ///   * "במלאי" (in stock) — when stock >= quantity
  ///   * "חלקי"  (partial)  — when 0 < stock < quantity, with the shortage shown as detail
  ///   * "חסר"   (missing)  — when stock <= 0, with the full quantity shown as detail
  /// Rows manually marked as already-in-store also show "במלאי". Rows not linked
  /// to an inventory item show "—".
  ({
    String label,
    String? detail,
    Color primaryColor,
    Color? detailColor,
    Color? rowTint,
  }) _orderLineStatusForRow(
    BuildContext context,
    AppLocalizations? l10n,
    _ItemRow item,
    List<InventoryItem> inventoryItems,
  ) {
    final inStockLabel = _orderTableColumnLabel(
      context,
      l10n,
      'orderStockStatusInStock',
      en: 'In stock',
      he: 'במלאי',
      ar: 'متوفر',
    );

    final invId = (item.inventoryItemId ?? '').trim();
    if (invId.isEmpty) {
      return (
        label: '—',
        detail: null,
        primaryColor: AppTheme.onSurfaceVariant,
        detailColor: null,
        rowTint: null,
      );
    }

    final inv = inventoryItems.where((it) => it.id == invId).firstOrNull;
    if (inv == null) {
      return (
        label: '—',
        detail: null,
        primaryColor: AppTheme.onSurfaceVariant,
        detailColor: null,
        rowTint: null,
      );
    }

    final qty = _parseQty(item.quantityCtrl.text);
    final stock = inv.availableStock;

    if (stock >= qty) {
      return (
        label: inStockLabel,
        detail: null,
        primaryColor: AppTheme.success,
        detailColor: null,
        rowTint: AppTheme.success.withValues(alpha: 0.10),
      );
    }
    return (
      label: _orderTableColumnLabel(
        context,
        l10n,
        'orderStockStatusMissing',
        en: 'Out of stock',
        he: 'חסר במלאי',
        ar: 'غير متوفر',
      ),
      detail: '${qty - stock}',
      primaryColor: AppTheme.error,
      detailColor: AppTheme.error,
      rowTint: AppTheme.error.withValues(alpha: 0.10),
    );
  }

  /// Same radius and padding as [orderTableCellDecoration] pills; fill + border
  /// follow the status accent (semantic color of the text).
  BoxDecoration _orderLineStatusPillDecoration(Color accent) {
    return BoxDecoration(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: accent.withValues(alpha: 0.45),
        width: 1,
      ),
    );
  }

  Widget _orderTableHeader(
    BuildContext context,
    AppLocalizations? l10n,
    String key, {
    required String en,
    required String he,
    required String ar,
  }) {
    final label =
        _orderTableColumnLabel(context, l10n, key, en: en, he: he, ar: ar);
    return Text(
      label,
      style: GoogleFonts.assistant(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.onSurfaceVariant,
        letterSpacing: 0.15,
        height: 1.2,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildItemsTable(
    BuildContext context,
    AppLocalizations? l10n,
    List<Supplier> suppliers,
    List<InventoryItem> inventoryItems, {
    bool readOnly = false,
  }) {
    final cellStyle = GoogleFonts.assistant(
      color: AppTheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final lineTotalDecoration = BoxDecoration(
      color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: AppTheme.outlineVariant.withValues(alpha: 0.22),
      ),
    );

    final headerTopRadius = BorderRadiusDirectional.only(
      topStart: const Radius.circular(20),
      topEnd: const Radius.circular(20),
    ).resolve(Directionality.of(context));

    return ClipRRect(
      borderRadius: headerTopRadius,
      clipBehavior: Clip.antiAlias,
      child: DataTable(
        headingRowHeight: 56,
        dataRowMinHeight: 56,
        dataRowMaxHeight: 92,
        columnSpacing: 12,
        headingRowColor: WidgetStateProperty.all(
          AppTheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        columns: [
          DataColumn(
            label: Text(
              '#',
              style: GoogleFonts.assistant(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'orderFormTableProductCode',
              en: 'Product code',
              he: 'קוד גוף',
              ar: 'رمز المنتج',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'orderFormTableItemName',
              en: 'Item name',
              he: 'שם גוף',
              ar: 'اسم الصنف',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'quantity',
              en: 'Qty',
              he: 'כמות',
              ar: 'الكمية',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'orderFormStockStatus',
              en: 'Stock',
              he: 'מלאי גוף',
              ar: 'المخزون',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'unitPrice',
              en: 'Unit price',
              he: 'מחיר ליחידה',
              ar: 'سعر الوحدة',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'extras',
              en: 'Extras',
              he: 'תוספות',
              ar: 'إضافات',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'extrasPrice',
              en: 'Add-ons price',
              he: 'מחיר תוספות',
              ar: 'سعر الإضافات',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'deliveryDate',
              en: 'Delivery',
              he: 'תאריך משלוח',
              ar: 'التسليم',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'assemblyRequired',
              en: 'Assembly',
              he: 'דרוש הרכבה',
              ar: 'التجميع',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'warranty',
              en: 'Warranty',
              he: 'אחריות',
              ar: 'الضمان',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'room',
              en: 'Room',
              he: 'חדר',
              ar: 'الغرفة',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'supplier',
              en: 'Supplier',
              he: 'סוכן',
              ar: 'المورد',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'orderLineSupplierNoteColumn',
              en: 'Supplier note',
              he: 'הערה לסוכן',
              ar: 'ملاحظة للمورد',
            ),
          ),
          DataColumn(
            label: _orderTableHeader(
              context,
              l10n,
              'lineTotal',
              en: 'Line total',
              he: 'סה"כ שורה',
              ar: 'إجمالي السطر',
            ),
          ),
          const DataColumn(label: SizedBox.shrink()),
        ],
        rows: List.generate(_items.length, (index) {
          final item = _items[index];
          final lineStatus =
              _orderLineStatusForRow(context, l10n, item, inventoryItems);
          final rowTint = lineStatus.rowTint;
          return DataRow(
            color: rowTint != null
                ? WidgetStateProperty.all(rowTint)
                : _orderItemRowHighlight(item),
            cells: [
              DataCell(
                Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: item.itemNumberKey,
                          controller: item.itemNumberCtrl,
                          enabled: !readOnly,
                          onChanged: (_) {
                            _markDirty();
                            if (item.inventoryItemId != null) {
                              setState(() {
                                _resetRowInventoryLink(item);
                                item.nameCtrl.clear();
                              });
                            }
                            _showInventorySuggestions(
                              context: context,
                              anchorKey: item.itemNumberKey,
                              row: item,
                              items: inventoryItems,
                              l10n: l10n,
                              fromNameField: false,
                            );
                          },
                          decoration: orderTableCellDecoration(),
                          style: cellStyle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: l10n?.tr('scanBarcode') ?? 'Scan barcode',
                        icon:
                            const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        onPressed: readOnly
                            ? null
                            : () async {
                                final code =
                                    await BarcodeScanDialog.show(context);
                                if (!mounted || code == null) return;
                                setState(() {
                                  _markDirty();
                                  item.itemNumberCtrl.text = code;
                                  _showInventorySuggestions(
                                    context: context,
                                    anchorKey: item.itemNumberKey,
                                    row: item,
                                    items: inventoryItems,
                                    l10n: l10n,
                                    fromNameField: false,
                                  );
                                });
                              },
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        tooltip: l10n?.tr('inventory') ?? 'Inventory',
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        onPressed:
                            readOnly ? null : () => _pickFromInventory(item),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 192,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: item.nameKey,
                          controller: item.nameCtrl,
                          enabled: !readOnly,
                          onChanged: (_) {
                            _markDirty();
                            if (item.inventoryItemId != null) {
                              setState(() {
                                _resetRowInventoryLink(item);
                                item.itemNumberCtrl.clear();
                              });
                            }
                            _showInventorySuggestions(
                              context: context,
                              anchorKey: item.nameKey,
                              row: item,
                              items: inventoryItems,
                              l10n: l10n,
                              fromNameField: true,
                            );
                          },
                          decoration: orderTableCellDecoration(),
                          style: cellStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(builder: (context) {
                        final hasImg = item.imageUrl != null &&
                            item.imageUrl!.trim().isNotEmpty;
                        final canUpload =
                            !readOnly && _rowIsManualEntry(item);
                        final isInteractive = hasImg || canUpload;
                        return InkWell(
                          onTap: isInteractive
                              ? () => _onItemImageTapped(item, l10n)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.outlineVariant
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: hasImg
                                    ? CachedNetworkImage(
                                        imageUrl: item.imageUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.image_outlined,
                                        size: 18,
                                        color: AppTheme.outline
                                            .withValues(alpha: 0.55),
                                      ),
                              ),
                              if (canUpload)
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            AppTheme.surfaceContainerLowest,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      size: 11,
                                      color: AppTheme.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: item.quantityCtrl,
                    focusNode: item.quantityFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    enableSuggestions: false,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    enabled: !readOnly,
                    onChanged: (_) {
                      _markDirty();
                      setState(() {});
                    },
                    decoration: orderTableCellDecoration().copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 14,
                      ),
                    ),
                    style: cellStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 88,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: _orderLineStatusPillDecoration(
                      lineStatus.primaryColor,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lineStatus.label,
                          style: cellStyle.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: lineStatus.primaryColor,
                            height: 1.15,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lineStatus.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            lineStatus.detail!,
                            style: cellStyle.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color:
                                  lineStatus.detailColor ?? AppTheme.secondary,
                              height: 1.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: item.priceCtrl,
                    focusNode: item.priceFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    enableSuggestions: false,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    enabled: !readOnly,
                    onChanged: (_) {
                      _markDirty();
                      setState(() {});
                    },
                    decoration: orderTableCellDecoration(),
                    style: cellStyle,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: item.extrasCtrl,
                    enabled: !readOnly,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) {
                      _markDirty();
                      setState(() {});
                    },
                    decoration: orderTableCellDecoration(),
                    style: cellStyle,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: item.extrasPriceCtrl,
                    focusNode: item.extrasPriceFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    enableSuggestions: false,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    enabled: !readOnly,
                    onChanged: (_) {
                      _markDirty();
                      setState(() {});
                    },
                    decoration: orderTableCellDecoration(),
                    style: cellStyle,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 118,
                  child: IgnorePointer(
                    ignoring: readOnly,
                    child: InkWell(
                      onTap: () => _pickItemDeliveryDate(item),
                      borderRadius: BorderRadius.circular(18),
                      child: InputDecorator(
                        isEmpty: item.deliveryDate == null,
                        decoration: orderTableCellDecoration().copyWith(
                          suffixIcon: item.deliveryDate != null && !readOnly
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: () => setState(() {
                                    _markDirty();
                                    item.deliveryDate = null;
                                  }),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: AppTheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          AppDateFormat.tableOrEmpty(item.deliveryDate),
                          style: cellStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DataCell(
                AppAnimatedSquareCheckbox(
                  value: item.assemblyRequired,
                  onChanged: readOnly
                      ? null
                      : (v) => setState(() {
                            _markDirty();
                            final next = v ?? false;
                            item.assemblyRequired = next;
                            if (next && !_assemblyRequired) {
                              _assemblyRequired = true;
                            }
                          }),
                  activeColor: AppTheme.secondary,
                ),
              ),
              DataCell(
                SizedBox(
                  width: 124,
                  child: DropdownMenu<int>(
                    key: ValueKey('of_warranty_${index}_${item.warrantyYears}'),
                    enabled: !readOnly,
                    initialSelection:
                        item.warrantyYears == 3 || item.warrantyYears == 5
                            ? item.warrantyYears
                            : 0,
                    width: 124,
                    selectOnly: true,
                    enableFilter: false,
                    enableSearch: false,
                    menuStyle: appDropdownMenuStyle(),
                    inputDecorationTheme: appDropdownInputDecorationTheme(),
                    decorationBuilder: animatedDropdownDecorationBuilder(
                      label: Text(
                        _orderTableColumnLabel(
                          context,
                          l10n,
                          'warranty',
                          en: 'Warranty',
                          he: 'אחריות',
                          ar: 'الضمان',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      iconSize: 18,
                    ),
                    textStyle: cellStyle.copyWith(fontSize: 12),
                    onSelected: (v) => setState(() {
                      _markDirty();
                      item.warrantyYears = v ?? 0;
                    }),
                    dropdownMenuEntries: [
                      DropdownMenuEntry<int>(
                        value: 0,
                        label: _orderTableColumnLabel(
                          context,
                          l10n,
                          'warrantyNone',
                          en: 'No warranty',
                          he: 'ללא אחריות',
                          ar: 'بدون ضمان',
                        ),
                      ),
                      DropdownMenuEntry<int>(
                        value: 3,
                        label: _orderTableColumnLabel(
                          context,
                          l10n,
                          'warranty3Years',
                          en: '3 years',
                          he: '3 שנים',
                          ar: '3 سنوات',
                        ),
                      ),
                      DropdownMenuEntry<int>(
                        value: 5,
                        label: _orderTableColumnLabel(
                          context,
                          l10n,
                          'warranty5Years',
                          en: '5 years',
                          he: '5 שנים',
                          ar: '5 سنوات',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: ValueKey('of_room_$index'),
                    controller: item.roomCtrl,
                    enabled: !readOnly,
                    onChanged: (_) {
                      _markDirty();
                    },
                    decoration: orderTableCellDecoration(),
                    style: cellStyle,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 148,
                  child: DropdownMenu<String?>(
                    key: ValueKey(
                      'of_sup_${index}_${item.supplierId}_${suppliers.length}',
                    ),
                    enabled: !readOnly,
                    initialSelection: item.supplierId,
                    width: 148,
                    selectOnly: true,
                    enableFilter: false,
                    enableSearch: false,
                    menuStyle: appDropdownMenuStyle(),
                    inputDecorationTheme: appDropdownInputDecorationTheme(),
                    decorationBuilder: animatedDropdownDecorationBuilder(
                      label: Text(
                        l10n?.tr('supplier') ?? 'Supplier',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      iconSize: 18,
                    ),
                    textStyle: cellStyle.copyWith(fontSize: 12),
                    onSelected: (v) => setState(() {
                      _markDirty();
                      item.supplierId = v;
                    }),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry<String?>(
                        value: null,
                        label: '—',
                      ),
                      ...suppliers.map(
                        (s) => DropdownMenuEntry<String?>(
                          value: s.id,
                          label: s.companyName,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                Center(
                  child: IconButton(
                    tooltip: _orderTableColumnLabel(
                      context,
                      l10n,
                      'orderLineSupplierNoteColumn',
                      en: 'Supplier note',
                      he: 'הערה לסוכן',
                      ar: 'ملاحظة للمورد',
                    ),
                    onPressed: () =>
                        _showLineSupplierNoteDialog(context, l10n, item),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 22,
                          color: item.supplierNote.trim().isNotEmpty
                              ? AppTheme.secondary
                              : AppTheme.onSurfaceVariant,
                        ),
                        if (item.supplierNote.trim().isNotEmpty)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppTheme.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              DataCell(
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: lineTotalDecoration,
                  child: Text(
                    '₪${_lineTotal(item).toStringAsFixed(0)}',
                    style: GoogleFonts.assistant(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurface,
                    ),
                  ),
                ),
              ),
              DataCell(
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppTheme.error,
                    size: 20,
                  ),
                  onPressed: readOnly
                      ? null
                      : () {
                          if (_items.length > 1) {
                            setState(() => _items.removeAt(index));
                          }
                        },
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<bool> _saveOrder() async {
    if (_selectedCustomer == null) {
      await _showSelectCustomerRequiredDialog();
      return false;
    }

    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Order is locked. Only cancel is allowed.')),
      );
      return false;
    }

    if (_loadFailed) {
      final lang = Localizations.localeOf(context).languageCode;
      final message = switch (lang) {
        'he' => 'שגיאה בטעינת ההזמנה. חזור ונסה שוב.',
        'ar' => 'فشل تحميل الطلب. ارجع وحاول مرة أخرى.',
        _ => 'Failed to load order. Please go back and try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return false;
    }

    // Validate items: check if any row has both code and name empty
    final emptyItemIndex = _items.indexWhere((item) {
      final codeTrimmed = item.itemNumberCtrl.text.trim();
      final nameTrimmed = item.nameCtrl.text.trim();
      return codeTrimmed.isEmpty && nameTrimmed.isEmpty;
    });

    if (emptyItemIndex >= 0) {
      final lang = Localizations.localeOf(context).languageCode;
      final message = switch (lang) {
        'he' => 'שורה ${emptyItemIndex + 1}: חובה להזין קוד או שם לפחות',
        'ar' => 'الصف ${emptyItemIndex + 1}: يجب إدخال رمز أو اسم على الأقل',
        _ => 'Row ${emptyItemIndex + 1}: Code or name is required',
      };
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    // Session expiry check — if JWT is dead, log out cleanly instead of
    // hitting the wire with an expired token (which surfaces as PGRST116).
    final auth = ref.read(authServiceProvider);
    if (!auth.hasValidSession) {
      final lang = Localizations.localeOf(context).languageCode;
      final message = switch (lang) {
        'he' => 'פג תוקף ההתחברות. נא להתחבר מחדש.',
        'ar' => 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى.',
        _ => 'Session expired. Please sign in again.',
      };
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.assistant()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
      await auth.signOut();
      return false;
    }

    setState(() => _isLoading = true);

    try {
      final isCreateFlow = !_isEdit;
      final username = ref.read(currentUsernameProvider);
      final orderItems = _items.map((item) {
        final roomTrim = item.roomCtrl.text.trim();
        // For new items, generate a UUID on the client side
        final itemId = (item.orderItemId != null && item.orderItemId!.trim().isNotEmpty)
            ? item.orderItemId
            : const Uuid().v4();
        return OrderItem(
          id: itemId,
          itemNumber: item.itemNumberCtrl.text.trim(),
          name: item.nameCtrl.text.trim(),
          imageUrl: item.imageUrl,
          quantity: _parseQty(item.quantityCtrl.text),
          extras: item.extrasCtrl.text.trim(),
          notes: item.supplierNote.trim().isEmpty
              ? null
              : item.supplierNote.trim(),
          price: parseDecimalInput(item.priceCtrl.text),
          extrasPrice: parseDecimalInput(item.extrasPriceCtrl.text),
          assemblyRequired: item.assemblyRequired,
          roomId: null,
          roomLabel: roomTrim.isEmpty ? null : roomTrim,
          supplierId: item.supplierId,
          deliveryDate: item.deliveryDate,
          existingInStore: item.existingInStore,
          supplierReceived: item.supplierReceived,
          readyForPickup: item.readyForPickup,
          inventoryItemId: item.inventoryItemId,
          inventoryDeducted: item.inventoryDeducted,
          warrantyYears: item.warrantyYears,
          createdBy: username,
          updatedBy: username,
        );
      }).toList();

      if (_isEdit && _existingOrder != null) {
        // Update existing order
        final orderId = _existingOrder!.id;
        await ref.read(orderServiceProvider).update(
          orderId,
          {
            'customer_id': _selectedCustomer!.id,
            'assembly_required': _assemblyRequired,
            'assembly_date': _assemblyDate?.toIso8601String().split('T').first,
            'delivery_date': _orderDeliveryDateAggregate()
                ?.toIso8601String()
                .split('T')
                .first,
            'assembly_price': _assemblyRequired ? _assemblyInstallPrice : 0,
            'total_price': _grandTotalWithVat,
            'vat_enabled': _vatEnabled,
            'discount_type': _discountType,
            'discount_percentage': _discountStoredValue,
            'notes': _notesController.text.trim(),
            'updated_by': username,
          },
        );
        await ref
            .read(orderServiceProvider)
            .updateItems(orderId, orderItems, username);

        _existingOrder = await ref.read(orderServiceProvider).getById(orderId);
      } else {
        // Create new order
        final order = Order(
          id: '',
          customerId: _selectedCustomer!.id,
          assemblyRequired: _assemblyRequired,
          assemblyDate: _assemblyDate,
          deliveryDate: _orderDeliveryDateAggregate(),
          assemblyPrice: _assemblyRequired ? _assemblyInstallPrice : 0,
          totalPrice: _grandTotalWithVat,
          vatEnabled: _vatEnabled,
          discountType: _discountType,
          discountPercentage: _discountStoredValue,
          notes: _notesController.text.trim(),
          createdBy: username,
          updatedBy: username,
        );
        _existingOrder =
            await ref.read(orderServiceProvider).create(order, orderItems);
        _isEdit = true;

        final sourceQuoteId = widget.sourceQuoteId?.trim();
        if (sourceQuoteId != null && sourceQuoteId.isNotEmpty) {
          await ref.read(quoteServiceProvider).setConvertedOrderId(
                sourceQuoteId,
                _existingOrder!.id,
                username,
              );
          ref.invalidate(quotesProvider);
          ref.invalidate(customerQuotesProvider(_selectedCustomer!.id));
        }
      }

      _syncItemRowIdsAndFlagsFromOrder(_existingOrder!);

      if (mounted) {
        setState(() => _hasUnsavedChanges = false);
      }
      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(customerOrdersProvider(_selectedCustomer!.id));

      final itemsSig = _signatureForOrderItems(orderItems);
      final shouldSendCustomerWa =
          isCreateFlow || (_lastNotifiedCustomerItemsSignature != itemsSig);
      if (shouldSendCustomerWa) {
        await _sendOrderSummaryToCustomer(
          orderItems,
          isOrderItemsUpdate: !isCreateFlow,
        );
      }
      _lastNotifiedCustomerItemsSignature = itemsSig;

      if (mounted) {
        final lang = Localizations.localeOf(context).languageCode;
        final successMessage = switch (lang) {
          'he' => 'ההזמנה נשמרה בהצלחה',
          'ar' => 'تم حفظ الطلب بنجاح',
          _ => 'Order saved successfully',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successMessage,
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;

      // Surface session-expired errors as a clean logout, not as raw exception text.
      // PGRST116 happens when RLS blocks a .single() read after the JWT expires.
      final errStr = e.toString().toLowerCase();
      final isAuthError = errStr.contains('jwt expired') ||
          (errStr.contains('jwt') && errStr.contains('expired')) ||
          errStr.contains('pgrst116') ||
          errStr.contains('401') ||
          errStr.contains('unauthorized');

      final lang = Localizations.localeOf(context).languageCode;

      if (isAuthError) {
        final message = switch (lang) {
          'he' => 'פג תוקף ההתחברות. נא להתחבר מחדש.',
          'ar' => 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى.',
          _ => 'Session expired. Please sign in again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.assistant()),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
        await ref.read(authServiceProvider).signOut();
        return false;
      }

      final errorMessage = switch (lang) {
        'he' => 'שגיאה בשמירה: $e',
        'ar' => 'خطأ في الحفظ: $e',
        _ => 'Error saving: $e',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: GoogleFonts.assistant()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSelectCustomerRequiredDialog() async {
    final lang = Localizations.localeOf(context).languageCode;
    final title = switch (lang) {
      'he' => 'נא לבחור לקוח',
      'ar' => 'يرجى اختيار عميل',
      _ => 'Select a customer',
    };
    final body = switch (lang) {
      'he' =>
        'כדי לשמור את ההזמנה יש לבחור לקוח בשדה ״שם לקוח״. השינויים יישארו במסך עד שתשמור בהצלחה.',
      'ar' =>
        'لحفظ الطلب يجب اختيار عميل في حقل اسم العميل. ستبقى تغييراتك في هذه الشاشة حتى يتم الحفظ بنجاح.',
      _ =>
        'To save the order, choose a customer in the customer field. Your changes stay on this screen until you save successfully.',
    };
    final okLabel = switch (lang) {
      'he' => 'הבנתי',
      'ar' => 'حسناً',
      _ => 'OK',
    };

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(body, style: GoogleFonts.assistant()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              okLabel,
              style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _customerSelectorKey.currentContext;
      if (anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          alignment: 0.12,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      _customerFocusNode.requestFocus();
    });
  }

  Future<_LeaveAction> _confirmLeaveUnsaved(AppLocalizations? l10n) async {
    final lang = Localizations.localeOf(context).languageCode;
    final title = switch (lang) {
      'he' => 'שינויים לא שמורים',
      'ar' => 'تغييرات غير محفوظة',
      _ => 'Unsaved changes',
    };
    final body = switch (lang) {
      'he' => 'יש שינויים שלא נשמרו. האם לשמור את ההזמנה?',
      'ar' => 'هناك تغييرات غير محفوظة. هل تريد حفظ الطلب؟',
      _ => 'You have unsaved changes. Do you want to save the order?',
    };
    final saveLabel = switch (lang) {
      'he' => 'שמור',
      'ar' => 'حفظ',
      _ => 'Save',
    };
    final discardLabel = switch (lang) {
      'he' => 'אל תשמור',
      'ar' => 'تجاهل',
      _ => "Don't save",
    };
    final cancelLabel = l10n?.tr('cancel') ??
        switch (lang) {
          'he' => 'ביטול',
          'ar' => 'إلغاء',
          _ => 'Cancel',
        };

    final result = await showDialog<_LeaveAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: GoogleFonts.assistant(fontWeight: FontWeight.w800)),
        content: Text(body, style: GoogleFonts.assistant()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveAction.cancel),
            child: Text(cancelLabel,
                style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveAction.discard),
            child: Text(discardLabel,
                style: GoogleFonts.assistant(color: AppTheme.error)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _LeaveAction.save),
            child: Text(saveLabel,
                style: GoogleFonts.assistant(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? _LeaveAction.cancel;
  }

  Future<bool> _confirmSendToSuppliers(AppLocalizations? l10n) async {
    final lang = Localizations.localeOf(context).languageCode;
    final title = switch (lang) {
      'he' => 'שליחה לסוכנים',
      'ar' => 'إرسال للمورّدين',
      _ => 'Send to suppliers',
    };
    final body = switch (lang) {
      'he' => 'האם לשלוח את ההזמנה לסוכנים בוואטסאפ?',
      'ar' => 'هل تريد إرسال الطلب للمورّدين عبر واتساب؟',
      _ => 'Send this order to the suppliers via WhatsApp?',
    };
    final sendLabel = switch (lang) {
      'he' => 'שלח',
      'ar' => 'إرسال',
      _ => 'Send',
    };
    final cancelLabel = l10n?.tr('cancel') ??
        switch (lang) {
          'he' => 'ביטול',
          'ar' => 'إلغاء',
          _ => 'Cancel',
        };

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: GoogleFonts.assistant(fontWeight: FontWeight.w800)),
        content: Text(body, style: GoogleFonts.assistant()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel,
                style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(sendLabel,
                style: GoogleFonts.assistant(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _sendOrderSummaryToCustomer(
    List<OrderItem> orderItems, {
    bool isOrderItemsUpdate = false,
  }) async {
    final customer = _selectedCustomer;
    if (customer == null) return;
    if (customer.phones.isEmpty) return;
    final phone = customer.phones.first;
    if (phone.trim().isEmpty) return;

    final code = mounted ? Localizations.localeOf(context).languageCode : 'he';

    final message = _buildCustomerOrderMessage(
      languageCode: code,
      customer: customer,
      orderNumber: _existingOrder?.orderNumber,
      items: orderItems,
      totalPrice: _totalPrice,
      assemblyDate: _assemblyRequired ? _assemblyDate : null,
      isOrderItemsUpdate: isOrderItemsUpdate,
    );

    await WhatsAppService.sendMessage(phone, message);
  }

  /// Stable fingerprint of line-item fields that affect the customer order summary.
  String _signatureForOrderItems(List<OrderItem> items) {
    String money(double v) {
      if (v.isNaN) return '0.00';
      return v.toStringAsFixed(2);
    }

    final parts = <String>[];
    for (final it in items) {
      final dateStr = it.deliveryDate == null
          ? ''
          : it.deliveryDate!.toIso8601String().split('T').first;
      parts.add([
        (it.itemNumber ?? '').trim(),
        it.name.trim(),
        formatQty(it.quantity),
        (it.extras ?? '').trim(),
        money(it.price),
        money(it.extrasPrice),
        it.assemblyRequired ? '1' : '0',
        (it.roomLabel ?? '').trim(),
        (it.supplierId ?? '').trim(),
        dateStr,
        it.warrantyYears.toString(),
        it.existingInStore ? '1' : '0',
        (it.inventoryItemId ?? '').trim(),
        (it.imageUrl ?? '').trim(),
      ].join('\u001f'));
    }
    return '${items.length}\u001e${parts.join('\u001d')}';
  }

  String _buildCustomerOrderMessage({
    required String languageCode,
    required Customer customer,
    required int? orderNumber,
    required List<OrderItem> items,
    required double totalPrice,
    required DateTime? assemblyDate,
    bool isOrderItemsUpdate = false,
  }) {
    final lang =
        (languageCode == 'he' || languageCode == 'ar') ? languageCode : 'en';
    final money = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd/MM/yyyy');

    final greetingName = customer.customerName.trim().isNotEmpty
        ? customer.customerName
        : customer.cardName;

    final greeting = switch (lang) {
      'he' => 'שלום $greetingName (כרטיס: ${customer.cardName}),',
      'ar' => 'مرحبًا $greetingName (البطاقة: ${customer.cardName})،',
      _ => 'Hello $greetingName (card: ${customer.cardName}),',
    };

    final orderHeader = isOrderItemsUpdate
        ? switch (lang) {
            'he' => orderNumber != null
                ? 'עדכון: ההזמנה #$orderNumber עודכנה (שינוי בפריטים) 📋'
                : 'עדכון: ההזמנה עודכנה (שינוי בפריטים) 📋',
            'ar' => orderNumber != null
                ? 'تحديث: تم تعديل الطلب #$orderNumber (تغيير في الأصناف) 📋'
                : 'تحديث: تم تعديل الطلب (تغيير في الأصناف) 📋',
            _ => orderNumber != null
                ? 'Update: order #$orderNumber was revised (line items changed) 📋'
                : 'Update: your order was revised (line items changed) 📋',
          }
        : switch (lang) {
            'he' => orderNumber != null
                ? 'הזמנה חדשה #$orderNumber נפתחה עבורך 🎉'
                : 'הזמנה חדשה נפתחה עבורך 🎉',
            'ar' => orderNumber != null
                ? 'تم فتح طلب جديد #$orderNumber لك 🎉'
                : 'تم فتح طلب جديد لك 🎉',
            _ => orderNumber != null
                ? 'A new order #$orderNumber has been opened for you 🎉'
                : 'A new order has been opened for you 🎉',
          };

    final itemsHeader = switch (lang) {
      'he' => '📦 פריטים:',
      'ar' => '📦 المنتجات:',
      _ => '📦 Items:',
    };
    final qtyLabel =
        switch (lang) { 'he' => 'כמות', 'ar' => 'الكمية', _ => 'Qty' };
    final roomLabel =
        switch (lang) { 'he' => 'חדר', 'ar' => 'الغرفة', _ => 'Room' };
    final extrasLabel =
        switch (lang) { 'he' => 'תוספת', 'ar' => 'إضافة', _ => 'Extras' };
    final priceLabel =
        switch (lang) { 'he' => 'מחיר', 'ar' => 'السعر', _ => 'Price' };

    final itemLines = <String>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final lineTotal = it.quantity * (it.price + it.extrasPrice);
      final name = it.name.trim().isEmpty ? '—' : it.name.trim();
      final extras = (it.extras ?? '').trim();
      final room = (it.roomLabel ?? '').trim();

      final block = StringBuffer();
      block.writeln('${i + 1}) $name');
      final meta = <String>[];
      meta.add('$qtyLabel: ${formatQty(it.quantity)}');
      if (room.isNotEmpty) meta.add('$roomLabel: $room');
      block.writeln('   ${meta.join(' | ')}');
      if (extras.isNotEmpty) {
        final extrasPart = it.extrasPrice > 0
            ? '$extras (+₪${money.format(it.extrasPrice)})'
            : extras;
        block.writeln('   $extrasLabel: $extrasPart');
      }
      block.write('   $priceLabel: ₪${money.format(lineTotal)}');
      itemLines.add(block.toString());
    }

    final totalLabel = switch (lang) {
      'he' => '💰 סה"כ הזמנה',
      'ar' => '💰 إجمالي الطلب',
      _ => '💰 Order total',
    };
    final assemblyLabel = switch (lang) {
      'he' => '🔧 תאריך הרכבה',
      'ar' => '🔧 تاريخ التركيب',
      _ => '🔧 Assembly date',
    };

    final sections = <String>[
      greeting,
      orderHeader,
      '$itemsHeader\n${itemLines.join('\n\n')}',
      '$totalLabel: ₪${money.format(totalPrice)}',
    ];
    if (assemblyDate != null) {
      sections.add('$assemblyLabel: ${dateFmt.format(assemblyDate)}');
    }
    return sections.join('\n\n');
  }

  String _buildSupplierOrderMessage({
    required String languageCode,
    required Supplier supplier,
    required List<_ItemRow> rows,
    required int? orderNumber,
  }) {
    // Suppliers: Arabic falls back to English (per business preference).
    final lang = languageCode == 'he' ? 'he' : 'en';

    final supplierName = (supplier.contactName?.trim().isNotEmpty ?? false)
        ? supplier.contactName!.trim()
        : supplier.companyName.trim();

    final greeting = switch (lang) {
      'he' => 'שלום $supplierName,',
      'ar' => 'مرحبًا $supplierName،',
      _ => 'Hello $supplierName,',
    };
    final intro = switch (lang) {
      'he' => 'מצורפים פריטים שצריך להזמין:',
      'ar' => 'المنتجات المطلوب طلبها:',
      _ => 'Items that need to be ordered:',
    };
    final nameLabel =
        switch (lang) { 'he' => 'שם גוף', 'ar' => 'الاسم', _ => 'Name' };
    final codeLabel =
        switch (lang) { 'he' => 'קוד', 'ar' => 'الكود', _ => 'Code' };
    final qtyLabel =
        switch (lang) { 'he' => 'כמות', 'ar' => 'الكمية', _ => 'Qty' };
    final lineNoteLabel = switch (lang) {
      'he' => 'הערה לפריט זה',
      'ar' => 'ملاحظة لهذا السطر',
      _ => 'Note for this item',
    };
    final orderRefLabel = switch (lang) {
      'he' => 'מיועד להזמנה מספר',
      'ar' => 'لطلب رقم',
      _ => 'For order number',
    };

    final itemLines = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final name =
          r.nameCtrl.text.trim().isEmpty ? '—' : r.nameCtrl.text.trim();
      final code = r.itemNumberCtrl.text.trim();
      final qty = formatQty(_parseQty(r.quantityCtrl.text));
      final noteTrim = r.supplierNote.trim();
      final block = StringBuffer();
      block.writeln('${i + 1}) $nameLabel: $name');
      if (code.isNotEmpty) block.writeln('   $codeLabel: $code');
      block.writeln('   $qtyLabel: $qty');
      if (noteTrim.isNotEmpty) {
        // Keep the note visually under this item only (multi-line indented).
        block.writeln('   $lineNoteLabel:');
        for (final raw in noteTrim.split('\n')) {
          final line = raw.trimRight();
          block.writeln(line.isEmpty ? '' : '      $line');
        }
      }
      itemLines.add(block.toString());
    }

    final sections = <String>[
      greeting,
      intro,
      itemLines.join('\n\n'),
    ];
    if (orderNumber != null) {
      sections.add('$orderRefLabel: $orderNumber');
    }
    return sections.join('\n\n');
  }

  Future<void> _sendOrderToSuppliers() async {
    if (_existingOrder == null) return;
    if (!_canSendToSupplier) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmSendToSuppliers(l10n);
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final username = ref.read(currentUsernameProvider);
      // Fresh supplier rows (phone, contact name) for the IDs currently on the form.
      ref.invalidate(suppliersProvider);
      final suppliers = await ref.read(suppliersProvider.future);

      final Map<String, List<_ItemRow>> grouped = {};
      for (final item in _items) {
        final supplierId = item.supplierId;
        if (supplierId == null || supplierId.isEmpty) continue;
        grouped.putIfAbsent(supplierId, () => []).add(item);
      }

      if (grouped.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No suppliers selected for any product.',
              ),
            ),
          );
        }
        return;
      }

      // Send a WhatsApp message per supplier, with all that supplier's products.
      bool isFirst = true;
      for (final entry in grouped.entries) {
        final supplier = suppliers.where((s) => s.id == entry.key).firstOrNull;
        if (supplier == null ||
            supplier.phone == null ||
            supplier.phone!.isEmpty) {
          continue;
        }

        final lang =
            mounted ? Localizations.localeOf(context).languageCode : 'he';
        final message = _buildSupplierOrderMessage(
          languageCode: lang,
          supplier: supplier,
          rows: entry.value,
          orderNumber: _existingOrder?.orderNumber,
        );

        final phone = supplier.phone!.replaceAll(RegExp(r'[^\d+]'), '');
        if (!isFirst) {
          await Future.delayed(const Duration(seconds: 10));
        }
        await WhatsAppService.sendMessage(phone, message);
        isFirst = false;
      }

      // Lock order: disable editing until admin changes status after confirmation.
      await ref.read(orderServiceProvider).updateStatus(
            _existingOrder!.id,
            OrderStatus.sentToSupplier.dbValue,
            username,
          );

      setState(() {
        _existingOrder = _existingOrder!.copyWith(
          status: OrderStatus.sentToSupplier,
        );
      });

      ref.invalidate(ordersProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirmCancelOrderFromForm(AppLocalizations? l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          _orderTableColumnLabel(
            context,
            l10n,
            'orderCancelConfirmTitle',
            en: 'Cancel this order?',
            he: 'לבטל את ההזמנה?',
            ar: 'إلغاء هذا الطلب؟',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(
          _orderTableColumnLabel(
            context,
            l10n,
            'orderCancelConfirmLead',
            en: 'The order will be marked as canceled. This cannot be undone.',
            he: 'ההזמנה תסומן כמבוטלת. לא ניתן לבטל פעולה זו.',
            ar: 'سيتم تعليم الطلب كملغى. لا يمكن التراجع.',
          ),
          style: GoogleFonts.assistant(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n?.tr('cancel') ?? 'Cancel',
              style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant),
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _orderTableColumnLabel(
                context,
                l10n,
                'orderCancelConfirmAction',
                en: 'Yes, cancel order',
                he: 'כן, בטל הזמנה',
                ar: 'نعم، إلغاء الطلب',
              ),
              style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancelSupplierWaitingOrder() async {
    if (_existingOrder == null) return;
    if (!_waitingSupplierConfirmation) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmCancelOrderFromForm(l10n);
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final username = ref.read(currentUsernameProvider);
      await ref.read(orderServiceProvider).cancelOrder(
            _existingOrder!.id,
            username,
          );

      setState(() {
        _existingOrder = _existingOrder!.copyWith(
          status: OrderStatus.canceled,
        );
      });

      ref.invalidate(ordersProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(totalUnpaidDebtsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _customerFocusNode.removeListener(_onCustomerFocusChange);
    _notesController.removeListener(_markDirty);
    _assemblyPriceController.removeListener(_markDirty);
    _discountPctController.removeListener(_markDirty);
    _discountPctController.removeListener(_onDiscountChanged);
    _notesController.dispose();
    _assemblyPriceFocusNode.dispose();
    _assemblyPriceController.dispose();
    _discountPctFocusNode.dispose();
    _discountPctController.dispose();
    _customerTextController.dispose();
    _customerFocusNode.dispose();
    _bottomDrawerController.dispose();
    _itemsTableHorizontalScrollCtrl.dispose();
    _hideCustomerDropdown();
    _hideInventoryDropdown();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }
}

// (removed) _AssemblyGoldSwitch – replaced with SwitchListTile.adaptive to match
// the inventory add-item toggle style.

/// When a numeric field gains focus, select all text so the next keystroke replaces
/// the value (avoids e.g. "1" + "5" → "15" on tablets).
void _bindSelectAllOnNumericFieldFocus(
  FocusNode node,
  TextEditingController controller,
) {
  node.addListener(() {
    if (!node.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!node.hasFocus) return;
      final len = controller.text.length;
      controller.selection = TextSelection(baseOffset: 0, extentOffset: len);
    });
  });
}

class _ItemRow {
  final itemNumberKey = GlobalKey();
  final nameKey = GlobalKey();
  final itemNumberCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final quantityCtrl = TextEditingController(text: '1');
  final quantityFocusNode = FocusNode();
  final extrasCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '0');
  final priceFocusNode = FocusNode();
  final extrasPriceCtrl = TextEditingController();
  final extrasPriceFocusNode = FocusNode();
  final roomCtrl = TextEditingController();

  _ItemRow() {
    _bindSelectAllOnNumericFieldFocus(quantityFocusNode, quantityCtrl);
    _bindSelectAllOnNumericFieldFocus(priceFocusNode, priceCtrl);
    _bindSelectAllOnNumericFieldFocus(extrasPriceFocusNode, extrasPriceCtrl);
  }

  /// Persisted `order_items.id` when loaded or after save (used to keep workflow flags).
  String? orderItemId;
  bool assemblyRequired = false;
  String? supplierId;
  String? inventoryItemId;
  DateTime? deliveryDate;
  bool existingInStore = false;

  /// From server / workflow: supplier line marked received.
  bool supplierReceived = false;

  /// From server / workflow: line marked ready for customer pickup.
  bool readyForPickup = false;
  bool inventoryDeducted = false;
  int warrantyYears = 0;
  String? imageUrl;

  /// Per-line note included only in WhatsApp to this row's supplier.
  String supplierNote = '';

  void dispose() {
    quantityFocusNode.dispose();
    priceFocusNode.dispose();
    extrasPriceFocusNode.dispose();
    itemNumberCtrl.dispose();
    nameCtrl.dispose();
    quantityCtrl.dispose();
    extrasCtrl.dispose();
    priceCtrl.dispose();
    extrasPriceCtrl.dispose();
    roomCtrl.dispose();
  }
}

enum _LeaveAction { save, discard, cancel }
