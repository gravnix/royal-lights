import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/payment.dart';
import '../../models/customer.dart';
import '../../providers/providers.dart';
import '../../services/payment_service.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../widgets/app_loading_overlay.dart';
import '../../widgets/editorial_screen_title.dart';

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

String _receiptUploadErrorMessage(
  BuildContext context,
  AppLocalizations? l10n,
  Object error,
) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('bucket not found')) {
    return _trOrLocale(
      context,
      l10n,
      'receiptStorageUnavailable',
      en: 'Receipt storage is not set up on the server. Contact your administrator.',
      he: 'אחסון הקבלות לא מוגדר בשרת. פנה למנהל המערכת.',
      ar: 'تخزين الإيصالات غير مُعد على الخادم. تواصل مع مسؤول النظام.',
    );
  }
  return '${_trOrLocale(context, l10n, 'receiptUploadFailed', en: 'Receipt upload failed', he: 'העלאת הקבלה נכשלה', ar: 'فشل رفع الإيصال')}: $error';
}

Future<void> _refreshPaymentsLists(
  WidgetRef ref, {
  required String customerId,
}) async {
  final filtered = ref.read(paymentsCustomerFilterProvider);
  if (filtered != null) {
    ref.invalidate(customerPaymentsProvider(filtered.id));
    await ref.read(customerPaymentsProvider(filtered.id).future);
  } else {
    ref.invalidate(paymentsProvider(null));
    await ref.read(paymentsProvider(null).future);
  }
  ref.invalidate(customerPaymentsProvider(customerId));
}

