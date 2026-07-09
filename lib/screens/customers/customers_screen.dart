import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';
import '../../config/app_animations.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../providers/providers.dart';
import 'customer_detail_screen.dart';
import '../../widgets/editorial_screen_title.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../theme/order_status_colors.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  String _customersDebtSort = 'highToLow'; // highToLow | lowToHigh

  int _gridCols(double width) {
    // Aim: iPad 11" should fit 4 cards per row.
    // Keep max at 4 for consistent density.
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

  String _customersSearchFieldLabel() {
    final l10n = AppLocalizations.of(context);
    final t = l10n?.tr('searchCustomersHint');
    if (t != null && t.isNotEmpty && t != 'searchCustomersHint') return t;
    return switch (Localizations.localeOf(context).languageCode) {
      'ar' => 'بحث بالبطاقة أو الاسم أو الهاتف…',
      'en' => 'Search by card name, customer, phone…',
      _ => 'חיפוש לפי כרטיס, שם לקוח, טלפון…',
    };
  }

  /// When ARB is stale, [AppLocalizations.tr] returns the key — treat as missing.
  String _l10nOrLocale(
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customersAsync = ref.watch(customersProvider);
    final ordersAsync = ref.watch(ordersProvider);

    final Map<String, int> openOrdersMap = {};
    final Map<String, int> totalOrdersMap = {};
    final Map<String, OrderStatus> latestOpenStatusMap = {};
    final Map<String, DateTime> latestOpenStatusAtMap = {};

    if (ordersAsync.hasValue) {
      for (final o in ordersAsync.value!) {
        totalOrdersMap[o.customerId] = (totalOrdersMap[o.customerId] ?? 0) + 1;
        if (o.status != OrderStatus.delivered &&
            o.status != OrderStatus.canceled) {
          openOrdersMap[o.customerId] = (openOrdersMap[o.customerId] ?? 0) + 1;

          // Show the exact status: pick the most recently updated/created open order.
          final when = o.updatedAt ?? o.createdAt ?? DateTime(1970);
          final prev = latestOpenStatusAtMap[o.customerId];
          if (prev == null || when.isAfter(prev)) {
            latestOpenStatusAtMap[o.customerId] = when;
            latestOpenStatusMap[o.customerId] = o.status;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTheme.surfaceContainerLowest,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.onPrimary,
        elevation: 2,
        onPressed: () => _showCustomerDialog(context, ref, l10n),
        tooltip: l10n?.tr('newCustomer') ?? 'New Customer',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: customersAsync.when(
        data: (customers) {
          final q = _searchCtrl.text.trim().toLowerCase();
          var filtered = customers.where((c) {
            if (q.isEmpty) return true;
            return c.cardName.toLowerCase().contains(q) ||
                c.customerName.toLowerCase().contains(q) ||
                c.phones.any((p) => p.toLowerCase().contains(q));
          }).toList();

          // Sort by remaining debt (balance to pay).
          filtered.sort((a, b) {
            final ad = a.remainingDebt;
            final bd = b.remainingDebt;
            if (_customersDebtSort == 'lowToHigh') {
              return ad.compareTo(bd);
            }
            // Default: highToLow
            return bd.compareTo(ad);
          });

          return CustomScrollView(
            slivers: [
              // ─── Page Header ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorialScreenTitle(
                      title: l10n?.tr('customers') ?? 'Customers',
                      padding: const EdgeInsets.only(
                        left: 32,
                        right: 32,
                        top: 28,
                        bottom: 6,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final isTight = c.maxWidth < 760;
                          final searchField = Material(
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
                                labelText: _customersSearchFieldLabel(),
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
                          );

                          final sort = DropdownMenu<String>(
                            key: ValueKey(
                              '${Localizations.localeOf(context).languageCode}_$_customersDebtSort',
                            ),
                            initialSelection: _customersDebtSort,
                            width: isTight ? 240 : 260,
                            menuStyle: appDropdownMenuStyle(),
                            inputDecorationTheme:
                                appDropdownInputDecorationTheme().copyWith(
                              fillColor: Colors.white,
                            ),
                            decorationBuilder:
                                (context, MenuController controller) {
                              return animatedDropdownDecorationBuilder(
                                label: Text(
                                  _l10nOrLocale(
                                    context,
                                    l10n,
                                    'sortByDebt',
                                    en: 'Sort by debt',
                                    he: 'מיין לפי חוב',
                                    ar: 'ترتيب حسب الدين',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                iconSize: 18,
                              )(context, controller);
                            },
                            onSelected: (v) => setState(
                              () => _customersDebtSort =
                                  v ?? _customersDebtSort,
                            ),
                            dropdownMenuEntries: [
                              DropdownMenuEntry<String>(
                                value: 'lowToHigh',
                                label: _l10nOrLocale(
                                  context,
                                  l10n,
                                  'debtLowToHigh',
                                  en: 'Low to high',
                                  he: 'נמוך עד גבוה',
                                  ar: 'من الأقل إلى الأعلى',
                                ),
                              ),
                              DropdownMenuEntry<String>(
                                value: 'highToLow',
                                label: _l10nOrLocale(
                                  context,
                                  l10n,
                                  'debtHighToLow',
                                  en: 'High to low',
                                  he: 'גבוה עד נמוך',
                                  ar: 'من الأعلى إلى الأقل',
                                ),
                              ),
                            ],
                          );

                          final countPill = Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryContainer.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.outlineVariant.withValues(
                                  alpha: 0.14,
                                ),
                              ),
                            ),
                            child: Text(
                              'סה״כ לקוחות: ${customers.length}',
                              style: GoogleFonts.assistant(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.secondary,
                              ),
                            ),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                SizedBox(
                                  width: isTight ? c.maxWidth : c.maxWidth - 260 - 12 - 190,
                                  child: searchField,
                                ),
                                sort,
                                countPill,
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // ─── Customer Grid ─────────────────────────────────────
              if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
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
                      final width = constraints.crossAxisExtent;
                      final cols = _gridCols(width);
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          // Slightly shorter cards so 4-column layouts breathe.
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final customer = filtered[index];
                            return StaggeredFadeIn(
                              index: index,
                              stepMilliseconds: 55,
                              child: _CustomerCard(
                                customer: customer,
                                index: index,
                                openOrders: openOrdersMap[customer.id] ?? 0,
                                totalOrders: totalOrdersMap[customer.id] ?? 0,
                                latestOpenStatus:
                                    latestOpenStatusMap[customer.id],
                                l10n: l10n,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CustomerDetailScreen(
                                          customer: customer),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      );
                    },
                  ),
                ),
              // Bottom padding (clear FAB)
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            '${l10n?.tr('error') ?? 'Error'}: $e',
            style: const TextStyle(color: AppTheme.error),
          ),
        ),
      ),
    );
  }

  void _showCustomerDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations? l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => CustomerFormDialog(
        ref: ref,
        l10n: l10n,
        onCustomerSaved: (createdCustomer) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(customer: createdCustomer),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW CUSTOMER DIALOG — Clean, editorial style
// ─────────────────────────────────────────────────────────────────────────────
class CustomerFormDialog extends StatefulWidget {
  final WidgetRef ref;
  final AppLocalizations? l10n;
  final Customer? existingCustomer;
  final Function(Customer)? onCustomerSaved;

  const CustomerFormDialog({
    super.key,
    required this.ref,
    required this.l10n,
    this.existingCustomer,
    this.onCustomerSaved,
  });

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _cardNameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  Uint8List? _pickedImageBytes;
  bool _deleteExistingPhoto = false;
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
    if (widget.existingCustomer != null) {
      final c = widget.existingCustomer!;
      _cardNameCtrl.text = c.cardName;
      _nameCtrl.text = c.customerName;
      _phoneCtrl.text = c.phones.join(', ');
      _locationCtrl.text = c.location ?? '';
    }
  }

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _showPhotoPicker() async {
    final l10n = widget.l10n;
    final hasExisting =
        widget.existingCustomer?.imageUrl != null && !_deleteExistingPhoto;
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
    final cardName = _cardNameCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (cardName.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                widget.l10n?.tr('error') ?? 'Please fill required fields')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final username = widget.ref.read(currentUsernameProvider);
      final phones = _phoneCtrl.text
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (widget.existingCustomer == null) {
        // Create new
        final customer = Customer(
          id: '',
          cardName: cardName,
          customerName: name,
          phones: phones,
          location: _locationCtrl.text.trim(),
          notes: null,
          createdBy: username,
          updatedBy: username,
        );
        var created =
            await widget.ref.read(customerServiceProvider).create(customer);
        if (_pickedImageBytes != null) {
          final url = await widget.ref
              .read(customerServiceProvider)
              .uploadPhoto(created.id, _pickedImageBytes!);
          created = created.copyWith(imageUrl: url);
          await widget.ref
              .read(customerServiceProvider)
              .update(created.id, {'image_url': url, 'updated_by': username});
        }
        widget.ref.invalidate(customersProvider);
        if (mounted) {
          Navigator.of(context).pop();
          widget.onCustomerSaved?.call(created);
        }
      } else {
        // Update existing
        var customer = widget.existingCustomer!.copyWith(
          cardName: cardName,
          customerName: name,
          phones: phones,
          location: _locationCtrl.text.trim(),
          updatedBy: username,
        );
        final updates = {
          'card_name': customer.cardName,
          'customer_name': customer.customerName,
          'phones': customer.phones,
          'location': customer.location,
          'updated_by': username,
        };
        await widget.ref
            .read(customerServiceProvider)
            .update(customer.id, updates);

        if (_pickedImageBytes != null) {
          final url = await widget.ref
              .read(customerServiceProvider)
              .uploadPhoto(customer.id, _pickedImageBytes!);
          customer = customer.copyWith(imageUrl: url);
          await widget.ref
              .read(customerServiceProvider)
              .update(customer.id, {'image_url': url});
        } else if (_deleteExistingPhoto) {
          await widget.ref
              .read(customerServiceProvider)
              .deletePhoto(customer.id);
          customer = customer.copyWith(imageUrl: null);
          // deletePhoto already sets image_url to null in db
        }
        widget.ref.invalidate(customersProvider);
        if (mounted) {
          Navigator.of(context).pop();
          widget.onCustomerSaved?.call(customer);
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('23505') || msg.contains('duplicate key')) {
          msg = widget.l10n?.tr('customerExistsError') ??
              'A customer with this Card Name already exists.';
        } else {
          msg = '${widget.l10n?.tr('error') ?? 'Error'}: $e';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Dialog(
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existingCustomer == null
                    ? _trOrLocale(
                        context,
                        l10n,
                        'newCustomer',
                        en: 'New Customer',
                        he: 'לקוח חדש',
                        ar: 'عميل جديد',
                      )
                    : _trOrLocale(
                        context,
                        l10n,
                        'editCustomerDetails',
                        en: 'Edit details',
                        he: 'עריכת פרטים',
                        ar: 'تعديل البيانات',
                      ),
                style: GoogleFonts.assistant(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              // Photo picker
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
                  child: _pickedImageBytes == null
                      ? ((widget.existingCustomer?.imageUrl != null &&
                              !_deleteExistingPhoto)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: widget.existingCustomer!.imageUrl!,
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
                            ))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _pickedImageBytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.white, size: 20),
                                  onPressed: () {
                                    setState(() => _pickedImageBytes = null);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              _buildDialogField(
                controller: _cardNameCtrl,
                label: l10n?.tr('cardName') ?? 'Card Name',
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 14),
              _buildDialogField(
                controller: _nameCtrl,
                label: l10n?.tr('customerName') ?? 'Customer Name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 14),
              _buildDialogField(
                controller: _phoneCtrl,
                label: l10n?.tr('phones') ?? 'Phones',
                icon: Icons.phone_outlined,
                hint: 'Comma separated',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _buildDialogField(
                controller: _locationCtrl,
                label: l10n?.tr('location') ?? 'Location',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      l10n?.tr('cancel') ?? 'Cancel',
                      style: GoogleFonts.assistant(
                        color: AppTheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            l10n?.tr('save') ?? 'Save',
                            style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
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
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: GoogleFonts.assistant(fontSize: 14, color: AppTheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: AppTheme.onSurfaceVariant,
            fontSize: 13,
          ),
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.outline.withValues(alpha: 0.4)),
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

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOMER CARD — Matches Stitch "Customers (Final)" screen
// Large photo top, name + subtitle + status dot at bottom
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final int index;
  final int openOrders;
  final int totalOrders;
  final OrderStatus? latestOpenStatus;
  final AppLocalizations? l10n;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.customer,
    required this.index,
    required this.openOrders,
    required this.totalOrders,
    required this.latestOpenStatus,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final debt = customer.remainingDebt;
    final bool isUnpaid = debt > 0;
    final bool isOverpaid = debt < 0;
    final bool isZero = debt == 0;
    String trOrLocale(String key,
        {required String en, required String he, required String ar}) {
      final t = l10n?.tr(key) ?? '';
      if (t.isNotEmpty && t != key) return t;
      return switch (Localizations.localeOf(context).languageCode) {
        'he' => he,
        'ar' => ar,
        _ => en,
      };
    }

    final hasPhoto =
        customer.imageUrl != null && customer.imageUrl!.trim().isNotEmpty;
    // If there's no uploaded photo, use a consistent yellow banner.
    final fallbackBannerColor = AppTheme.secondary;

    final isOpen = openOrders > 0 && latestOpenStatus != null;
    final statusLabel = isOpen
        ? orderStatusLocalizedLabel(latestOpenStatus!, l10n)
        : switch (Localizations.localeOf(context).languageCode) {
            'ar' => 'لا توجد طلبات مفتوحة',
            'en' => 'No open orders',
            _ => 'אין הזמנות פתוחות',
          };
    final statusColor =
        isOpen ? orderStatusColor(latestOpenStatus!) : AppTheme.outline;

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
              // ── Top Banner & Avatar (tall color block into the card body) ──
              SizedBox(
                height: 108,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          height: 98,
                          width: double.infinity,
                          child: hasPhoto
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: customer.imageUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: fallbackBannerColor,
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: fallbackBannerColor,
                                      ),
                                    ),
                                    // Slight tint for consistent contrast.
                                    Container(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                    ),
                                  ],
                                )
                              : Container(color: fallbackBannerColor),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 36,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          shape: BoxShape.circle,
                        ),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surfaceContainerHighest,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildPhoto(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Badge & Card ID Row ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isUnpaid
                                    ? AppTheme.error.withValues(alpha: 0.12)
                                    : AppTheme.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isOverpaid
                                    ? trOrLocale(
                                        'balanceOverpaidLabel',
                                        en: 'Overpaid',
                                        he: 'עודף ששולם',
                                        ar: 'مدفوعات زائدة',
                                      )
                                    : (isZero
                                        ? trOrLocale(
                                            'paid',
                                            en: 'Paid',
                                            he: 'שולם',
                                            ar: 'مدفوع',
                                          )
                                        : trOrLocale(
                                            'unpaid',
                                            en: 'Need to pay',
                                            he: 'צריך לשלם',
                                            ar: 'بحاجة للدفع',
                                          )),
                                style: GoogleFonts.assistant(
                                  color: isUnpaid
                                      ? AppTheme.error
                                      : AppTheme.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                customer.cardName,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.assistant(
                                  color: AppTheme.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Name & Phone ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            customer.customerName,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.assistant(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            customer.phones.isNotEmpty
                                ? customer.phones.first
                                : '-',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.assistant(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Orders status ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$statusLabel • $openOrders / $totalOrders הזמנות פתוחות',
                                style: GoogleFonts.assistant(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── Divider + debt pinned to card bottom ──
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.15),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '₪',
                                  style: GoogleFonts.assistant(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isUnpaid
                                        ? AppTheme.error
                                        : (isOverpaid
                                            ? AppTheme.success
                                            : AppTheme.onSurface),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isOverpaid
                                      ? '+${(-debt).toStringAsFixed(2)}'
                                      : debt.toStringAsFixed(2),
                                  style: GoogleFonts.assistant(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isUnpaid
                                        ? AppTheme.error
                                        : (isOverpaid
                                            ? AppTheme.success
                                            : AppTheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                            Directionality(
                              textDirection: TextDirection.rtl,
                              child: Text(
                                isOverpaid
                                    ? (l10n?.tr('balanceOverpaidLabel') ??
                                        'עודף ששולם')
                                    : (l10n?.tr('remainingDebt') ??
                                        'יתרה לתשלום'),
                                textAlign: TextAlign.right,
                                style: GoogleFonts.assistant(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.onSurfaceVariant,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    if (customer.imageUrl != null && customer.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: customer.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _photoPlaceholder(),
        errorWidget: (_, __, ___) => _photoPlaceholder(),
      );
    }
    return _photoPlaceholder();
  }

  Widget _photoPlaceholder() {
    return Container(
      color: AppTheme.surfaceContainer,
      child: Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.secondary.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              customer.cardName.isNotEmpty
                  ? customer.cardName[0].toUpperCase()
                  : '?',
              style: GoogleFonts.assistant(
                color: AppTheme.secondary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
