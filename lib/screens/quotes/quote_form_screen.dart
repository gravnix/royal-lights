import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/inventory_item.dart';
import '../../models/quote.dart';
import '../../models/quote_item.dart';
import '../../providers/providers.dart';
import '../../services/quote_pdf_service.dart';
import '../../services/whatsapp_service.dart';

String _trOrLocale(
  BuildContext context,
  AppLocalizations? l10n,
  String key, {
  required String en,
  required String he,
  required String ar,
}) {
  final t = l10n?.tr(key) ?? '';
  // If ARB bundle is stale/missing, `tr()` returns the key itself.
  if (t.isNotEmpty && t != key) return t;
  return switch (Localizations.localeOf(context).languageCode) {
    'he' => he,
    'ar' => ar,
    _ => en,
  };
}

InputDecoration _quoteFieldDecoration({
  String? labelText,
  String? hintText,
  String? prefixText,
  Widget? prefixIcon,
  bool isDense = true,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: AppTheme.outlineVariant.withValues(alpha: 0.35),
    ),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixText: prefixText,
    prefixIcon: prefixIcon,
    isDense: isDense,
    filled: true,
    fillColor: AppTheme.surfaceContainerLowest,
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.secondary, width: 1.5),
    ),
    labelStyle: GoogleFonts.assistant(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    hintStyle: GoogleFonts.assistant(
      color: AppTheme.onSurfaceVariant.withValues(alpha: 0.75),
      fontWeight: FontWeight.w500,
      fontSize: 13,
    ),
  );
}

// ─── Quote Form Screen ──────────────────────────────────────────────────────

class _QuoteItemRow {
  final nameKey = GlobalKey();
  final itemNumberCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final quantityCtrl = TextEditingController(text: '1');
  String? inventoryItemId;
  String? imageUrl;
  final extrasCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final extrasPriceCtrl = TextEditingController();

  double get lineTotal {
    final price = double.tryParse(priceCtrl.text) ?? 0;
    final extras = double.tryParse(extrasPriceCtrl.text) ?? 0;
    final qty = double.tryParse(quantityCtrl.text) ?? 1;
    return (price + extras) * qty;
  }
}

