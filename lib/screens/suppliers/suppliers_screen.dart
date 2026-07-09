import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_animations.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/supplier.dart';
import '../../providers/providers.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/editorial_screen_title.dart';

/// Singular "agent" label; Hebrew is fixed so stale ARB assets cannot show "ספק".
String _agentSingularLabel(BuildContext context, AppLocalizations? l10n) {
  if (Localizations.localeOf(context).languageCode == 'he') return 'סוכן';
  final t = l10n?.tr('supplier');
  if (t != null && t.isNotEmpty && t != 'supplier') return t;
  return 'Supplier';
}

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _searchCtrl = TextEditingController();

  int _gridCols(double width) {
    // Aim: iPad 11" should fit 4 cards per row.
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

  String _suppliersSearchFieldLabel() {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'he') {
      return 'חיפוש סוכנים לפי חברה, איש קשר, טלפון…';
    }
    final l10n = AppLocalizations.of(context);
    final t = l10n?.tr('searchSuppliersHint');
    if (t != null && t.isNotEmpty && t != 'searchSuppliersHint') return t;
    return switch (lang) {
      'ar' => 'ابحث بالشركة، جهة الاتصال، الهاتف…',
      _ => 'Search by company, contact, phone…',
    };
  }

  String _suppliersPageTitle(AppLocalizations? l10n) {
    if (Localizations.localeOf(context).languageCode == 'he') return 'סוכנים';
    final t = l10n?.tr('suppliers');
    if (t != null && t.isNotEmpty && t != 'suppliers') return t;
    return 'Suppliers';
  }

  String _newSupplierHeading(AppLocalizations? l10n) {
    if (Localizations.localeOf(context).languageCode == 'he') return 'סוכן חדש';
    final t = l10n?.tr('newSupplier');
    if (t != null && t.isNotEmpty && t != 'newSupplier') return t;
    return 'New Supplier';
  }

  String _fabNewSupplierTooltip(AppLocalizations? l10n) => _newSupplierHeading(l10n);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final suppliersAsync = ref.watch(suppliersProvider);

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
        elevation: 2,
        onPressed: () => _showSupplierDialog(context, ref, l10n),
        tooltip: _fabNewSupplierTooltip(l10n),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: _suppliersPageTitle(l10n),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                  labelText: _suppliersSearchFieldLabel(),
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
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                final q = _searchCtrl.text.trim().toLowerCase();
                final filtered = suppliers.where((s) {
                  if (q.isEmpty) return true;
                  final company = s.companyName.toLowerCase();
                  final contact = (s.contactName ?? '').toLowerCase();
                  final phone = (s.phone ?? '').toLowerCase();
                  final notes = (s.notes ?? '').toLowerCase();
                  return company.contains(q) ||
                      contact.contains(q) ||
                      phone.contains(q) ||
                      notes.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 80,
                          color:
                              AppTheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n?.tr('noData') ?? 'No Data',
                          style: GoogleFonts.assistant(
                            color: AppTheme.onSurfaceVariant,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final cols = _gridCols(width);

                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final supplier = filtered[index];
                          return StaggeredFadeIn(
                            index: index,
                            stepMilliseconds: 55,
                            child: _SupplierCard(
                              supplier: supplier,
                              index: index,
                              l10n: l10n,
                              onTap: () => _showSupplierDialog(
                                context,
                                ref,
                                l10n,
                                supplier: supplier,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => const AppLoadingOverlay(
                isLoading: true,
                child: SizedBox.expand(),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: GoogleFonts.assistant(color: AppTheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSupplierDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations? l10n, {
    Supplier? supplier,
  }) {
    final companyCtrl = TextEditingController(
      text: supplier?.companyName ?? '',
    );
    final contactCtrl = TextEditingController(
      text: supplier?.contactName ?? '',
    );
    final phoneCtrl = TextEditingController(text: supplier?.phone ?? '');
    final notesCtrl = TextEditingController(text: supplier?.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppTheme.surfaceContainerLowest,
        elevation: 8,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier != null
                      ? (l10n?.tr('edit') ?? 'Edit')
                      : _newSupplierHeading(l10n),
                  style: GoogleFonts.assistant(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: companyCtrl,
                  style: GoogleFonts.assistant(color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n?.tr('companyName') ?? 'Company Name',
                    labelStyle:
                        const TextStyle(color: AppTheme.onSurfaceVariant),
                    prefixIcon: const Icon(Icons.business,
                        color: AppTheme.onSurfaceVariant),
                    filled: true,
                    fillColor:
                        AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contactCtrl,
                  style: GoogleFonts.assistant(color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n?.tr('contactName') ?? 'Contact Name',
                    labelStyle:
                        const TextStyle(color: AppTheme.onSurfaceVariant),
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppTheme.onSurfaceVariant),
                    filled: true,
                    fillColor:
                        AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.assistant(color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n?.tr('phone') ?? 'Phone',
                    labelStyle:
                        const TextStyle(color: AppTheme.onSurfaceVariant),
                    prefixIcon: const Icon(Icons.phone,
                        color: AppTheme.onSurfaceVariant),
                    filled: true,
                    fillColor:
                        AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: GoogleFonts.assistant(color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n?.tr('notes') ?? 'Notes',
                    labelStyle:
                        const TextStyle(color: AppTheme.onSurfaceVariant),
                    filled: true,
                    fillColor:
                        AppTheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (supplier != null)
                      TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(
                                l10n?.tr('delete') ?? 'Delete',
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              content: Text(
                                'Delete ${supplier.companyName}?',
                                style: GoogleFonts.assistant(
                                  fontSize: 16,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(
                                    l10n?.tr('cancel') ?? 'Cancel',
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant,
                                    ),
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
                                    style: GoogleFonts.assistant(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await ref
                                .read(supplierServiceProvider)
                                .delete(supplier.id);
                            ref.invalidate(suppliersProvider);
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
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
                    if (supplier != null) const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: Text(l10n?.tr('cancel') ?? 'Cancel',
                          style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final username = ref.read(currentUsernameProvider);
                        if (supplier != null) {
                          // Update
                          await ref
                              .read(supplierServiceProvider)
                              .update(supplier.id, {
                            'company_name': companyCtrl.text.trim(),
                            'contact_name': contactCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'notes': notesCtrl.text.trim(),
                            'updated_by': username,
                          });
                        } else {
                          // Create
                          final newSupplier = Supplier(
                            id: '',
                            companyName: companyCtrl.text.trim(),
                            contactName: contactCtrl.text.trim(),
                            phone: phoneCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                            createdBy: username,
                            updatedBy: username,
                          );
                          await ref
                              .read(supplierServiceProvider)
                              .create(newSupplier);
                        }
                        ref.invalidate(suppliersProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary,
                        foregroundColor: AppTheme.onSecondary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(l10n?.tr('save') ?? 'Save',
                          style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700)),
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
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final int index;
  final AppLocalizations? l10n;
  final VoidCallback onTap;

  const _SupplierCard({
    required this.supplier,
    required this.index,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Matches the card vibe used in `CustomersScreen` (top banner + rounded card).
    final topColor =
        (index % 2 == 0) ? const Color(0xFF263248) : const Color(0xFFE2870F);

    final companyName = supplier.companyName.trim();
    final contactOrCompany = (supplier.contactName != null &&
            supplier.contactName!.trim().isNotEmpty)
        ? supplier.contactName!.trim()
        : companyName;

    final phone = (supplier.phone != null && supplier.phone!.trim().isNotEmpty)
        ? supplier.phone!.trim()
        : '-';

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
                height: 108,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          height: 98,
                          width: double.infinity,
                          decoration: BoxDecoration(color: topColor),
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
                          child: Center(
                            child: Text(
                              companyName.isNotEmpty
                                  ? companyName[0].toUpperCase()
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
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                color:
                                    AppTheme.secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _agentSingularLabel(context, l10n),
                                style: GoogleFonts.assistant(
                                  color: AppTheme.secondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                companyName,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            contactOrCompany,
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
                            phone,
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
                              // Simple always-on indicator to keep layout consistent.
                              // If you later add supplier status, we can map the color.
                              color: AppTheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _agentSingularLabel(context, l10n),
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
                  ],
                ),
              ),
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
                          Icon(
                            Icons.phone_outlined,
                            size: 16,
                            color: AppTheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            phone,
                            style: GoogleFonts.assistant(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          l10n?.tr('phone') ?? 'Phone',
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
      ),
    );
  }
}