String _localizedPaymentType(
  BuildContext context,
  AppLocalizations? l10n,
  PaymentType t,
) {
  switch (t) {
    case PaymentType.cash:
      return _trOrLocale(context, l10n, 'cash',
          en: 'Cash', he: 'מזומן', ar: 'نقدي');
    case PaymentType.credit:
      return _trOrLocale(context, l10n, 'credit',
          en: 'Credit', he: 'אשראי', ar: 'بطاقة ائتمان');
    case PaymentType.check:
      return _trOrLocale(context, l10n, 'check',
          en: 'Check', he: 'צ\'ק', ar: 'شيك');
    case PaymentType.transfer:
      return _trOrLocale(context, l10n, 'transfer',
          en: 'Transfer', he: 'העברה', ar: 'تحويل');
  }
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  /// Optimistic receipt paths keyed by payment id (until provider refresh completes).
  final Map<String, String> _receiptOverrides = {};

  final _searchCtrl = TextEditingController();
  final _amountMinCtrl = TextEditingController();
  final _amountMaxCtrl = TextEditingController();

  /// Empty string means all customers.
  String _customerFilterId = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  /// `all` | `cash` | `credit` | `check` | `transfer`
  String _typeFilterKey = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountMinCtrl.dispose();
    _amountMaxCtrl.dispose();
    super.dispose();
  }

  List<Payment> _filterPayments(
    BuildContext context,
    List<Payment> payments,
    bool customerAlreadyScoped,
    AppLocalizations? l10n,
  ) {
    Iterable<Payment> it = payments;

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((p) {
        final notes = p.notes ?? '';
        final user = p.createdBy ?? '';
        final typeLabel =
            _localizedPaymentType(context, l10n, p.type).toLowerCase();
        return p.cardName.toLowerCase().contains(q) ||
            p.customerName.toLowerCase().contains(q) ||
            notes.toLowerCase().contains(q) ||
            user.toLowerCase().contains(q) ||
            p.type.dbValue.toLowerCase().contains(q) ||
            typeLabel.contains(q) ||
            p.amount.toString().contains(q);
      });
    }

    if (!customerAlreadyScoped && _customerFilterId.isNotEmpty) {
      it = it.where((p) => p.customerId == _customerFilterId);
    }

    if (_dateFrom != null) {
      final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      it = it.where((p) {
        final d = DateTime(p.date.year, p.date.month, p.date.day);
        return !d.isBefore(from);
      });
    }
    if (_dateTo != null) {
      final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day);
      it = it.where((p) {
        final d = DateTime(p.date.year, p.date.month, p.date.day);
        return !d.isAfter(to);
      });
    }

    final minAmt = double.tryParse(_amountMinCtrl.text.trim());
    if (minAmt != null) {
      it = it.where((p) => p.amount >= minAmt);
    }
    final maxAmt = double.tryParse(_amountMaxCtrl.text.trim());
    if (maxAmt != null) {
      it = it.where((p) => p.amount <= maxAmt);
    }

    if (_typeFilterKey != 'all') {
      final PaymentType? t = switch (_typeFilterKey) {
        'cash' => PaymentType.cash,
        'credit' => PaymentType.credit,
        'check' => PaymentType.check,
        'transfer' => PaymentType.transfer,
        _ => null,
      };
      if (t != null) {
        it = it.where((p) => p.type == t);
      }
    }

    return it.toList();
  }

  void _resetLocalFilters() {
    setState(() {
      _searchCtrl.clear();
      _amountMinCtrl.clear();
      _amountMaxCtrl.clear();
      _customerFilterId = '';
      _dateFrom = null;
      _dateTo = null;
      _typeFilterKey = 'all';
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  String _formatDay(DateTime d) => AppDateFormat.table(d);

  String? _storedReceipt(Payment payment) =>
      _receiptOverrides[payment.id] ?? payment.imageUrl;

  bool _hasReceipt(Payment payment) {
    final stored = _storedReceipt(payment);
    return stored != null && stored.trim().isNotEmpty;
  }

  String? _displayReceiptUrl(Payment payment) {
    final stored = _storedReceipt(payment);
    if (stored == null || stored.trim().isEmpty) return null;
    final client = ref.read(supabaseClientProvider);
    final bust = _receiptOverrides.containsKey(payment.id)
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : payment.updatedAt?.millisecondsSinceEpoch.toString();
    return PaymentService.resolveReceiptDisplayUrl(
      client,
      stored,
      cacheBustToken: bust,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filterCustomer = ref.watch(paymentsCustomerFilterProvider);
    final customersAsync = ref.watch(customersProvider);
    final customers = customersAsync.value ?? [];

    final AsyncValue<List<Payment>> paymentsAsync = filterCustomer != null
        ? ref.watch(customerPaymentsProvider(filterCustomer.id))
        : ref.watch(paymentsProvider(null));

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
        onPressed: () => showPaymentDialog(
          context,
          ref,
          l10n,
          initialCustomer: ref.read(paymentsCustomerFilterProvider),
          onReceiptSaved: (paymentId, storagePath) {
            if (!mounted) return;
            setState(() => _receiptOverrides[paymentId] = storagePath);
          },
        ),
        tooltip: l10n?.tr('newPayment') ?? 'New Payment',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EditorialScreenTitle(
            title: l10n?.tr('payments') ?? 'Payments',
          ),

          // Search & filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (filterCustomer != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      elevation: 0,
                      color: AppTheme.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_pin_circle_outlined,
                              size: 22,
                              color: AppTheme.secondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${filterCustomer.cardName} — ${filterCustomer.customerName}',
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppTheme.onSurface,
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                ref
                                    .read(
                                      paymentsCustomerFilterProvider.notifier,
                                    )
                                    .setFilter(null);
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(
                                l10n?.tr('clearFilter') ?? 'Clear filter',
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    AppTheme.surfaceContainerLowest,
                                foregroundColor: AppTheme.secondary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
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
                if (filterCustomer != null) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Material(
                        elevation: 2,
                        shadowColor: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          style:
                              GoogleFonts.assistant(color: AppTheme.onSurface),
                          decoration: InputDecoration(
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            floatingLabelAlignment:
                                FloatingLabelAlignment.start,
                            labelText: l10n?.tr('searchPaymentsHint') ??
                                'Search payments…',
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
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _resetLocalFilters,
                      icon: const Icon(Icons.restart_alt_rounded, size: 22),
                      label: Text(
                        l10n?.tr('resetFilters') ?? 'Reset filters',
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        backgroundColor:
                            AppTheme.secondaryContainer.withValues(alpha: 0.45),
                        foregroundColor: AppTheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context).copyWith(
                    inputDecorationTheme: paymentsFilterInputDecorationTheme(),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (filterCustomer == null)
                        SizedBox(
                          width: 300,
                          height: paymentsFilterControlHeight,
                          child: Center(
                            child: DropdownMenu<String>(
                              key: ValueKey(
                                'cust_${_customerFilterId}_${customers.length}',
                              ),
                              initialSelection: _customerFilterId,
                              width: 300,
                              enableFilter: true,
                              requestFocusOnTap: true,
                              leadingIcon: dropdownLeadingSlot(
                                Icon(
                                  Icons.groups_2_rounded,
                                  size: 18,
                                  color: AppTheme.secondary,
                                ),
                              ),
                              label: Text(
                                l10n?.tr('filterCustomer') ?? 'Customer',
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              hintText: l10n?.tr('all') ?? 'All',
                              menuStyle: appDropdownMenuStyle(),
                              inputDecorationTheme:
                                  paymentsFilterInputDecorationTheme(),
                              textStyle: GoogleFonts.assistant(
                                color: AppTheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              trailingIcon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppTheme.secondary,
                              ),
                              selectedTrailingIcon: Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: AppTheme.secondary,
                              ),
                              onSelected: (v) =>
                                  setState(() => _customerFilterId = v ?? ''),
                              dropdownMenuEntries: [
                                DropdownMenuEntry(
                                  value: '',
                                  label: l10n?.tr('all') ?? 'All',
                                ),
                                ...customers.map(
                                  (c) => DropdownMenuEntry(
                                    value: c.id,
                                    label: '${c.cardName} — ${c.customerName}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: () => _pickDate(true),
                        icon: const Icon(Icons.date_range_rounded, size: 20),
                        label: Text(
                          _dateFrom != null
                              ? _formatDay(_dateFrom!)
                              : (l10n?.tr('dateFrom') ?? 'From date'),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.surfaceContainerLowest,
                          foregroundColor: AppTheme.onSurface,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size(
                            0,
                            paymentsFilterControlHeight,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _pickDate(false),
                        icon: const Icon(Icons.event_note_rounded, size: 20),
                        label: Text(
                          _dateTo != null
                              ? _formatDay(_dateTo!)
                              : (l10n?.tr('dateTo') ?? 'To date'),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.surfaceContainerLowest,
                          foregroundColor: AppTheme.onSurface,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size(
                            0,
                            paymentsFilterControlHeight,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: AppTheme.outlineVariant
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: paymentsFilterControlHeight,
                        child: Center(
                          child: TextField(
                            controller: _amountMinCtrl,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              labelText: l10n?.tr('amountMin') ?? 'Min ₪',
                              prefixText: '₪ ',
                              prefixStyle: GoogleFonts.assistant(
                                color: AppTheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ).applyDefaults(
                              Theme.of(context).inputDecorationTheme,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: paymentsFilterControlHeight,
                        child: Center(
                          child: TextField(
                            controller: _amountMaxCtrl,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              labelText: l10n?.tr('amountMax') ?? 'Max ₪',
                              prefixText: '₪ ',
                              prefixStyle: GoogleFonts.assistant(
                                color: AppTheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ).applyDefaults(
                              Theme.of(context).inputDecorationTheme,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 210,
                        height: paymentsFilterControlHeight,
                        child: Builder(
                          builder: (context) {
                            final typeLeading = dropdownLeadingSlot(
                              Icon(
                                Icons.category_rounded,
                                size: 18,
                                color: AppTheme.secondary,
                              ),
                            );
                            return Center(
                              child: DropdownMenu<String>(
                                key: ValueKey('type_$_typeFilterKey'),
                                initialSelection: _typeFilterKey,
                                width: 210,
                                selectOnly: true,
                                enableFilter: false,
                                enableSearch: false,
                                leadingIcon: typeLeading,
                                decorationBuilder:
                                    animatedDropdownDecorationBuilder(
                                  label: Text(
                                    l10n?.tr('type') ?? 'Type',
                                    style: GoogleFonts.assistant(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  leadingIcon: typeLeading,
                                ),
                                menuStyle: appDropdownMenuStyle(),
                                inputDecorationTheme:
                                    paymentsFilterInputDecorationTheme(),
                                textStyle: GoogleFonts.assistant(
                                  color: AppTheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                onSelected: (v) => setState(
                                  () => _typeFilterKey = v ?? 'all',
                                ),
                                dropdownMenuEntries: [
                                  DropdownMenuEntry(
                                    value: 'all',
                                    label: l10n?.tr('allPaymentTypes') ??
                                        'All types',
                                  ),
                                  DropdownMenuEntry(
                                    value: 'cash',
                                    label: l10n?.tr('cash') ?? 'Cash',
                                  ),
                                  DropdownMenuEntry(
                                    value: 'credit',
                                    label: l10n?.tr('credit') ?? 'Credit',
                                  ),
                                  DropdownMenuEntry(
                                    value: 'check',
                                    label: l10n?.tr('check') ?? 'Check',
                                  ),
                                  DropdownMenuEntry(
                                    value: 'transfer',
                                    label: l10n?.tr('transfer') ?? 'Transfer',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Table Area
          Expanded(
            child: paymentsAsync.when(
              data: (payments) {
                final scoped = filterCustomer != null;
                final filtered =
                    _filterPayments(context, payments, scoped, l10n);

                if (payments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.payment_outlined,
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

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 80,
                          color:
                              AppTheme.onSurfaceVariant.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n?.tr('noMatchingResults') ??
                              'No payments match your filters',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.assistant(
                            color: AppTheme.onSurfaceVariant,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppTheme.outlineVariant.withValues(alpha: 0.2),
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
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          AppTheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        headingRowHeight: 64,
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 72,
                        columnSpacing: 24,
                        dividerThickness: 0.5,
                        columns: [
                          _buildColumnHeader(l10n?.tr('date') ?? 'Date'),
                          _buildColumnHeader(l10n?.tr('type') ?? 'Type'),
                          _buildColumnHeader(
                              l10n?.tr('cardName') ?? 'Card Name'),
                          _buildColumnHeader(
                              l10n?.tr('customerName') ?? 'Customer'),
                          _buildColumnHeader(l10n?.tr('amount') ?? 'Amount'),
                          _buildColumnHeader(l10n?.tr('image') ?? 'Receipt'),
                          _buildColumnHeader(l10n?.tr('notes') ?? 'Notes'),
                          _buildColumnHeader(l10n?.tr('username') ?? 'User'),
                          _buildColumnHeader(
                            _trOrLocale(
                              context,
                              l10n,
                              'actions',
                              en: 'Actions',
                              he: 'פעולות',
                              ar: 'إجراءات',
                            ),
                          ),
                        ],
                        rows: filtered.map((payment) {
                          late final Widget typeLeading;
                          late final Color typeColor;
                          switch (payment.type) {
                            case PaymentType.cash:
                              typeColor = AppTheme.success;
                              typeLeading = Text(
                                '\u20AA',
                                style: GoogleFonts.assistant(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: typeColor,
                                  height: 1,
                                ),
                              );
                              break;
                            case PaymentType.credit:
                              typeColor = AppTheme.secondary;
                              typeLeading = Icon(
                                Icons.credit_card,
                                size: 16,
                                color: typeColor,
                              );
                              break;
                            case PaymentType.check:
                              typeColor = AppTheme.warning;
                              typeLeading = Icon(
                                Icons.description,
                                size: 16,
                                color: typeColor,
                              );
                              break;
                            case PaymentType.transfer:
                              typeColor = const Color(0xFF1976D2);
                              typeLeading = Icon(
                                Icons.swap_horiz,
                                size: 16,
                                color: typeColor,
                              );
                              break;
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  AppDateFormat.tableOrDash(payment.date),
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      typeLeading,
                                      const SizedBox(width: 8),
                                      Text(
                                        _localizedPaymentType(
                                          context,
                                          l10n,
                                          payment.type,
                                        ),
                                        style: GoogleFonts.assistant(
                                          color: typeColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  payment.cardName,
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  payment.customerName,
                                  style: GoogleFonts.assistant(
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '₪${payment.amount.toStringAsFixed(0)}',
                                  style: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.secondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              DataCell(
                                _PaymentReceiptTableCell(
                                  type: payment.type,
                                  hasReceipt: _hasReceipt(payment),
                                  displayImageUrl: _displayReceiptUrl(payment),
                                  l10n: l10n,
                                ),
                                onTap: () async {
                                  await _onReceiptCellTapped(
                                    context,
                                    payment,
                                    l10n,
                                  );
                                },
                              ),
                              DataCell(
                                Text(
                                  payment.notes ?? '-',
                                  style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant),
                                ),
                              ),
                              DataCell(
                                Text(
                                  payment.createdBy ?? '-',
                                  style: GoogleFonts.assistant(
                                      color: AppTheme.onSurfaceVariant),
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: _trOrLocale(
                                    context,
                                    l10n,
                                    'delete',
                                    en: 'Delete',
                                    he: 'מחק',
                                    ar: 'حذف',
                                  ),
                                  onPressed: () => _confirmDeletePayment(
                                    context,
                                    payment,
                                    l10n,
                                  ),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppTheme.error.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
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

  Future<void> _onReceiptCellTapped(
    BuildContext context,
    Payment payment,
    AppLocalizations? l10n,
  ) async {
    final displayUrl = _displayReceiptUrl(payment);
    if (displayUrl != null && displayUrl.isNotEmpty) {
      _showPaymentReceiptPreview(context, displayUrl, l10n);
      return;
    }
    if (payment.type == PaymentType.check) {
      await _pickAndAttachCheckReceipt(context, payment, l10n);
    }
  }

  Future<void> _confirmDeletePayment(
    BuildContext context,
    Payment payment,
    AppLocalizations? l10n,
  ) async {
    final summary =
        '${payment.cardName} — ${payment.customerName}\n'
        '${AppDateFormat.tableOrDash(payment.date)} · '
        '₪${payment.amount.toStringAsFixed(0)} · '
        '${_localizedPaymentType(context, l10n, payment.type)}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _trOrLocale(ctx, l10n, 'deletePayment',
              en: 'Delete payment?', he: 'למחוק תשלום?', ar: 'حذف الدفعة؟'),
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w900,
            color: AppTheme.onSurface,
          ),
        ),
        content: Text(
          '${_trOrLocale(ctx, l10n, 'confirmDeletePayment', en: 'This permanently removes this payment record.', he: 'פעולה זו מוחקת את רשומת התשלום לצמיתות.', ar: 'سيؤدي هذا إلى إزالة سجل الدفعة نهائيًا.')}\n\n$summary',
          style: GoogleFonts.assistant(
            color: AppTheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_trOrLocale(ctx, l10n, 'cancel',
                en: 'Cancel', he: 'ביטול', ar: 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: AppTheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOrLocale(ctx, l10n, 'delete',
                en: 'Delete', he: 'מחק', ar: 'حذف')),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await ref.read(paymentServiceProvider).deleteWithReceipt(payment);
      _receiptOverrides.remove(payment.id);
      await _refreshPaymentsLists(ref, customerId: payment.customerId);
      ref.invalidate(customersProvider);
      ref.invalidate(totalUnpaidDebtsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, l10n, 'success',
                en: 'Success', he: 'הצלחה', ar: 'نجاح'),
            style: GoogleFonts.assistant(),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text(
            '${_trOrLocale(context, l10n, 'error', en: 'Error', he: 'שגיאה', ar: 'خطأ')}: $e',
            style: GoogleFonts.assistant(color: AppTheme.onError),
          ),
        ),
      );
    }
  }

  Future<void> _pickAndAttachCheckReceipt(
    BuildContext context,
    Payment payment,
    AppLocalizations? l10n,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(_trOrLocale(ctx, l10n, 'takePhoto',
                  en: 'Take Photo', he: 'צלם תמונה', ar: 'التقاط صورة')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_trOrLocale(ctx, l10n, 'chooseFromGallery',
                  en: 'Choose from Gallery',
                  he: 'בחר מגלריה',
                  ar: 'اختيار من المعرض')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (!mounted || xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted || bytes.isEmpty) return;

    final username = ref.read(currentUsernameProvider);
    try {
      final updated = await ref.read(paymentServiceProvider).attachReceiptPhoto(
            payment.id,
            bytes,
            updatedBy: username,
          );
      final storagePath = updated.imageUrl!.trim();
      setState(() => _receiptOverrides[payment.id] = storagePath);
      await _refreshPaymentsLists(ref, customerId: payment.customerId);
      if (!mounted) return;
      final filtered = ref.read(paymentsCustomerFilterProvider);
      final List<Payment> refreshedList;
      if (filtered != null) {
        refreshedList =
            await ref.read(customerPaymentsProvider(filtered.id).future);
      } else {
        refreshedList = await ref.read(paymentsProvider(null).future);
      }
      final refreshed = refreshedList
          .cast<Payment?>()
          .where((p) => p?.id == payment.id)
          .map((p) => p!)
          .firstOrNull;
      setState(() {
        if (refreshed != null &&
            refreshed.imageUrl != null &&
            refreshed.imageUrl!.trim().isNotEmpty) {
          _receiptOverrides.remove(payment.id);
        }
      });
      ref.invalidate(customersProvider);
      ref.invalidate(totalUnpaidDebtsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, l10n, 'success',
                en: 'Success', he: 'הצלחה', ar: 'نجاح'),
            style: GoogleFonts.assistant(),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text(
            _receiptUploadErrorMessage(context, l10n, e),
            style: GoogleFonts.assistant(color: AppTheme.onError),
          ),
        ),
      );
    }
  }

  DataColumn _buildColumnHeader(String label) {
    return DataColumn(
      label: Text(
        label,
        style: GoogleFonts.assistant(
          fontWeight: FontWeight.w700,
          color: AppTheme.onSurfaceVariant,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

void _showPaymentReceiptMemoryPreview(
  BuildContext context,
  Uint8List imageBytes,
  AppLocalizations? l10n,
) {
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
                    tooltip: _trOrLocale(ctx, l10n, 'close',
                        en: 'Close', he: 'סגור', ar: 'إغلاق'),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      imageBytes,
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

/// Same popup pattern as order form [OrderFormScreen._showImagePreview].
/// DataTable cells need [DataCell.onTap] — inner InkWell taps are ignored otherwise.
void _showPaymentReceiptPreview(
  BuildContext context,
  String imageUrl,
  AppLocalizations? l10n,
) {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty) return;

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
                    tooltip: _trOrLocale(ctx, l10n, 'close',
                        en: 'Close', he: 'סגור', ar: 'إغلاق'),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: trimmed,
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

class _PaymentReceiptTableCell extends StatelessWidget {
  const _PaymentReceiptTableCell({
    required this.type,
    required this.hasReceipt,
    required this.displayImageUrl,
    required this.l10n,
  });

  final PaymentType type;
  final bool hasReceipt;
  final String? displayImageUrl;
  final AppLocalizations? l10n;

  @override
  Widget build(BuildContext context) {
    if (!hasReceipt) {
      if (type == PaymentType.check) {
        return Tooltip(
          message: _trOrLocale(context, l10n, 'attachCheckPhoto',
              en: 'Add check photo',
              he: 'הוספת תמונת צ\'ק',
              ar: 'إضافة صورة الشيك'),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              Icons.add_a_photo_outlined,
              size: 22,
              color: AppTheme.warning,
            ),
          ),
        );
      }
      return Icon(
        Icons.remove,
        color: AppTheme.onSurfaceVariant.withValues(alpha: 0.4),
        size: 20,
      );
    }
    return Tooltip(
      message: _trOrLocale(context, l10n, 'view',
          en: 'View', he: 'הצג', ar: 'عرض'),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: displayImageUrl ?? '',
              cacheKey: displayImageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.secondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Icon(
                Icons.receipt_long_rounded,
                color: AppTheme.success,
                size: 22,
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.surfaceContainerLowest,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.zoom_in_rounded,
                  size: 11,
                  color: AppTheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations? l10n, {
  Customer? initialCustomer,
  void Function(String paymentId, String storagePath)? onReceiptSaved,
}) {
  final customersAsync = ref.read(customersProvider);
  final customers = customersAsync.value ?? [];

  Customer? selectedCustomer = initialCustomer;
  PaymentType selectedType = PaymentType.cash;
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  Uint8List? receiptImageBytes;
  var isSaving = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pickReceipt(ImageSource source) async {
          final picker = ImagePicker();
          final xFile = await picker.pickImage(
            source: source,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 88,
          );
          if (xFile == null) return;
          final bytes = await xFile.readAsBytes();
          setDialogState(() => receiptImageBytes = bytes);
        }

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    l10n?.tr('newPayment') ?? 'New Payment',
                    style: GoogleFonts.assistant(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: DropdownMenu<Customer>(
                      key: ValueKey(selectedCustomer?.id ?? 'none'),
                      initialSelection: selectedCustomer,
                      enabled: initialCustomer == null,
                      width: 436,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      leadingIcon: dropdownLeadingSlot(
                        Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: AppTheme.secondary,
                        ),
                      ),
                      label: Text(
                        l10n?.tr('customerName') ?? 'Customer',
                        style: GoogleFonts.assistant(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      menuStyle: appDropdownMenuStyle(),
                      inputDecorationTheme: appDropdownInputDecorationTheme(),
                      textStyle: GoogleFonts.assistant(
                        color: AppTheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      trailingIcon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.secondary,
                      ),
                      selectedTrailingIcon: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppTheme.secondary,
                      ),
                      onSelected: initialCustomer != null
                          ? null
                          : (c) => setDialogState(() => selectedCustomer = c),
                      dropdownMenuEntries: customers
                          .map(
                            (c) => DropdownMenuEntry<Customer>(
                              value: c,
                              label: '${c.cardName} — ${c.customerName}',
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (context) {
                        final dialogTypeLeading = dropdownLeadingSlot(
                          Icon(
                            Icons.payments_rounded,
                            size: 18,
                            color: AppTheme.secondary,
                          ),
                        );
                        return DropdownMenu<PaymentType>(
                          key: ValueKey(selectedType.name),
                          initialSelection: selectedType,
                          width: 436,
                          selectOnly: true,
                          enableFilter: false,
                          enableSearch: false,
                          leadingIcon: dialogTypeLeading,
                          decorationBuilder: animatedDropdownDecorationBuilder(
                            label: Text(
                              l10n?.tr('type') ?? 'Type',
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            leadingIcon: dialogTypeLeading,
                          ),
                          menuStyle: appDropdownMenuStyle(),
                          inputDecorationTheme:
                              appDropdownInputDecorationTheme(),
                          textStyle: GoogleFonts.assistant(
                            color: AppTheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (v) => setDialogState(
                            () => selectedType = v ?? PaymentType.cash,
                          ),
                          dropdownMenuEntries: PaymentType.values
                              .map(
                                (t) => DropdownMenuEntry<PaymentType>(
                                  value: t,
                                  label: _localizedPaymentType(ctx, l10n, t),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Amount
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppTheme.onSurface),
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      floatingLabelAlignment: FloatingLabelAlignment.start,
                      labelText: l10n?.tr('amount') ?? 'Amount',
                      labelStyle:
                          const TextStyle(color: AppTheme.onSurfaceVariant),
                      floatingLabelStyle: const TextStyle(
                        color: AppTheme.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      prefixIcon: dropdownLeadingSlot(
                        Text(
                          '\u20AA',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.assistant(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.secondary,
                            height: 1,
                          ),
                        ),
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.secondary,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _trOrLocale(ctx, l10n, 'receipt',
                        en: 'Receipt', he: 'קבלה', ar: 'إيصال'),
                    style: GoogleFonts.assistant(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                  if (selectedType == PaymentType.check) ...[
                    const SizedBox(height: 6),
                    Text(
                      _trOrLocale(ctx, l10n, 'checkPhotoRequired',
                          en: 'Attach a photo of the check before saving.',
                          he: 'יש לצרף תמונת צ\'ק לפני השמירה.',
                          ar: 'يرجى إرفاق صورة الشيك قبل الحفظ.'),
                      style: GoogleFonts.assistant(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 18,
                          ),
                          side: BorderSide(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: AppTheme.onSurfaceVariant,
                        ),
                        onPressed: isSaving
                            ? null
                            : () => pickReceipt(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 20),
                        label: Text(_trOrLocale(ctx, l10n, 'takePhoto',
                            en: 'Take Photo',
                            he: 'צלם תמונה',
                            ar: 'التقاط صورة')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 18,
                          ),
                          side: BorderSide(
                            color:
                                AppTheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: AppTheme.onSurfaceVariant,
                        ),
                        onPressed: isSaving
                            ? null
                            : () => pickReceipt(ImageSource.gallery),
                        icon:
                            const Icon(Icons.photo_library_outlined, size: 20),
                        label: Text(_trOrLocale(ctx, l10n, 'chooseFromGallery',
                            en: 'Choose from Gallery',
                            he: 'בחר מגלריה',
                            ar: 'اختيار من المعرض')),
                      ),
                      if (receiptImageBytes != null)
                        TextButton.icon(
                          onPressed: isSaving
                              ? null
                              : () => setDialogState(
                                  () => receiptImageBytes = null),
                          icon: Icon(Icons.close_rounded,
                              color: AppTheme.error.withValues(alpha: 0.9)),
                          label: Text(
                            l10n?.tr('delete') ?? 'Remove',
                            style: GoogleFonts.assistant(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (receiptImageBytes != null) ...[
                    const SizedBox(height: 12),
                    Tooltip(
                      message: _trOrLocale(ctx, l10n, 'view',
                          en: 'View', he: 'הצג', ar: 'عرض'),
                      child: InkWell(
                        onTap: isSaving
                            ? null
                            : () => _showPaymentReceiptMemoryPreview(
                                  ctx,
                                  receiptImageBytes!,
                                  l10n,
                                ),
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.memory(
                                receiptImageBytes!,
                                height: 140,
                                width: 436,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.88),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.surfaceContainerLowest,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.zoom_in_rounded,
                                  size: 16,
                                  color: AppTheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Notes
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppTheme.onSurface),
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      floatingLabelAlignment: FloatingLabelAlignment.start,
                      labelText: l10n?.tr('notes') ?? 'Notes',
                      labelStyle:
                          const TextStyle(color: AppTheme.onSurfaceVariant),
                      floatingLabelStyle: const TextStyle(
                        color: AppTheme.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.secondary,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
                        onPressed: isSaving || selectedCustomer == null
                            ? null
                            : () async {
                                if (selectedType == PaymentType.check &&
                                    (receiptImageBytes == null ||
                                        receiptImageBytes!.isEmpty)) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _trOrLocale(
                                            ctx,
                                            l10n,
                                            'checkPhotoRequired',
                                            en: 'Attach a photo of the check before saving.',
                                            he: 'יש לצרף תמונת צ\'ק לפני השמירה.',
                                            ar: 'يرجى إرفاق صورة الشيك قبل الحفظ.',
                                          ),
                                          style: GoogleFonts.assistant(),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final username =
                                    ref.read(currentUsernameProvider);
                                setDialogState(() => isSaving = true);
                                try {
                                  final payment = Payment(
                                    id: '',
                                    customerId: selectedCustomer!.id,
                                    date: DateTime.now(),
                                    type: selectedType,
                                    cardName: selectedCustomer!.cardName,
                                    customerName:
                                        selectedCustomer!.customerName,
                                    amount:
                                        double.tryParse(amountCtrl.text) ?? 0,
                                    notes: notesCtrl.text.trim().isEmpty
                                        ? null
                                        : notesCtrl.text.trim(),
                                    createdBy: username,
                                    updatedBy: username,
                                  );
                                  final created = await ref
                                      .read(paymentServiceProvider)
                                      .create(payment);
                                  var uploadOk = true;
                                  if (receiptImageBytes != null &&
                                      receiptImageBytes!.isNotEmpty) {
                                    try {
                                      final updated = await ref
                                          .read(paymentServiceProvider)
                                          .attachReceiptPhoto(
                                            created.id,
                                            receiptImageBytes!,
                                            updatedBy: username,
                                          );
                                      onReceiptSaved?.call(
                                        created.id,
                                        updated.imageUrl!.trim(),
                                      );
                                    } catch (e) {
                                      uploadOk = false;
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppTheme.error,
                                            content: Text(
                                              _receiptUploadErrorMessage(
                                                ctx,
                                                l10n,
                                                e,
                                              ),
                                              style: GoogleFonts.assistant(
                                                color: AppTheme.onError,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  }
                                  if (!uploadOk) return;
                                  await _refreshPaymentsLists(
                                    ref,
                                    customerId: selectedCustomer!.id,
                                  );
                                  ref.invalidate(customersProvider);
                                  ref.invalidate(totalUnpaidDebtsProvider);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } finally {
                                  if (ctx.mounted) {
                                    setDialogState(() => isSaving = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondary,
                          foregroundColor: AppTheme.onSecondary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppTheme.onSecondary,
                                ),
                              )
                            : Text(
                                l10n?.tr('save') ?? 'Save',
                                style: GoogleFonts.assistant(
                                  fontWeight: FontWeight.w700,
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
    ),
  );
}