/// Build and send a price quote.
///
/// Opened two ways: from a customer's page, which passes [customer]; and from
/// the Quotes screen, which has no customer in context and passes null — the
/// form then shows a picker and the send button stays disabled until one is
/// chosen.
class QuoteFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;

  const QuoteFormScreen({super.key, this.customer});

  @override
  ConsumerState<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends ConsumerState<QuoteFormScreen> {
  final List<_QuoteItemRow> _items = [];
  final _notesController = TextEditingController();
  OverlayEntry? _inventoryOverlayEntry;
  bool _isSending = false;
  bool _inStockOnly = true;

  /// Chosen in the form when the screen was opened without one.
  Customer? _pickedCustomer;

  /// 'percentage' or 'fixed_amount', matching the order form and the DB.
  String _discountType = 'percentage';
  final _discountCtrl = TextEditingController();

  Customer? get _customer => widget.customer ?? _pickedCustomer;

  @override
  void initState() {
    super.initState();
    _items.add(_QuoteItemRow());
  }

  @override
  void dispose() {
    _hideInventoryDropdown();
    _notesController.dispose();
    _discountCtrl.dispose();
    for (final item in _items) {
      item.itemNumberCtrl.dispose();
      item.nameCtrl.dispose();
      item.quantityCtrl.dispose();
      item.extrasCtrl.dispose();
      item.priceCtrl.dispose();
      item.extrasPriceCtrl.dispose();
    }
    super.dispose();
  }

  void _hideInventoryDropdown() {
    _inventoryOverlayEntry?.remove();
    _inventoryOverlayEntry = null;
  }

  /// Header slot: a plain name when the screen was opened from a customer,
  /// a tappable picker when it was opened from the Quotes list.
  Widget _customerBanner(BuildContext context, AppLocalizations? l10n) {
    final customer = _customer;

    if (widget.customer != null && customer != null) {
      return Text(
        '${customer.cardName} — ${customer.customerName}',
        style: GoogleFonts.assistant(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.onSurface,
        ),
      );
    }

    return InkWell(
      onTap: _isSending ? null : _pickCustomer,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Icon(
            customer == null
                ? Icons.person_search_rounded
                : Icons.person_rounded,
            size: 20,
            color: customer == null
                ? AppTheme.onSurfaceVariant
                : AppTheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              customer == null
                  ? _trOrLocale(context, l10n, 'quoteChooseCustomer',
                      en: 'Choose a customer',
                      he: 'בחר לקוח',
                      ar: 'اختر عميلاً')
                  : '${customer.cardName} — ${customer.customerName}',
              style: GoogleFonts.assistant(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: customer == null
                    ? AppTheme.onSurfaceVariant
                    : AppTheme.onSurface,
              ),
            ),
          ),
          Icon(
            Icons.edit_rounded,
            size: 16,
            color: AppTheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomer() async {
    final l10n = AppLocalizations.of(context);
    final customers = await ref.read(customersProvider.future);
    if (!mounted) return;

    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) => _CustomerPickerDialog(customers: customers, l10n: l10n),
    );
    if (picked != null && mounted) {
      setState(() => _pickedCustomer = picked);
    }
  }

  void _applyInventoryToQuoteRow(_QuoteItemRow row, InventoryItem it) {
    row.inventoryItemId = it.id;
    row.imageUrl = it.imageUrl;
    row.nameCtrl.text = it.description;
    row.itemNumberCtrl.text = it.barcode ?? '';
    row.priceCtrl.text = (it.consumerPrice ?? 0).toString();
  }

  void _showQuoteInventorySuggestions({
    required BuildContext context,
    required GlobalKey anchorKey,
    required _QuoteItemRow row,
    required List<InventoryItem> items,
    required AppLocalizations? l10n,
  }) {
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    final overlay = Overlay.of(context);
    final screenW = MediaQuery.sizeOf(context).width;
    const screenMargin = 8.0;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final query = row.nameCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      _hideInventoryDropdown();
      return;
    }

    final filtered = items.where((it) {
      if (_inStockOnly && it.availableStock <= 0) return false;
      final desc = it.description.toLowerCase();
      final brand = (it.brand ?? '').toLowerCase();
      final barcode = (it.barcode ?? '').toLowerCase();
      return desc.contains(query) ||
          brand.contains(query) ||
          barcode.contains(query);
    }).take(12).toList();

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
              final rawLeft = isRtl ? (pos.dx + size.width - desiredW) : pos.dx;
              return rawLeft.clamp(minLeft, maxLeft);
            }(),
            top: pos.dy + size.height + 4,
            width: (size.width + 220).clamp(360.0, 560.0),
            child: Material(
              elevation: 10,
              shadowColor: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
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
                            '${_trOrLocale(context, l10n, 'quoteSelectedStock', en: 'Available now:', he: 'זמין כעת:', ar: 'متوفر الآن:')} ${it.availableStock}',
                          ];
                          return InkWell(
                            onTap: () {
                              if (!mounted) return;
                              setState(() => _applyInventoryToQuoteRow(row, it));
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
                                    width: 56,
                                    height: 56,
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
                                            Icons.inventory_2_outlined,
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
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitleParts.join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.assistant(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.onSurfaceVariant,
                                          ),
                                        ),
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

  Future<void> _pickQuoteItemFromInventory(
    _QuoteItemRow row,
    List<InventoryItem> items,
    AppLocalizations? l10n,
  ) async {
    final pool =
        _inStockOnly ? items.where((it) => it.availableStock > 0).toList() : items;
    final selected = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final searchCtrl = TextEditingController(text: row.nameCtrl.text.trim());
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = pool.where((it) {
              if (query.isEmpty) return true;
              return it.description.toLowerCase().contains(query) ||
                  (it.brand ?? '').toLowerCase().contains(query) ||
                  (it.barcode ?? '').toLowerCase().contains(query);
            }).toList();
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: _quoteFieldDecoration(
                      hintText: _trOrLocale(
                        ctx,
                        l10n,
                        'quoteItemSearchHint',
                        en: 'Type product name, brand, or barcode',
                        he: 'הקלד שם מוצר, מותג או ברקוד',
                        ar: 'اكتب اسم المنتج أو العلامة أو الباركود',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: false,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              l10n?.tr('noMatchingResults') ?? 'No matches',
                              style: GoogleFonts.assistant(
                                color: AppTheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.14),
                            ),
                            itemBuilder: (ctx, i) {
                              final it = filtered[i];
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                leading: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: (it.imageUrl != null &&
                                          it.imageUrl!.trim().isNotEmpty)
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: CachedNetworkImage(
                                            imageUrl: it.imageUrl!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.inventory_2_outlined,
                                            size: 20,
                                          ),
                                        ),
                                ),
                                title: Text(
                                  it.description,
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if ((it.brand ?? '').trim().isNotEmpty)
                                      it.brand!.trim(),
                                    if ((it.barcode ?? '').trim().isNotEmpty)
                                      it.barcode!.trim(),
                                    '${it.availableStock}',
                                  ].join(' · '),
                                  style: GoogleFonts.assistant(),
                                ),
                                trailing: Text(
                                  it.consumerPrice == null
                                      ? '—'
                                      : '₪${it.consumerPrice!.toStringAsFixed(0)}',
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                onTap: () => Navigator.of(ctx).pop(it),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _applyInventoryToQuoteRow(row, selected));
    }
  }

  double get _subtotal =>
      _items.fold<double>(0, (s, i) => s + i.lineTotal);

  /// Raw value typed in the discount box, clamped to something sane.
  /// A percentage caps at 100; a fixed amount cannot exceed the subtotal.
  double get _discountInput {
    final v = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    if (v <= 0) return 0;
    return _discountType == 'percentage'
        ? (v > 100 ? 100 : v)
        : (v > _subtotal ? _subtotal : v);
  }

  /// Discount in shekels.
  double get _discountAmount => _discountType == 'percentage'
      ? _subtotal * (_discountInput / 100)
      : _discountInput;

  /// Discount comes off BEFORE VAT, so VAT is charged on the net amount.
  double get _netTotal => _subtotal - _discountAmount;

  double get _vat => _netTotal * 0.18;

  double get _grandTotal => _netTotal + _vat;

  Future<void> _sendQuote() async {
    final emptyIdx = _items.indexWhere((i) =>
        i.itemNumberCtrl.text.trim().isEmpty &&
        i.nameCtrl.text.trim().isEmpty);
    if (emptyIdx >= 0) {
      final lang = Localizations.localeOf(context).languageCode;
      final msg = switch (lang) {
        'he' => 'שורה ${emptyIdx + 1}: חובה להזין קוד או שם לפחות',
        'ar' => 'الصف ${emptyIdx + 1}: يجب إدخال رمز أو اسم على الأقل',
        _ => 'Row ${emptyIdx + 1}: Code or name is required',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.assistant()),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final customer = _customer;
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, AppLocalizations.of(context),
                'quotePickCustomerFirst',
                en: 'Choose a customer first',
                he: 'יש לבחור לקוח תחילה',
                ar: 'اختر عميلاً أولاً'),
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (customer.phones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.tr('noPhone') ??
                'No phone number available',
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final username = ref.read(currentUsernameProvider);
      final lang = Localizations.localeOf(context).languageCode;
      final quoteItems = _items
          .map((i) => QuoteItem(
                itemNumber: i.itemNumberCtrl.text.trim(),
                name: i.nameCtrl.text.trim(),
                imageUrl: i.imageUrl,
                quantity: double.tryParse(i.quantityCtrl.text) ?? 1,
                extras: i.extrasCtrl.text.trim(),
                price: double.tryParse(i.priceCtrl.text) ?? 0,
                extrasPrice: double.tryParse(i.extrasPriceCtrl.text) ?? 0,
              ))
          .toList();

      final quote = Quote(
        id: '',
        customerId: customer.id,
        totalPrice: _grandTotal,
        discountPercentage: _discountInput,
        discountType: _discountType,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdBy: username,
        updatedBy: username,
      );

      // Save quote + warm PDF fonts/logo at the same time.
      final savedQuoteFuture =
          ref.read(quoteServiceProvider).create(quote, quoteItems);
      final warmFuture = QuotePdfService.warmUp(lang);
      final savedQuote = await savedQuoteFuture;
      await warmFuture;

      final pdfBytes = await QuotePdfService.generate(
        customer: customer,
        quote: savedQuote,
        // Prefer local items so images are available even if DB column
        // migration hasn't been applied yet on every environment.
        items: quoteItems
            .asMap()
            .entries
            .map((e) => e.value.copyWith(
                  imageUrl: e.value.imageUrl ??
                      (e.key < savedQuote.items.length
                          ? savedQuote.items[e.key].imageUrl
                          : null),
                ))
            .toList(),
        languageCode: lang,
      );

      final pdfUrl = await ref
          .read(quoteServiceProvider)
          .uploadPdf(savedQuote.id, pdfBytes);
      // Don't block WhatsApp on the pdf_url DB write.
      final setPdfFuture =
          ref.read(quoteServiceProvider).setPdfUrl(savedQuote.id, pdfUrl);

      String phone = customer.phones.first.replaceAll(RegExp(r'\D'), '');
      if (phone.startsWith('0')) {
        phone = '972${phone.substring(1)}';
      } else if (!phone.startsWith('972')) {
        phone = '972$phone';
      }

      final customerDisplayName = customer.customerName.trim().isNotEmpty
          ? customer.customerName
          : customer.cardName;

      final caption = switch (lang) {
        'he' =>
          'שלום $customerDisplayName,\nמצורפת הצעת מחיר מ-Royal Lights.\nנשמח לעמוד לשירותכם!',
        'ar' =>
          'مرحبًا $customerDisplayName،\nمرفق عرض سعر من Royal Lights.\nنتطلع لخدمتكم!',
        _ =>
          'Hello $customerDisplayName,\nPlease find attached a price quote from Royal Lights.\nWe look forward to serving you!',
      };

      await Future.wait([
        WhatsAppService.sendDocument(phone, pdfUrl, caption),
        setPdfFuture,
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, AppLocalizations.of(context), 'quoteSent',
                en: 'Quote sent',
                he: 'הצעת המחיר נשלחה',
                ar: 'تم إرسال عرض السعر'),
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.assistant()),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = NumberFormat('#,##0.00', 'en_US');
    final inventoryAsync = ref.watch(inventoryItemsProvider);
    // Riverpod 3.x doesn't expose `valueOrNull`; use `asData` for a safe read.
    final inventoryItems =
        inventoryAsync.asData?.value ?? const <InventoryItem>[];
    final visibleInventory = _inStockOnly
        ? inventoryItems.where((it) => it.availableStock > 0).toList()
        : inventoryItems;
    final inventoryById = {
      for (final it in inventoryItems) it.id: it,
    };

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _trOrLocale(context, l10n, 'quoteFormTitle',
              en: 'New price quote',
              he: 'הצעת מחיר חדשה',
              ar: 'عرض سعر جديد'),
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppTheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerHighest
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            AppTheme.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: _customerBanner(context, l10n),
                  ),
                  const SizedBox(height: 20),

                  // In-stock toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'quoteInStockOnlyLabel',
                            en: 'Show in-stock items only',
                            he: 'הצג רק פריטים במלאי',
                            ar: 'عرض العناصر المتوفرة فقط',
                          ),
                          style: GoogleFonts.assistant(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Switch(
                        value: _inStockOnly,
                        onChanged: inventoryItems.isEmpty
                            ? null
                            : (v) => setState(() => _inStockOnly = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Items
                  ...List.generate(_items.length, (index) {
                    final item = _items[index];
                    final selectedInv =
                        item.inventoryItemId != null ? inventoryById[item.inventoryItemId] : null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.outlineVariant
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${_trOrLocale(context, l10n, 'quoteItem', en: 'Item', he: 'פריט', ar: 'صنف')} ${index + 1}',
                                  style: GoogleFonts.assistant(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                if (_items.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: AppTheme.error),
                                    onPressed: () =>
                                        setState(() => _items.removeAt(index)),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (selectedInv != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${_trOrLocale(
                                    context,
                                    l10n,
                                    'quoteSelectedStock',
                                    en: 'Available now:',
                                    he: 'זמין כעת:',
                                    ar: 'متوفر الآن:',
                                  )} ${selectedInv.availableStock}',
                                  style: GoogleFonts.assistant(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: item.nameKey,
                                          controller: item.nameCtrl,
                                          onChanged: (_) {
                                            if (item.inventoryItemId != null) {
                                              setState(() {
                                                item.inventoryItemId = null;
                                                item.imageUrl = null;
                                                item.itemNumberCtrl.clear();
                                              });
                                            } else {
                                              setState(() {});
                                            }
                                            _showQuoteInventorySuggestions(
                                              context: context,
                                              anchorKey: item.nameKey,
                                              row: item,
                                              items: visibleInventory,
                                              l10n: l10n,
                                            );
                                          },
                                          onTap: () {
                                            if (item.nameCtrl.text.trim().isNotEmpty) {
                                              _showQuoteInventorySuggestions(
                                                context: context,
                                                anchorKey: item.nameKey,
                                                row: item,
                                                items: visibleInventory,
                                                l10n: l10n,
                                              );
                                            }
                                          },
                                          decoration: _quoteFieldDecoration(
                                            labelText: _trOrLocale(
                                              context,
                                              l10n,
                                              'quoteProductNameLabel',
                                              en: 'Product name',
                                              he: 'שם המוצר',
                                              ar: 'اسم المنتج',
                                            ),
                                            hintText: _trOrLocale(
                                              context,
                                              l10n,
                                              'quoteItemSearchHintShort',
                                              en: 'Type to search stock',
                                              he: 'הקלד לחיפוש במלאי',
                                              ar: 'اكتب للبحث في المخزون',
                                            ),
                                          ),
                                          style: GoogleFonts.assistant(fontSize: 14),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: _trOrLocale(
                                          context,
                                          l10n,
                                          'quoteItemFromStockLabel',
                                          en: 'Stock item',
                                          he: 'פריט מהמלאי',
                                          ar: 'عنصر من المخزون',
                                        ),
                                        onPressed: inventoryItems.isEmpty
                                            ? null
                                            : () => _pickQuoteItemFromInventory(
                                                  item,
                                                  inventoryItems,
                                                  l10n,
                                                ),
                                        icon: const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: item.itemNumberCtrl,
                                    decoration: _quoteFieldDecoration(
                                      labelText: _trOrLocale(
                                        context,
                                        l10n,
                                        'quoteProductCodeLabel',
                                        en: 'Code',
                                        he: 'מק״ט',
                                        ar: 'الرمز',
                                      ),
                                    ),
                                    style: GoogleFonts.assistant(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: item.quantityCtrl,
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _quoteFieldDecoration(
                                      labelText: _trOrLocale(
                                        context,
                                        l10n,
                                        'quoteQtyLabel',
                                        en: 'Qty',
                                        he: 'כמות',
                                        ar: 'الكمية',
                                      ),
                                    ),
                                    style: GoogleFonts.assistant(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: item.priceCtrl,
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _quoteFieldDecoration(
                                      labelText: _trOrLocale(
                                        context,
                                        l10n,
                                        'quotePriceLabel',
                                        en: 'Price',
                                        he: 'מחיר',
                                        ar: 'السعر',
                                      ),
                                      prefixText: '₪ ',
                                    ),
                                    style: GoogleFonts.assistant(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: item.extrasPriceCtrl,
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _quoteFieldDecoration(
                                      labelText: _trOrLocale(
                                        context,
                                        l10n,
                                        'quoteExtrasPriceLabel',
                                        en: 'Extras price',
                                        he: 'מחיר תוספת',
                                        ar: 'سعر الإضافة',
                                      ),
                                      prefixText: '₪ ',
                                    ),
                                    style: GoogleFonts.assistant(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    '₪${item.lineTotal.toStringAsFixed(0)}',
                                    textAlign: TextAlign.end,
                                    style: GoogleFonts.assistant(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                            TextField(
                              controller: item.extrasCtrl,
                              onChanged: (_) => setState(() {}),
                              decoration: _quoteFieldDecoration(
                                labelText: _trOrLocale(
                                  context,
                                  l10n,
                                  'quoteExtrasDescriptionLabel',
                                  en: 'Extras (description)',
                                  he: 'תוספת (תיאור)',
                                  ar: 'إضافات (وصف)',
                                ),
                              ),
                              style: GoogleFonts.assistant(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Add item button
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _items.add(_QuoteItemRow())),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        _trOrLocale(context, l10n, 'addItem',
                            en: 'Add item',
                            he: 'הוסף פריט',
                            ar: 'إضافة صنف'),
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: _quoteFieldDecoration(
                      labelText: _trOrLocale(context, l10n, 'quoteNotes',
                          en: 'Notes', he: 'הערות', ar: 'ملاحظات'),
                      isDense: false,
                    ),
                    style: GoogleFonts.assistant(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          // Bottom totals + send button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLowest,
              border: Border(
                top: BorderSide(
                  color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _trOrLocale(context, l10n, 'subtotal',
                          en: 'Subtotal', he: 'סכום ביניים', ar: 'المجموع الفرعي'),
                      style: GoogleFonts.assistant(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '₪${money.format(_subtotal)}',
                      style: GoogleFonts.assistant(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Discount — applied BEFORE VAT, so the VAT row below is
                // charged on the discounted amount.
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _discountCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.assistant(fontSize: 14),
                        decoration: _quoteFieldDecoration(
                          labelText: _trOrLocale(context, l10n, 'discountLabel',
                              en: 'Discount', he: 'הנחה', ar: 'خصم'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'percentage', label: Text('%')),
                        ButtonSegment(value: 'fixed_amount', label: Text('₪')),
                      ],
                      selected: {_discountType},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _discountType = v.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          GoogleFonts.assistant(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_discountAmount > 0)
                      Text(
                        '-₪${money.format(_discountAmount)}',
                        style: GoogleFonts.assistant(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.error,
                        ),
                      ),
                  ],
                ),

                if (_discountAmount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _trOrLocale(context, l10n, 'totalAfterDiscount',
                            en: 'Total after discount',
                            he: 'סה״כ אחרי הנחה',
                            ar: 'المجموع بعد الخصم'),
                        style: GoogleFonts.assistant(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '₪${money.format(_netTotal)}',
                        style: GoogleFonts.assistant(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _trOrLocale(context, l10n, 'vat',
                          en: 'VAT 18%', he: 'מע״מ 18%', ar: 'ض.ق.م 18٪'),
                      style: GoogleFonts.assistant(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '₪${money.format(_vat)}',
                      style: GoogleFonts.assistant(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _trOrLocale(context, l10n, 'total',
                          en: 'Total', he: 'סה״כ', ar: 'المجموع'),
                      style: GoogleFonts.assistant(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '₪${money.format(_grandTotal)}',
                      style: GoogleFonts.assistant(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSending ? null : _sendQuote,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      _trOrLocale(context, l10n, 'sendQuoteViaWhatsApp',
                          en: 'Send via WhatsApp',
                          he: 'שלח בוואטסאפ',
                          ar: 'إرسال عبر واتساب'),
                      style: GoogleFonts.assistant(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable customer list, used when a quote is started without one.
class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  final AppLocalizations? l10n;

  const _CustomerPickerDialog({required this.customers, required this.l10n});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.customers;
    return widget.customers.where((c) {
      return c.cardName.toLowerCase().contains(q) ||
          c.customerName.toLowerCase().contains(q) ||
          c.phones.any((p) => p.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final results = _filtered;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppTheme.surfaceContainerLowest,
      child: Container(
        width: 480,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _trOrLocale(context, l10n, 'quoteChooseCustomer',
                  en: 'Choose a customer',
                  he: 'בחר לקוח',
                  ar: 'اختر عميلاً'),
              style: GoogleFonts.assistant(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: GoogleFonts.assistant(color: AppTheme.onSurface),
              decoration: _quoteFieldDecoration(
                hintText: l10n?.tr('search') ?? 'Search',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        l10n?.tr('noData') ?? 'No results',
                        style: GoogleFonts.assistant(
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppTheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (ctx, i) {
                        final c = results[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            c.cardName,
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            [
                              c.customerName,
                              if (c.phones.isNotEmpty) c.phones.first,
                            ].where((e) => e.trim().isNotEmpty).join(' · '),
                            style: GoogleFonts.assistant(
                              fontSize: 12.5,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                          // A quote can't be sent without a phone, so say so here
                          // rather than after the user has filled in every line.
                          trailing: c.phones.isEmpty
                              ? Icon(Icons.phone_disabled_rounded,
                                  size: 16,
                                  color: AppTheme.error.withValues(alpha: 0.7))
                              : null,
                          onTap: () => Navigator.pop(ctx, c),
                        );
                      },
                    ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l10n?.tr('cancel') ?? 'Cancel',
                  style: GoogleFonts.assistant(
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
