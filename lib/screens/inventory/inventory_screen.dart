import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_animations.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/inventory_item.dart';
import '../../models/supplier.dart';
import '../../providers/providers.dart';
import '../../services/whatsapp_service.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../widgets/editorial_screen_title.dart';
import '../../widgets/barcode_scan_dialog.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  bool _fabExpanded = false;

  void _toggleFab() => setState(() => _fabExpanded = !_fabExpanded);

  void _closeFab() {
    if (!_fabExpanded) return;
    setState(() => _fabExpanded = false);
  }

  int _gridCols(double width) {
    const minTileWidth = 185.0;
    const spacing = 14.0;
    final cols = ((width + spacing) / (minTileWidth + spacing)).floor();
    return cols.clamp(2, 4);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _trOrLocale(
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

  String _searchHint() {
    final l10n = AppLocalizations.of(context);
    final t = l10n?.tr('searchItemsHint');
    if (t != null && t.isNotEmpty && t != 'searchItemsHint') return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'ar' => 'ابحث بالوصف، الماركة، الباركود…',
      'en' => 'Search by description, brand, barcode…',
      _ => 'חיפוש לפי תיאור, מותג, ברקוד…',
    };
  }

  Future<void> _openItemDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations? l10n, {
    InventoryItem? existing,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => InventoryItemDialog(
        ref: ref,
        l10n: l10n,
        existingItem: existing,
      ),
    );
  }

  Future<void> _openRefillStockDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations? l10n,
    List<InventoryItem> items,
  ) async {
    InventoryItem? selected;
    final amountCtrl = TextEditingController(text: '1');
    final selectedCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final mq = MediaQuery.sizeOf(ctx);
          return Dialog(
            backgroundColor: AppTheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: AppTheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (mq.width - 32).clamp(360.0, 720.0),
                maxHeight: (mq.height * 0.86).clamp(340.0, 720.0),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: StatefulBuilder(
                  builder: (context, setLocal) {
                    final enable = selected != null &&
                        (int.tryParse(amountCtrl.text.trim()) ?? 0) > 0;
                    final targetH =
                        (mq.height * 0.9).clamp(460.0, 860.0).toDouble();
                    return SizedBox(
                      height: targetH,
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryContainer
                                      .withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: AppTheme.secondary,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _trOrLocale(
                                    context,
                                    l10n,
                                    'refillStockTitle',
                                    en: 'Refill stock',
                                    he: 'מילוי מלאי',
                                    ar: 'تعبئة المخزون',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l10n?.tr('close') ?? 'Close',
                                onPressed: () => Navigator.pop(ctx, false),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Autocomplete<InventoryItem>(
                            optionsBuilder: (value) {
                              final q = value.text.trim().toLowerCase();
                              if (q.isEmpty)
                                return const Iterable<InventoryItem>.empty();
                              return items.where((it) {
                                final desc = it.description.toLowerCase();
                                final brand = (it.brand ?? '').toLowerCase();
                                final barcode =
                                    (it.barcode ?? '').toLowerCase();
                                return desc.contains(q) ||
                                    brand.contains(q) ||
                                    barcode.contains(q);
                              }).take(20);
                            },
                            displayStringForOption: (it) => it.description,
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmit) {
                              controller.text = selectedCtrl.text;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                style: GoogleFonts.assistant(),
                                decoration: InputDecoration(
                                  labelText: _trOrLocale(
                                    context,
                                    l10n,
                                    'refillStockSelectItem',
                                    en: 'Select item',
                                    he: 'בחר פריט',
                                    ar: 'اختر عنصرًا',
                                  ),
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: AppTheme.surfaceContainerLow,
                                ),
                                onChanged: (_) {
                                  setLocal(() {
                                    selected = null;
                                    selectedCtrl.text = controller.text;
                                  });
                                },
                              );
                            },
                            onSelected: (it) {
                              setLocal(() {
                                selected = it;
                                selectedCtrl.text = it.description;
                              });
                            },
                            optionsViewBuilder: (context, onSelected, opts) {
                              return Align(
                                alignment: AlignmentDirectional.topStart,
                                child: Material(
                                  color: AppTheme.surfaceContainerLowest,
                                  elevation: 8,
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: 360,
                                      maxWidth:
                                          (mq.width - 40).clamp(340.0, 680.0),
                                    ),
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      shrinkWrap: true,
                                      itemCount: opts.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: AppTheme.outlineVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                      itemBuilder: (context, i) {
                                        final it = opts.elementAt(i);
                                        final hasPhoto = it.imageUrl != null &&
                                            it.imageUrl!.trim().isNotEmpty;
                                        return ListTile(
                                          dense: true,
                                          leading: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Container(
                                              width: 46,
                                              height: 46,
                                              color: AppTheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.45),
                                              child: hasPhoto
                                                  ? CachedNetworkImage(
                                                      imageUrl: it.imageUrl!,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Icon(
                                                      Icons.image_outlined,
                                                      color: AppTheme
                                                          .outlineVariant,
                                                      size: 22,
                                                    ),
                                            ),
                                          ),
                                          title: Text(
                                            it.description,
                                            style: GoogleFonts.assistant(
                                                fontWeight: FontWeight.w700),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '${_trOrLocale(context, l10n, 'availableStock', en: 'In stock', he: 'מלאי זמין', ar: 'متوفر')}: ${it.availableStock}',
                                            style: GoogleFonts.assistant(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.onSurfaceVariant),
                                          ),
                                          onTap: () => onSelected(it),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: amountCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.assistant(),
                                  decoration: InputDecoration(
                                    labelText: _trOrLocale(
                                      context,
                                      l10n,
                                      'refillStockAmount',
                                      en: 'Add units',
                                      he: 'הוסף יחידות',
                                      ar: 'أضف وحدات',
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.surfaceContainerLow,
                                  ),
                                  onChanged: (_) => setLocal(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (selected != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondaryContainer
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.secondary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    '+${int.tryParse(amountCtrl.text.trim()) ?? 0}',
                                    style: GoogleFonts.assistant(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.secondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(_trOrLocale(
                                  context,
                                  l10n,
                                  'cancel',
                                  en: 'Cancel',
                                  he: 'ביטול',
                                  ar: 'إلغاء',
                                )),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: enable
                                    ? () => Navigator.pop(ctx, true)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.secondary,
                                  foregroundColor: AppTheme.onSecondary,
                                  disabledBackgroundColor: AppTheme.secondary
                                      .withValues(alpha: 0.35),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _trOrLocale(
                                    context,
                                    l10n,
                                    'refillStockConfirm',
                                    en: 'Add to stock',
                                    he: 'הוסף למלאי',
                                    ar: 'إضافة للمخزون',
                                  ),
                                  style: GoogleFonts.assistant(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );

      if (ok != true || !mounted || selected == null) return;
      final add = int.tryParse(amountCtrl.text.trim()) ?? 0;
      if (add <= 0) return;
      await ref.read(inventoryServiceProvider).update(
        selected!.id,
        {'available_stock': selected!.availableStock + add},
      );
      ref.invalidate(inventoryItemsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(l10n?.tr('success') ?? 'Success'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      amountCtrl.dispose();
      selectedCtrl.dispose();
    }
  }

  Future<void> _openWhatsAppToPhone(String rawPhone, String message) async {
    final phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) return;
    await WhatsAppService.sendMessage(phone, message);
  }

  String _supplierStockOrderMessage(
    BuildContext context,
    AppLocalizations? l10n,
    Supplier supplier,
    List<({InventoryItem item, int qty})> lines,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final header = switch (lang) {
      'en' => 'Stock order request',
      'ar' => 'طلب تزويد مخزون',
      _ => 'בקשה להזמנת מלאי',
    };
    final intro = switch (lang) {
      'en' => 'Hello ${supplier.companyName}, please supply:',
      'ar' => 'مرحبًا ${supplier.companyName}، نرجو توفير:',
      _ => 'שלום ${supplier.companyName}, אשמח להזמין:',
    };
    final body = lines.map((l) {
      final code = (l.item.barcode ?? '').trim();
      final codePart = code.isNotEmpty ? '($code) ' : '';
      return '$codePart${l.item.description}\n×${l.qty}';
    }).join('\n\n');
    final outro = switch (lang) {
      'en' => 'Please confirm availability and ETA.',
      'ar' => 'يرجى تأكيد التوفر وموعد التسليم.',
      _ => 'נא לאשר זמינות וזמן אספקה.',
    };
    return '$header\n\n$intro\n\n$body\n\n$outro';
  }

  Future<void> _openOrderStockDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations? l10n,
    List<Supplier> suppliers,
    List<InventoryItem> items,
  ) async {
    Supplier? selectedSupplier;
    var filter = 'all'; // all | low | out
    final qtyByItemId = <String, TextEditingController>{};

    List<InventoryItem> itemsForSupplier() {
      final sid = selectedSupplier?.id;
      if (sid == null) return <InventoryItem>[];
      final list =
          items.where((i) => i.supplierId == sid).toList(growable: true);
      list.sort((a, b) =>
          a.description.toLowerCase().compareTo(b.description.toLowerCase()));
      return list;
    }

    TextEditingController qtyCtrl(String itemId) =>
        qtyByItemId.putIfAbsent(itemId, () => TextEditingController(text: '0'));

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final mq = MediaQuery.sizeOf(ctx);
          return Dialog(
            backgroundColor: AppTheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: AppTheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (mq.width - 24).clamp(380.0, 980.0),
                maxHeight: (mq.height * 0.9).clamp(460.0, 860.0),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: StatefulBuilder(
                  builder: (dialogContext, setLocal) {
                    const lowStockThreshold = 2;
                    var itemList = itemsForSupplier();
                    if (filter == 'out') {
                      itemList =
                          itemList.where((i) => i.availableStock == 0).toList();
                    } else if (filter == 'low') {
                      itemList = itemList
                          .where((i) => i.availableStock <= lowStockThreshold)
                          .toList();
                    }
                    itemList.sort((a, b) {
                      final aLow =
                          a.availableStock <= lowStockThreshold ? 0 : 1;
                      final bLow =
                          b.availableStock <= lowStockThreshold ? 0 : 1;
                      final c = aLow.compareTo(bLow);
                      if (c != 0) return c;
                      return a.description
                          .toLowerCase()
                          .compareTo(b.description.toLowerCase());
                    });
                    final selectedLines = <({InventoryItem item, int qty})>[];
                    for (final it in itemList) {
                      final qty = int.tryParse(qtyCtrl(it.id).text.trim()) ?? 0;
                      if (qty > 0) selectedLines.add((item: it, qty: qty));
                    }
                    final canSend = selectedSupplier != null &&
                        selectedSupplier!.phone != null &&
                        selectedSupplier!.phone!.trim().isNotEmpty &&
                        selectedLines.isNotEmpty;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryContainer
                                    .withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.local_shipping_rounded,
                                  color: AppTheme.secondary,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _trOrLocale(
                                  dialogContext,
                                  l10n,
                                  'orderStockTitle',
                                  en: 'Order stock from supplier',
                                  he: 'הזמנת מלאי מסוכן',
                                  ar: 'طلب مخزون من المورد',
                                ),
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n?.tr('close') ?? 'Close',
                              onPressed: () => Navigator.pop(ctx, false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return DropdownMenu<Supplier>(
                              width: constraints.maxWidth,
                              expandedInsets: EdgeInsets.zero,
                              enableFilter: true,
                              enableSearch: true,
                              menuHeight: 320,
                              leadingIcon: const Icon(Icons.storefront_rounded),
                              initialSelection: selectedSupplier,
                              onSelected: (s) =>
                                  setLocal(() => selectedSupplier = s),
                              menuStyle: appDropdownMenuStyle(),
                              inputDecorationTheme:
                                  appDropdownInputDecorationTheme().copyWith(
                                fillColor: AppTheme.surfaceContainerLow,
                              ),
                              textStyle: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onSurface,
                              ),
                              label: Text(
                                _trOrLocale(
                                  dialogContext,
                                  l10n,
                                  'orderStockSelectSupplier',
                                  en: 'Supplier',
                                  he: 'סוכן',
                                  ar: 'المورد',
                                ),
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              dropdownMenuEntries: suppliers.map((s) {
                                return DropdownMenuEntry<Supplier>(
                                  value: s,
                                  label: s.companyName,
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        if (selectedSupplier != null)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                selected: filter == 'all',
                                label: Text(
                                  _trOrLocale(
                                    dialogContext,
                                    l10n,
                                    'orderStockFilterAll',
                                    en: 'All',
                                    he: 'הכל',
                                    ar: 'الكل',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onSelected: (_) =>
                                    setLocal(() => filter = 'all'),
                              ),
                              ChoiceChip(
                                selected: filter == 'low',
                                label: Text(
                                  _trOrLocale(
                                    dialogContext,
                                    l10n,
                                    'orderStockFilterLow',
                                    en: 'Low stock',
                                    he: 'מלאי נמוך',
                                    ar: 'مخزون منخفض',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onSelected: (_) =>
                                    setLocal(() => filter = 'low'),
                              ),
                              ChoiceChip(
                                selected: filter == 'out',
                                label: Text(
                                  _trOrLocale(
                                    dialogContext,
                                    l10n,
                                    'orderStockFilterOut',
                                    en: 'Out of stock',
                                    he: 'חסר במלאי',
                                    ar: 'نفد المخزون',
                                  ),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onSelected: (_) =>
                                    setLocal(() => filter = 'out'),
                              ),
                            ],
                          ),
                        if (selectedSupplier != null)
                          const SizedBox(height: 12),
                        Expanded(
                          child: selectedSupplier == null
                              ? Center(
                                  child: Text(
                                    _trOrLocale(
                                      dialogContext,
                                      l10n,
                                      'orderStockPickSupplierHint',
                                      en: 'Select a supplier to see its items.',
                                      he: 'בחר סוכן כדי לראות את הפריטים שלו.',
                                      ar: 'اختر موردًا لعرض عناصره.',
                                    ),
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : (itemList.isEmpty
                                  ? Center(
                                      child: Text(
                                        _trOrLocale(
                                          dialogContext,
                                          l10n,
                                          'orderStockNoItemsForSupplier',
                                          en: 'No inventory items are linked to this supplier.',
                                          he: 'אין פריטי מלאי שמשויכים לסוכן הזה.',
                                          ar: 'لا توجد عناصر مخزون مرتبطة بهذا المورد.',
                                        ),
                                        style: GoogleFonts.assistant(
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, c) {
                                        final cols = c.maxWidth >= 860 ? 2 : 1;
                                        return GridView.builder(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: cols,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                            childAspectRatio:
                                                cols == 1 ? 3.6 : 3.2,
                                          ),
                                          itemCount: itemList.length,
                                          itemBuilder: (context, i) {
                                            final it = itemList[i];
                                            final hasPhoto = it.imageUrl !=
                                                    null &&
                                                it.imageUrl!.trim().isNotEmpty;
                                            final ctrl = qtyCtrl(it.id);
                                            final stock = it.availableStock;
                                            final stockColor = stock == 0
                                                ? AppTheme.error
                                                : (stock <= lowStockThreshold
                                                    ? AppTheme.warning
                                                    : AppTheme
                                                        .onSurfaceVariant);
                                            final stockBg = stock == 0
                                                ? AppTheme.error
                                                    .withValues(alpha: 0.08)
                                                : (stock <= lowStockThreshold
                                                    ? AppTheme.warning
                                                        .withValues(alpha: 0.10)
                                                    : AppTheme
                                                        .surfaceContainerHighest
                                                        .withValues(
                                                            alpha: 0.45));

                                            return DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: AppTheme
                                                    .surfaceContainerLow,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: AppTheme.outlineVariant
                                                      .withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Row(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      child: Container(
                                                        width: 64,
                                                        height: 64,
                                                        color: AppTheme
                                                            .surfaceContainerHighest
                                                            .withValues(
                                                                alpha: 0.45),
                                                        child: hasPhoto
                                                            ? CachedNetworkImage(
                                                                imageUrl: it
                                                                    .imageUrl!,
                                                                fit: BoxFit
                                                                    .cover,
                                                              )
                                                            : Icon(
                                                                Icons
                                                                    .image_outlined,
                                                                color: AppTheme
                                                                    .outlineVariant,
                                                                size: 22,
                                                              ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  it.description,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: GoogleFonts
                                                                      .assistant(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 6,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color:
                                                                      stockBg,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              999),
                                                                  border: Border
                                                                      .all(
                                                                    color: stockColor
                                                                        .withValues(
                                                                            alpha:
                                                                                0.28),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '${_trOrLocale(dialogContext, l10n, 'availableStock', en: 'In stock', he: 'מלאי זמין', ar: 'متوفر')}: $stock',
                                                                  style: GoogleFonts
                                                                      .assistant(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    fontSize:
                                                                        11.5,
                                                                    color:
                                                                        stockColor,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 6),
                                                          Text(
                                                            [
                                                              if ((it.barcode ??
                                                                      '')
                                                                  .trim()
                                                                  .isNotEmpty)
                                                                '${_trOrLocale(dialogContext, l10n, 'barcode', en: 'Barcode', he: 'ברקוד', ar: 'باركוד')}: ${it.barcode}',
                                                            ].join(' · '),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
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
                                                    const SizedBox(width: 12),
                                                    SizedBox(
                                                      width: 96,
                                                      child: TextField(
                                                        controller: ctrl,
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        style: GoogleFonts
                                                            .assistant(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                        decoration:
                                                            InputDecoration(
                                                          labelText:
                                                              _trOrLocale(
                                                            dialogContext,
                                                            l10n,
                                                            'quantity',
                                                            en: 'Qty',
                                                            he: 'כמות',
                                                            ar: 'الكمية',
                                                          ),
                                                          filled: true,
                                                          fillColor:
                                                              Colors.white,
                                                        ),
                                                        onChanged: (_) =>
                                                            setLocal(() {}),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    )),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(_trOrLocale(
                                dialogContext,
                                l10n,
                                'cancel',
                                en: 'Cancel',
                                he: 'ביטול',
                                ar: 'إلغاء',
                              )),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: canSend
                                  ? () => Navigator.pop(ctx, true)
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.secondary,
                                foregroundColor: AppTheme.onSecondary,
                                disabledBackgroundColor:
                                    AppTheme.secondary.withValues(alpha: 0.35),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _trOrLocale(
                                  dialogContext,
                                  l10n,
                                  'orderStockSend',
                                  en: 'Send to supplier',
                                  he: 'שלח לסוכן',
                                  ar: 'إرسال للمورد',
                                ),
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      if (ok != true || !mounted || selectedSupplier == null) return;

      final supplier = selectedSupplier!;
      final phone = (supplier.phone ?? '').trim();
      if (phone.isEmpty) return;

      final itemList = itemsForSupplier();
      final lines = <({InventoryItem item, int qty})>[];
      for (final it in itemList) {
        final qty = int.tryParse(qtyCtrl(it.id).text.trim()) ?? 0;
        if (qty > 0) lines.add((item: it, qty: qty));
      }
      if (lines.isEmpty) return;

      final message =
          _supplierStockOrderMessage(this.context, l10n, supplier, lines);
      await _openWhatsAppToPhone(phone, message);
    } finally {
      for (final c in qtyByItemId.values) {
        c.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final suppliersAsync = ref.watch(suppliersProvider);

    final itemsForRefill = itemsAsync.value ?? const <InventoryItem>[];
    final suppliersForOrder = suppliersAsync.value ?? const <Supplier>[];

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTheme.surfaceContainerLowest,
      ),
      floatingActionButton: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSlide(
              offset: _fabExpanded ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _fabExpanded ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_fabExpanded,
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'inv_order_fab',
                    backgroundColor: AppTheme.surfaceContainerLowest,
                    foregroundColor: AppTheme.secondary,
                    elevation: 3,
                    onPressed: () async {
                      _closeFab();
                      await _openOrderStockDialog(
                        context,
                        ref,
                        l10n,
                        suppliersForOrder,
                        itemsForRefill,
                      );
                    },
                    tooltip: _trOrLocale(
                      context,
                      l10n,
                      'orderStock',
                      en: 'Order stock',
                      he: 'הזמנת מלאי',
                      ar: 'طلب مخزون',
                    ),
                    child: const Icon(Icons.shopping_cart_checkout_rounded,
                        size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSlide(
              offset: _fabExpanded ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _fabExpanded ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_fabExpanded,
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'inv_refill_fab',
                    backgroundColor: AppTheme.surfaceContainerLowest,
                    foregroundColor: AppTheme.secondary,
                    elevation: 3,
                    onPressed: () async {
                      _closeFab();
                      await _openRefillStockDialog(
                        context,
                        ref,
                        l10n,
                        itemsForRefill,
                      );
                    },
                    tooltip: _trOrLocale(
                      context,
                      l10n,
                      'refillStock',
                      en: 'Refill stock',
                      he: 'מילוי מלאי',
                      ar: 'تعبئة المخزون',
                    ),
                    child: const Icon(Icons.playlist_add_rounded, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSlide(
              offset: _fabExpanded ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _fabExpanded ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_fabExpanded,
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'inv_new_item_fab',
                    backgroundColor: AppTheme.surfaceContainerLowest,
                    foregroundColor: AppTheme.secondary,
                    elevation: 3,
                    onPressed: () {
                      _closeFab();
                      _openItemDialog(context, ref, l10n);
                    },
                    tooltip: l10n?.tr('newItem') ?? 'New Item',
                    child: const Icon(Icons.add_box_rounded, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'inv_add_fab',
              backgroundColor: AppTheme.secondary,
              foregroundColor: AppTheme.onPrimary,
              elevation: 2,
              onPressed: _toggleFab,
              tooltip: l10n?.tr('newItem') ?? 'New Item',
              child: AnimatedRotation(
                turns: _fabExpanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ],
        ),
      ),
      body: itemsAsync.when(
        data: (items) {
          final suppliersById = <String, String>{
            for (final s in (suppliersAsync.value ?? const []))
              s.id: s.companyName,
          };

          final q = _searchCtrl.text.trim().toLowerCase();
          final filtered = items.where((i) {
            if (q.isEmpty) return true;
            final desc = i.description.toLowerCase();
            final brand = (i.brand ?? '').toLowerCase();
            final barcode = (i.barcode ?? '').toLowerCase();
            return desc.contains(q) || brand.contains(q) || barcode.contains(q);
          }).toList();

          return SupplierNameCache(
            suppliersById: suppliersById,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EditorialScreenTitle(
                        title: _trOrLocale(
                          context,
                          l10n,
                          'inventory',
                          en: 'Inventory',
                          he: 'מלאי',
                          ar: 'المخزون',
                        ),
                        padding: const EdgeInsets.only(
                          left: 32,
                          right: 32,
                          top: 28,
                          bottom: 6,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                        child: Material(
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              floatingLabelAlignment:
                                  FloatingLabelAlignment.start,
                              labelText: _searchHint(),
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
                              suffixIcon: IconButton(
                                tooltip: _trOrLocale(
                                  context,
                                  l10n,
                                  'scanBarcode',
                                  en: 'Scan barcode',
                                  he: 'סריקת ברקוד',
                                  ar: 'مسح الباركود',
                                ),
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                color: AppTheme.secondary,
                                onPressed: () async {
                                  final code =
                                      await BarcodeScanDialog.show(context);
                                  if (!mounted || code == null) return;
                                  _searchCtrl.text = code;
                                  setState(() {});
                                },
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceContainerLowest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: AppTheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                  color: AppTheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: AppTheme.secondary,
                                  width: 1.6,
                                ),
                              ),
                              contentPadding: const EdgeInsets.fromLTRB(
                                8,
                                14,
                                12,
                                14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: AppTheme.outline.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.tr('noData') ?? 'No Data',
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurfaceVariant,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final cols = _gridCols(constraints.crossAxisExtent);
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            // Slightly taller cells so two-column details + price row fit on iPad without overflow.
                            childAspectRatio: 0.84,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = filtered[index];
                              return StaggeredFadeIn(
                                index: index,
                                stepMilliseconds: 55,
                                child: _InventoryItemCard(
                                  item: item,
                                  l10n: l10n,
                                  onTap: () => _openItemDialog(
                                    context,
                                    ref,
                                    l10n,
                                    existing: item,
                                  ),
                                ),
                              );
                            },
                            childCount: filtered.length,
                          ),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
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
            style: const TextStyle(color: AppTheme.error),
          ),
        ),
      ),
    );
  }
}

class _InventoryItemCard extends StatelessWidget {
  final InventoryItem item;
  final AppLocalizations? l10n;
  final VoidCallback onTap;

  const _InventoryItemCard({
    required this.item,
    required this.l10n,
    required this.onTap,
  });

  String _trOrLocale(BuildContext context, String key,
      {required String en, required String he, required String ar}) {
    final t = l10n?.tr(key) ?? '';
    if (t.isNotEmpty && t != key) return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'he' => he,
      'ar' => ar,
      _ => en,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = item.imageUrl != null && item.imageUrl!.trim().isNotEmpty;
    final fallbackBannerColor = AppTheme.secondary;
    final suppliers = SupplierNameCache.of(context)?.suppliersById;

    final stockLabel = _trOrLocale(
      context,
      'availableStock',
      en: 'In stock',
      he: 'מלאי זמין',
      ar: 'متوفر',
    );

    final int warrantyYears = item.warrantyYears;
    final String? warrantyLabel = warrantyYears == 3
        ? _trOrLocale(
            context,
            'warranty3Years',
            en: '3 years',
            he: '3 שנים',
            ar: '3 سنوات',
          )
        : (warrantyYears == 5
            ? _trOrLocale(
                context,
                'warranty5Years',
                en: '5 years',
                he: '5 שנים',
                ar: '5 سنوات',
              )
            : null);

    final warrantyPrefix = _trOrLocale(
      context,
      'warranty',
      en: 'Warranty',
      he: 'אחריות',
      ar: 'الضمان',
    );

    final supplierName = (item.supplierId != null && suppliers != null)
        ? suppliers[item.supplierId!]
        : null;
    final brand = (item.brand ?? '').trim();
    final barcode = (item.barcode ?? '').trim();
    final weightedLabel = _trOrLocale(
      context,
      'weightedItem',
      en: 'Weighted item',
      he: 'פריט שקיל',
      ar: 'عنصر وزني',
    );
    final vatLabel = _trOrLocale(
      context,
      'vatExemptItem',
      en: 'VAT exempt',
      he: 'ללא מע״מ',
      ar: 'معفى من الضريبة',
    );

    String yesNo(bool v) {
      return switch (Localizations.localeOf(context).languageCode) {
        'ar' => v ? 'نعم' : 'لا',
        'en' => v ? 'Yes' : 'No',
        _ => v ? 'כן' : 'לא',
      };
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.12),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(26, 28, 28, 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 128,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    hasPhoto
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: fallbackBannerColor),
                            errorWidget: (_, __, ___) =>
                                Container(color: fallbackBannerColor),
                          )
                        : Container(color: fallbackBannerColor),
                    Container(
                      color: Colors.black.withValues(alpha: 0.14),
                    ),
                    if (warrantyLabel != null)
                      PositionedDirectional(
                        top: 10,
                        start: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerLowest
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            '$warrantyPrefix · $warrantyLabel',
                            style: GoogleFonts.assistant(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      bottom: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest
                              .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          '$stockLabel · ${item.availableStock}',
                          style: GoogleFonts.assistant(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.assistant(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onSurface,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (supplierName != null &&
                                    supplierName.trim().isNotEmpty)
                                  _detailRow(
                                    context,
                                    label: _trOrLocale(
                                      context,
                                      'supplier',
                                      en: 'Supplier',
                                      he: 'סוכן',
                                      ar: 'مورد',
                                    ),
                                    value: supplierName,
                                  ),
                                if (brand.isNotEmpty)
                                  _detailRow(
                                    context,
                                    label: _trOrLocale(
                                      context,
                                      'brand',
                                      en: 'Brand',
                                      he: 'חברה / מותג',
                                      ar: 'شركة / ماركة',
                                    ),
                                    value: brand,
                                  ),
                                if (barcode.isNotEmpty)
                                  _detailRow(
                                    context,
                                    label: _trOrLocale(
                                      context,
                                      'barcode',
                                      en: 'Barcode',
                                      he: 'ברקוד',
                                      ar: 'باركود',
                                    ),
                                    value: barcode,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _detailRow(
                                  context,
                                  label: _trOrLocale(
                                    context,
                                    'availableStock',
                                    en: 'Available stock',
                                    he: 'מלאי זמין',
                                    ar: 'المخزون المتاح',
                                  ),
                                  value: item.availableStock.toString(),
                                  valueColor: item.availableStock < 3
                                      ? AppTheme.error
                                      : AppTheme.success,
                                  valueAsPill: true,
                                ),
                                _detailRow(
                                  context,
                                  label: weightedLabel,
                                  value: yesNo(item.isWeighted),
                                ),
                                _detailRow(
                                  context,
                                  label: vatLabel,
                                  value: yesNo(item.isVatExempt),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Divider(
                        height: 1,
                        color: AppTheme.outlineVariant.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.consumerPrice == null
                                ? '-'
                                : '₪${item.consumerPrice!.toStringAsFixed(2)}',
                            style: GoogleFonts.assistant(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              if (item.isWeighted)
                                _chip(
                                  context,
                                  label: _trOrLocale(
                                    context,
                                    'weightedItem',
                                    en: 'Weighted',
                                    he: 'שקיל',
                                    ar: 'وزني',
                                  ),
                                ),
                              if (item.isVatExempt)
                                _chip(
                                  context,
                                  label: _trOrLocale(
                                    context,
                                    'vatExemptItem',
                                    en: 'No VAT',
                                    he: 'ללא מע״מ',
                                    ar: 'بدون ضريبة',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, {required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.secondary.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.assistant(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.secondary,
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
    bool valueAsPill = false,
  }) {
    final labelStyle = GoogleFonts.assistant(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.onSurfaceVariant,
    );
    final valueStyle = GoogleFonts.assistant(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: valueColor ?? AppTheme.onSurface,
    );

    Widget valueWidget = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: valueStyle,
      textAlign: TextAlign.start,
    );

    if (valueAsPill && valueColor != null) {
      valueWidget = Container(
        constraints: const BoxConstraints(minHeight: 24, maxHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: valueColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: valueColor.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 24,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 62),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '$label:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: valueWidget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryItemDialog extends StatefulWidget {
  final WidgetRef ref;
  final AppLocalizations? l10n;
  final InventoryItem? existingItem;

  const InventoryItemDialog({
    super.key,
    required this.ref,
    required this.l10n,
    this.existingItem,
  });

  @override
  State<InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends State<InventoryItemDialog> {
  final _descCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _autoRestockThresholdCtrl = TextEditingController();
  final _autoRestockQuantityCtrl = TextEditingController();

  Uint8List? _pickedImageBytes;
  bool _deleteExistingPhoto = false;
  bool _isWeighted = false;
  bool _isVatExempt = false;
  int _warrantyYears = 0;
  String? _supplierId;
  bool _autoRestockEnabled = false;
  bool _saving = false;

  String _trOrLocale(
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

  @override
  void initState() {
    super.initState();
    final e = widget.existingItem;
    if (e != null) {
      _descCtrl.text = e.description;
      _brandCtrl.text = e.brand ?? '';
      _barcodeCtrl.text = e.barcode ?? '';
      _priceCtrl.text = e.consumerPrice?.toStringAsFixed(2) ?? '';
      _stockCtrl.text = e.availableStock.toString();
      _isWeighted = e.isWeighted;
      _isVatExempt = e.isVatExempt;
      _supplierId = e.supplierId;
      _warrantyYears = e.warrantyYears;
      _autoRestockEnabled = e.autoRestockEnabled;
      _autoRestockThresholdCtrl.text = e.autoRestockThreshold.toString();
      _autoRestockQuantityCtrl.text = e.autoRestockQuantity.toString();
    } else {
      _autoRestockThresholdCtrl.text = '0';
      _autoRestockQuantityCtrl.text = '1';
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _brandCtrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _autoRestockThresholdCtrl.dispose();
    _autoRestockQuantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _showPhotoPicker() async {
    final l10n = widget.l10n;
    final hasExisting =
        widget.existingItem?.imageUrl != null && !_deleteExistingPhoto;
    final hasPicked = _pickedImageBytes != null;

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          _trOrLocale(
            context,
            l10n,
            'selectImageSource',
            en: 'Select Image Source',
            he: 'בחר מקור תמונה',
            ar: 'اختر مصدر الصورة',
          ),
          style: GoogleFonts.assistant(fontWeight: FontWeight.bold),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    _trOrLocale(
                      context,
                      l10n,
                      'camera',
                      en: 'Camera',
                      he: 'מצלמה',
                      ar: 'الكاميرا',
                    ),
                    style: GoogleFonts.assistant(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    _trOrLocale(
                      context,
                      l10n,
                      'gallery',
                      en: 'Gallery',
                      he: 'גלריה',
                      ar: 'المعرض',
                    ),
                    style: GoogleFonts.assistant(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          if (hasExisting || hasPicked)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _pickedImageBytes = null;
                  _deleteExistingPhoto = true;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppTheme.error),
                    const SizedBox(width: 12),
                    Text(
                      _trOrLocale(
                        context,
                        l10n,
                        'deletePhoto',
                        en: 'Delete Photo',
                        he: 'מחק תמונה',
                        ar: 'حذف الصورة',
                      ),
                      style: GoogleFonts.assistant(
                        fontSize: 16,
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (source != null) {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (xFile == null || !mounted) return;
      final bytes = await xFile.readAsBytes();
      if (mounted) {
        setState(() {
          _pickedImageBytes = bytes;
          _deleteExistingPhoto = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final l10n = widget.l10n;
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.tr('error') ?? 'Error')),
      );
      return;
    }
    if (_supplierId == null || _supplierId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(
              context,
              l10n,
              'pleaseSelectSupplier',
              en: 'Please select a supplier',
              he: 'נא לבחור סוכן',
              ar: 'يرجى اختيار مورد',
            ),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    int parseStock(String raw) {
      final v = int.tryParse(raw.trim());
      return v == null ? 0 : v.clamp(0, 1 << 30);
    }

    int parsePositiveInt(String raw, {required int fallback}) {
      final v = int.tryParse(raw.trim());
      if (v == null) return fallback;
      return v.clamp(0, 1 << 30);
    }

    double? parsePrice(String raw) {
      final t = raw.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    String cacheBustedUrl(String url) {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      try {
        final uri = Uri.parse(url);
        final qp = Map<String, String>.from(uri.queryParameters);
        qp['v'] = ts;
        return uri.replace(queryParameters: qp).toString();
      } catch (_) {
        return '$url?v=$ts';
      }
    }

    setState(() => _saving = true);
    try {
      final stock = parseStock(_stockCtrl.text);
      final price = parsePrice(_priceCtrl.text);
      final autoThreshold = parsePositiveInt(
        _autoRestockThresholdCtrl.text,
        fallback: 0,
      );
      final autoQty =
          parsePositiveInt(_autoRestockQuantityCtrl.text, fallback: 1)
              .clamp(1, 1 << 30);

      if (_autoRestockEnabled && autoThreshold <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.error,
            content: Text(
              _trOrLocale(
                context,
                l10n,
                'autoRestockThresholdError',
                en: 'Set a low-stock threshold greater than 0.',
                he: 'יש להגדיר סף מלאי נמוך גדול מ-0.',
                ar: 'يرجى تعيين حد مخزون منخفض أكبر من 0.',
              ),
            ),
          ),
        );
        return;
      }

      if (widget.existingItem == null) {
        var created = await widget.ref.read(inventoryServiceProvider).create(
              InventoryItem(
                id: '',
                description: desc,
                supplierId: _supplierId,
                brand: _brandCtrl.text.trim().isEmpty
                    ? null
                    : _brandCtrl.text.trim(),
                barcode: _barcodeCtrl.text.trim().isEmpty
                    ? null
                    : _barcodeCtrl.text.trim(),
                consumerPrice: price,
                availableStock: stock,
                isWeighted: _isWeighted,
                isVatExempt: _isVatExempt,
                warrantyYears: _warrantyYears,
                autoRestockEnabled: _autoRestockEnabled,
                autoRestockThreshold: autoThreshold,
                autoRestockQuantity: autoQty,
              ),
            );

        if (_pickedImageBytes != null) {
          try {
            final url = await widget.ref
                .read(inventoryServiceProvider)
                .uploadPhoto(created.id, _pickedImageBytes!);
            final busted = cacheBustedUrl(url);
            created = created.copyWith(imageUrl: busted);
            await widget.ref
                .read(inventoryServiceProvider)
                .update(created.id, {'image_url': busted});
          } on StorageException catch (e) {
            if (!mounted) return;
            final msg = (e.message).toLowerCase();
            final looksLikeMissingBucket =
                msg.contains('bucket') && msg.contains('not found');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.error,
                content: Text(
                  looksLikeMissingBucket
                      ? _trOrLocale(
                          context,
                          l10n,
                          'inventoryPhotoBucketMissing',
                          en: 'Photo upload is not configured yet. Create the Supabase storage bucket "inventory-item-photos".',
                          he: 'העלאת תמונה עדיין לא מוגדרת. יש ליצור ב-Supabase את דלי האחסון "inventory-item-photos".',
                          ar: 'رفع الصورة غير مهيأ بعد. أنشئ سلة التخزين في Supabase باسم "inventory-item-photos".',
                        )
                      : '${l10n?.tr('error') ?? 'Error'}: ${e.message}',
                ),
              ),
            );
            // Keep the item (without photo) created; let the user fix bucket and edit later.
          }
        }
      } else {
        final id = widget.existingItem!.id;
        final updates = {
          'description': desc,
          'supplier_id': _supplierId,
          'brand':
              _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          'barcode': _barcodeCtrl.text.trim().isEmpty
              ? null
              : _barcodeCtrl.text.trim(),
          'consumer_price': price,
          'available_stock': stock,
          'is_weighted': _isWeighted,
          'is_vat_exempt': _isVatExempt,
          'warranty_years': _warrantyYears,
          'auto_restock_enabled': _autoRestockEnabled,
          'auto_restock_threshold': autoThreshold,
          'auto_restock_quantity': autoQty,
        };
        await widget.ref.read(inventoryServiceProvider).update(id, updates);

        if (_pickedImageBytes != null) {
          try {
            final url = await widget.ref
                .read(inventoryServiceProvider)
                .uploadPhoto(id, _pickedImageBytes!);
            final busted = cacheBustedUrl(url);
            await widget.ref
                .read(inventoryServiceProvider)
                .update(id, {'image_url': busted});
          } on StorageException catch (e) {
            if (!mounted) return;
            final msg = (e.message).toLowerCase();
            final looksLikeMissingBucket =
                msg.contains('bucket') && msg.contains('not found');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.error,
                content: Text(
                  looksLikeMissingBucket
                      ? _trOrLocale(
                          context,
                          l10n,
                          'inventoryPhotoBucketMissing',
                          en: 'Photo upload is not configured yet. Create the Supabase storage bucket "inventory-item-photos".',
                          he: 'העלאת תמונה עדיין לא מוגדרת. יש ליצור ב-Supabase את דלי האחסון "inventory-item-photos".',
                          ar: 'رفع الصورة غير مهيأ بعد. أنشئ سلة التخزين في Supabase باسم "inventory-item-photos".',
                        )
                      : '${l10n?.tr('error') ?? 'Error'}: ${e.message}',
                ),
              ),
            );
          }
        } else if (_deleteExistingPhoto) {
          await widget.ref.read(inventoryServiceProvider).update(
            id,
            {'image_url': null},
          );
        }
      }

      widget.ref.invalidate(inventoryItemsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final e = widget.existingItem;
    if (e == null) return;

    final l10n = widget.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n?.tr('delete') ?? 'Delete',
          style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
        ),
        content: Text(
          _trOrLocale(
            context,
            l10n,
            'deleteItemConfirm',
            en: 'Delete "${e.description}"?',
            he: 'למחוק "${e.description}"?',
            ar: 'حذف "${e.description}"؟',
          ),
          style: GoogleFonts.assistant(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n?.tr('cancel') ?? 'Cancel',
              style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text(
              l10n?.tr('delete') ?? 'Delete',
              style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.ref.read(inventoryServiceProvider).delete(e.id);
      widget.ref.invalidate(inventoryItemsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $err'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEdit = widget.existingItem != null;
    final hasExistingPhoto =
        widget.existingItem?.imageUrl != null && !_deleteExistingPhoto;
    final suppliersAsync = widget.ref.watch(suppliersProvider);

    return Dialog(
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: AppLoadingOverlay(
        isLoading: _saving,
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit
                      ? _trOrLocale(
                          context,
                          l10n,
                          'editItem',
                          en: 'Edit item',
                          he: 'עריכת פריט',
                          ar: 'تعديل عنصر',
                        )
                      : _trOrLocale(
                          context,
                          l10n,
                          'newItem',
                          en: 'New item',
                          he: 'פריט חדש',
                          ar: 'عنصر جديد',
                        ),
                  style: GoogleFonts.assistant(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _saving ? null : _showPhotoPicker,
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: _pickedImageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _pickedImageBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          )
                        : (hasExistingPhoto
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: widget.existingItem!.imageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 32,
                                    color: AppTheme.outline,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n?.tr('image') ?? 'Add photo',
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              )),
                  ),
                ),
                const SizedBox(height: 18),
                _buildField(
                  controller: _descCtrl,
                  label: _trOrLocale(
                    context,
                    l10n,
                    'itemDescription',
                    en: 'Item description',
                    he: 'תיאור פריט',
                    ar: 'وصف العنصر',
                  ),
                  icon: Icons.description_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                suppliersAsync.when(
                  data: (suppliers) {
                    String supplierLabel(Supplier s) {
                      final contact = s.contactName?.trim();
                      if (contact != null && contact.isNotEmpty) return contact;
                      return s.companyName;
                    }

                    final entries = suppliers
                        .map(
                          (s) => DropdownMenuEntry<String>(
                            value: s.id,
                            label: supplierLabel(s),
                          ),
                        )
                        .toList();

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return DropdownMenu<String>(
                          width: constraints.maxWidth,
                          initialSelection: _supplierId,
                          enabled: !_saving,
                          menuStyle: appDropdownMenuStyle(),
                          inputDecorationTheme:
                              appDropdownInputDecorationTheme()
                                  .copyWith(fillColor: Colors.white),
                          decorationBuilder: (context, controller) {
                            return animatedDropdownDecorationBuilder(
                              label: Text(
                                _trOrLocale(
                                  context,
                                  l10n,
                                  'supplier',
                                  en: 'Supplier',
                                  he: 'סוכן',
                                  ar: 'مورد',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              leadingIcon: dropdownLeadingSlot(
                                Icon(
                                  Icons.local_shipping_outlined,
                                  color: AppTheme.outline,
                                  size: 18,
                                ),
                              ),
                              iconSize: 18,
                            )(context, controller);
                          },
                          onSelected: (v) {
                            setState(() {
                              _supplierId = v;
                              if (v != null) {
                                final s = suppliers.firstWhere(
                                  (e) => e.id == v,
                                  orElse: () => suppliers.first,
                                );
                                _brandCtrl.text = s.companyName;
                              } else {
                                _brandCtrl.text = '';
                              }
                            });
                          },
                          dropdownMenuEntries: entries,
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (e, _) => Text(
                    '${l10n?.tr('error') ?? 'Error'}: $e',
                    style: GoogleFonts.assistant(color: AppTheme.error),
                  ),
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _brandCtrl,
                  label: _trOrLocale(
                    context,
                    l10n,
                    'brand',
                    en: 'Brand / company',
                    he: 'חברה / מותג',
                    ar: 'شركة / ماركة',
                  ),
                  icon: Icons.storefront_outlined,
                  readOnly: _supplierId != null && _supplierId!.isNotEmpty,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _barcodeCtrl,
                  label: _trOrLocale(
                    context,
                    l10n,
                    'barcode',
                    en: 'Barcode',
                    he: 'ברקוד',
                    ar: 'باركود',
                  ),
                  icon: Icons.qr_code_2_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final code = await BarcodeScanDialog.show(context);
                            if (!mounted || code == null) return;
                            setState(() => _barcodeCtrl.text = code);
                          },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(
                      _trOrLocale(
                        context,
                        l10n,
                        'scanBarcode',
                        en: 'Scan barcode',
                        he: 'סריקת ברקוד',
                        ar: 'مسح الباركود',
                      ),
                      style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.secondary,
                      side: BorderSide(
                        color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownMenu<int>(
                  key: ValueKey(
                      'inv_warranty_${_warrantyYears}_${Localizations.localeOf(context).languageCode}'),
                  initialSelection: _warrantyYears,
                  enabled: !_saving,
                  menuStyle: appDropdownMenuStyle(),
                  inputDecorationTheme: appDropdownInputDecorationTheme()
                      .copyWith(fillColor: Colors.white),
                  decorationBuilder: (context, controller) {
                    return animatedDropdownDecorationBuilder(
                      label: Text(
                        _trOrLocale(
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
                      leadingIcon: dropdownLeadingSlot(
                        Icon(
                          Icons.verified_outlined,
                          color: AppTheme.outline,
                          size: 18,
                        ),
                      ),
                      iconSize: 18,
                    )(context, controller);
                  },
                  onSelected: (v) => setState(() => _warrantyYears = v ?? 0),
                  dropdownMenuEntries: [
                    DropdownMenuEntry<int>(
                      value: 0,
                      label: _trOrLocale(
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
                      label: _trOrLocale(
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
                      label: _trOrLocale(
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        controller: _priceCtrl,
                        label: _trOrLocale(
                          context,
                          l10n,
                          'consumerPrice',
                          en: 'Consumer price',
                          he: 'מחיר לצרכן',
                          ar: 'سعر للمستهلك',
                        ),
                        icon: Icons.sell_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        controller: _stockCtrl,
                        label: _trOrLocale(
                          context,
                          l10n,
                          'availableStock',
                          en: 'Available stock',
                          he: 'מלאי זמין',
                          ar: 'المخزون المتاح',
                        ),
                        icon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerHighest
                        .withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        value: _autoRestockEnabled,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _autoRestockEnabled = v),
                        title: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'autoRestockEnabled',
                            en: 'Auto restock',
                            he: 'הזמנה אוטומטית',
                            ar: 'إعادة طلب تلقائية',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'autoRestockSubtitle',
                            en: 'When stock is low, create a restock order automatically.',
                            he: 'כשמלאי נמוך, נוצרת הזמנת חידוש מלאי אוטומטית.',
                            ar: 'عند انخفاض المخزون، يتم إنشاء طلب إعادة تزويد تلقائيًا.',
                          ),
                          style: GoogleFonts.assistant(
                            color: AppTheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_autoRestockEnabled) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _autoRestockThresholdCtrl,
                                label: _trOrLocale(
                                  context,
                                  l10n,
                                  'autoRestockThreshold',
                                  en: 'Low-stock threshold',
                                  he: 'סף מלאי נמוך',
                                  ar: 'حد المخزون المنخفض',
                                ),
                                icon: Icons.warning_amber_rounded,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildField(
                                controller: _autoRestockQuantityCtrl,
                                label: _trOrLocale(
                                  context,
                                  l10n,
                                  'autoRestockQuantity',
                                  en: 'Auto restock qty',
                                  he: 'כמות להזמנה',
                                  ar: 'كمية إعادة الطلب',
                                ),
                                icon: Icons.add_shopping_cart_rounded,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile.adaptive(
                        value: _isWeighted,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _isWeighted = v),
                        title: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'weightedItem',
                            en: 'Weighted item',
                            he: 'פריט שקיל',
                            ar: 'عنصر وزني',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile.adaptive(
                        value: _isVatExempt,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _isVatExempt = v),
                        title: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'vatExemptItem',
                            en: 'VAT exempt',
                            he: 'ללא מע״מ',
                            ar: 'معفى من الضريبة',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isEdit)
                      TextButton(
                        onPressed: _saving ? null : _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          l10n?.tr('delete') ?? 'Delete',
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (isEdit) const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        l10n?.tr('cancel') ?? 'Cancel',
                        style:
                            GoogleFonts.assistant(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n?.tr('save') ?? 'Save',
                        style:
                            GoogleFonts.assistant(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: TextField(
        controller: controller,
        enabled: !_saving,
        readOnly: readOnly,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: GoogleFonts.assistant(fontSize: 14, color: AppTheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: AppTheme.onSurfaceVariant,
            fontSize: 13,
          ),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.outline),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: AppTheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: AppTheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: AppTheme.secondary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// Small helper so cards can show supplier names without ref access.
class SupplierNameCache extends InheritedWidget {
  final Map<String, String> suppliersById;

  const SupplierNameCache({
    super.key,
    required this.suppliersById,
    required super.child,
  });

  static SupplierNameCache? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SupplierNameCache>();
  }

  @override
  bool updateShouldNotify(SupplierNameCache oldWidget) =>
      suppliersById != oldWidget.suppliersById;
}
