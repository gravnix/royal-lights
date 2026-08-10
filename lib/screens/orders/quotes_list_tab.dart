import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_animations.dart';
import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/quote.dart';
import '../../providers/providers.dart';
import '../../services/quote_pdf_service.dart';
import '../../services/whatsapp_service.dart';
import '../../widgets/app_dropdown_styles.dart';
import '../../widgets/confirm_send_customer_wa.dart';
import '../../widgets/quote_pdf_preview_dialog.dart';
import '../customers/customer_detail_screen.dart';
import 'order_form_screen.dart';

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

/// Global quotes list — filters, view PDF, resend WhatsApp, convert to order.
class QuotesListTab extends ConsumerStatefulWidget {
  const QuotesListTab({super.key, this.active = true});

  /// When this tab is shown; drives appear animations on switch.
  final bool active;

  @override
  ConsumerState<QuotesListTab> createState() => _QuotesListTabState();
}

class _QuotesListTabState extends ConsumerState<QuotesListTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _statusFilter = 'All';
  int _sortColumnIndex = 3;
  bool _sortAscending = false;
  int _currentPage = 1;
  int _rowsPerPage = 15;
  static const _rowsPerPageOptions = [10, 15, 25, 50];
  String? _busyQuoteId;
  int _appearGen = 0;

  @override
  void didUpdateWidget(covariant QuotesListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      setState(() => _appearGen++);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _searchQuery => _searchCtrl.text.trim().toLowerCase();

  Color _statusColor(QuoteStatus s) {
    switch (s) {
      case QuoteStatus.sent:
        return AppTheme.secondary;
      case QuoteStatus.accepted:
        return AppTheme.success;
      case QuoteStatus.converted:
        return AppTheme.primary;
      case QuoteStatus.expired:
        return AppTheme.error;
    }
  }

  String _statusLabel(BuildContext context, AppLocalizations? l10n, QuoteStatus s) {
    switch (s) {
      case QuoteStatus.sent:
        return _trLocale(context, l10n, 'quoteStatusSent',
            en: 'Sent', he: 'נשלחה', ar: 'مُرسل');
      case QuoteStatus.accepted:
        return _trLocale(context, l10n, 'quoteStatusAccepted',
            en: 'Accepted', he: 'התקבלה', ar: 'مقبول');
      case QuoteStatus.converted:
        return _trLocale(context, l10n, 'quoteStatusConverted',
            en: 'Converted', he: 'הומרה', ar: 'محوّل');
      case QuoteStatus.expired:
        return _trLocale(context, l10n, 'quoteStatusExpired',
            en: 'Expired', he: 'פגה תוקף', ar: 'منتهي الصلاحية');
    }
  }

  Customer? _findCustomer(String customerId) {
    final customers = ref.read(customersProvider).value;
    if (customers == null) return null;
    for (final c in customers) {
      if (c.id == customerId) return c;
    }
    return null;
  }

  Future<void> _viewQuote(Quote quote) async {
    await showQuotePdfPreview(
      context,
      quote: quote,
      l10n: AppLocalizations.of(context),
    );
  }

  Future<void> _resendQuote(Quote quote) async {
    final l10n = AppLocalizations.of(context);
    final customer = _findCustomer(quote.customerId);
    if (customer == null) {
      _snack(
        _trLocale(context, l10n, 'quoteCustomerMissing',
            en: 'Customer not found for this quote.',
            he: 'הלקוח להצעה זו לא נמצא.',
            ar: 'لم يتم العثور على العميل لهذا العرض.'),
        error: true,
      );
      return;
    }
    if (customer.phones.isEmpty) {
      _snack(
        _trLocale(context, l10n, 'quoteNoPhone',
            en: 'Customer has no phone number.',
            he: 'ללקוח אין מספר טלפון.',
            ar: 'لا يوجد رقم هاتف للعميل.'),
        error: true,
      );
      return;
    }

    final ok = await confirmSendCustomerWhatsApp(context);
    if (!ok || !mounted) return;

    setState(() => _busyQuoteId = quote.id);
    try {
      var pdfUrl = quote.pdfUrl?.trim() ?? '';
      if (pdfUrl.isEmpty) {
        // Regenerate if the stored PDF is missing.
        final full = await ref.read(quoteServiceProvider).getById(quote.id);
        if (!mounted) return;
        final lang = Localizations.localeOf(context).languageCode;
        await QuotePdfService.warmUp(lang);
        final bytes = await QuotePdfService.generate(
          customer: customer,
          quote: full,
          items: full.items,
          languageCode: lang,
        );
        pdfUrl = await ref
            .read(quoteServiceProvider)
            .uploadPdf(full.id, bytes);
        await ref.read(quoteServiceProvider).setPdfUrl(full.id, pdfUrl);
      }

      if (!mounted) return;
      final displayName = customer.customerName.trim().isNotEmpty
          ? customer.customerName
          : customer.cardName;
      final lang = Localizations.localeOf(context).languageCode;
      final caption = switch (lang) {
        'he' =>
          'שלום $displayName,\nמצורפת הצעת מחיר מ-Royal Lights.\nנשמח לעמוד לשירותכם!',
        'ar' =>
          'مرحبًا $displayName،\nمرفق عرض سعر من Royal Lights.\nنتطلع لخدمتكم!',
        _ =>
          'Hello $displayName,\nPlease find attached a price quote from Royal Lights.\nWe look forward to serving you!',
      };

      final sent = await WhatsAppService.sendDocument(
        customer.phones.first,
        pdfUrl,
        caption,
      );
      if (!mounted) return;
      if (sent) {
        _snack(
          _trLocale(context, l10n, 'quoteResent',
              en: 'Quote resent via WhatsApp.',
              he: 'ההצעה נשלחה מחדש בוואטסאפ.',
              ar: 'أُعيد إرسال العرض عبر واتساب.'),
        );
        ref.invalidate(quotesProvider);
        ref.invalidate(customerQuotesProvider(quote.customerId));
      } else {
        _snack(
          _trLocale(context, l10n, 'quoteResendFailed',
              en: 'Failed to resend quote.',
              he: 'שליחת ההצעה מחדש נכשלה.',
              ar: 'فشل إعادة إرسال العرض.'),
          error: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack(
        _trLocale(context, l10n, 'quoteResendFailed',
            en: 'Failed to resend quote: $e',
            he: 'שליחת ההצעה מחדש נכשלה: $e',
            ar: 'فشل إعادة إرسال العرض: $e'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyQuoteId = null);
    }
  }

  Future<void> _convertToOrder(Quote quote) async {
    final l10n = AppLocalizations.of(context);
    if (quote.status == QuoteStatus.converted ||
        quote.status == QuoteStatus.expired) {
      _snack(
        _trLocale(context, l10n, 'quoteCannotConvert',
            en: 'This quote cannot be converted.',
            he: 'לא ניתן להמיר הצעה זו.',
            ar: 'لا يمكن تحويل هذا العرض.'),
        error: true,
      );
      return;
    }

    setState(() => _busyQuoteId = quote.id);
    try {
      final full = await ref.read(quoteServiceProvider).getById(quote.id);
      final customer = _findCustomer(full.customerId);
      if (!mounted) return;

      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OrderFormScreen(
            initialCustomer: customer,
            initialQuoteItems: full.items,
            sourceQuoteId: full.id,
          ),
        ),
      );

      if (!mounted) return;
      ref.invalidate(quotesProvider);
      ref.invalidate(customerQuotesProvider(quote.customerId));
      ref.invalidate(ordersProvider);
      if (customer != null) {
        ref.invalidate(customerOrdersProvider(customer.id));
      }

      // Order form pops without a typed result; detect conversion via status.
      try {
        final updated =
            await ref.read(quoteServiceProvider).getById(quote.id);
        if (updated.status == QuoteStatus.converted && mounted) {
          _snack(
            _trLocale(context, l10n, 'quoteConverted',
                en: 'Quote converted to order',
                he: 'הצעת המחיר הומרה להזמנה',
                ar: 'تم تحويل العرض إلى طلب'),
          );
        }
      } catch (_) {
        if (result == true && mounted) {
          _snack(
            _trLocale(context, l10n, 'quoteConverted',
                en: 'Quote converted to order',
                he: 'הצעת המחיר הומרה להזמנה',
                ar: 'تم تحويل العرض إلى طلب'),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack(
        _trLocale(context, l10n, 'error',
            en: 'Error: $e', he: 'שגיאה: $e', ar: 'خطأ: $e'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyQuoteId = null);
    }
  }

  Future<void> _markExpired(Quote quote) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _trLocale(context, l10n, 'markQuoteExpiredTitle',
              en: 'Mark as expired?',
              he: 'לסמן כפג תוקף?',
              ar: 'تعيين كمنتهي الصلاحية؟'),
          style: GoogleFonts.assistant(fontWeight: FontWeight.w800),
        ),
        content: Text(
          _trLocale(context, l10n, 'markQuoteExpiredBody',
              en: 'Quote #${quote.quoteNumber ?? ''} will be marked expired.',
              he: 'הצעה מס׳ ${quote.quoteNumber ?? ''} תסומן כפגת תוקף.',
              ar: 'سيتم تعليم العرض رقم ${quote.quoteNumber ?? ''} كمنتهي الصلاحية.'),
          style: GoogleFonts.assistant(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _trLocale(context, l10n, 'cancel',
                  en: 'Cancel', he: 'ביטול', ar: 'إلغاء'),
              style: GoogleFonts.assistant(color: AppTheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _trLocale(context, l10n, 'confirm',
                  en: 'Confirm', he: 'אישור', ar: 'تأكيد'),
              style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyQuoteId = quote.id);
    try {
      final username = ref.read(currentUsernameProvider);
      await ref
          .read(quoteServiceProvider)
          .updateStatus(quote.id, 'Expired', username);
      ref.invalidate(quotesProvider);
      ref.invalidate(customerQuotesProvider(quote.customerId));
      if (!mounted) return;
      _snack(
        _trLocale(context, l10n, 'quoteMarkedExpired',
            en: 'Quote marked as expired.',
            he: 'ההצעה סומנה כפגת תוקף.',
            ar: 'تم تعليم العرض كمنتهي الصلاحية.'),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        _trLocale(context, l10n, 'error',
            en: 'Error: $e', he: 'שגיאה: $e', ar: 'خطأ: $e'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyQuoteId = null);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.assistant()),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
      ),
    );
  }

  void _openCustomer(Quote quote) {
    final customer = _findCustomer(quote.customerId);
    if (customer == null) {
      _snack(
        _trLocale(context, AppLocalizations.of(context), 'quoteCustomerMissing',
            en: 'Customer not found for this quote.',
            he: 'הלקוח להצעה זו לא נמצא.',
            ar: 'لم يتم العثور على العميل لهذا العرض.'),
        error: true,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customer: customer),
      ),
    );
  }

  Widget _statusChip(
      BuildContext context, AppLocalizations? l10n, QuoteStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(context, l10n, status),
        style: GoogleFonts.assistant(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? (color ?? AppTheme.onSurfaceVariant)
                  : AppTheme.onSurfaceVariant.withValues(alpha: 0.32),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionsCell(List<Widget> buttons) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            buttons[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quotesAsync = ref.watch(quotesProvider);
    // Warm customers for phone / convert lookups.
    ref.watch(customersProvider);

    return quotesAsync.when(
      data: (quotes) {
        var filtered = quotes.where((q) {
          if (_statusFilter != 'All' && q.status.dbValue != _statusFilter) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final n = q.quoteNumber?.toString() ?? '';
            final card = (q.cardName ?? '').toLowerCase();
            final name = (q.customerName ?? '').toLowerCase();
            return n.contains(_searchQuery) ||
                card.contains(_searchQuery) ||
                name.contains(_searchQuery);
          }
          return true;
        }).toList();

        filtered.sort((a, b) {
          int comp;
          switch (_sortColumnIndex) {
            case 0:
              comp = (a.quoteNumber ?? 0).compareTo(b.quoteNumber ?? 0);
              break;
            case 1:
              comp = (a.cardName ?? '')
                  .toLowerCase()
                  .compareTo((b.cardName ?? '').toLowerCase());
              break;
            case 2:
              comp = (a.customerName ?? '')
                  .toLowerCase()
                  .compareTo((b.customerName ?? '').toLowerCase());
              break;
            case 3:
              final ad =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bd =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              comp = ad.compareTo(bd);
              break;
            case 4:
              comp = a.status.dbValue.compareTo(b.status.dbValue);
              break;
            case 5:
              comp = a.totalPrice.compareTo(b.totalPrice);
              break;
            default:
              comp = (a.quoteNumber ?? 0).compareTo(b.quoteNumber ?? 0);
          }
          return _sortAscending ? comp : -comp;
        });

        final totalItems = filtered.length;
        final totalPages =
            totalItems == 0 ? 1 : (totalItems / _rowsPerPage).ceil();
        var page = _currentPage.clamp(1, totalPages);
        final start = (page - 1) * _rowsPerPage;
        final end = (start + _rowsPerPage).clamp(0, totalItems);
        final pageRows =
            filtered.isEmpty ? <Quote>[] : filtered.sublist(start, end);

        final statusItems = <DropdownMenuEntry<String>>[
          DropdownMenuEntry(
            value: 'All',
            label: _trLocale(context, l10n, 'all',
                en: 'All', he: 'הכל', ar: 'الكل'),
          ),
          for (final s in QuoteStatus.values)
            DropdownMenuEntry(
              value: s.dbValue,
              label: _statusLabel(context, l10n, s),
            ),
        ];

        return Stack(
            children: [
              Column(
                children: [
                  AppearOnActivate(
                    active: widget.active,
                    slideDy: 10,
                    scaleBegin: 0.99,
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {
                              _currentPage = 1;
                            }),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: _trLocale(
                                context,
                                l10n,
                                'searchQuotesHint',
                                en: 'Search by quote #, card, customer…',
                                he: 'חיפוש לפי מספר הצעה, כרטיס, לקוח…',
                                ar: 'بحث برقم العرض أو البطاقة أو العميل…',
                              ),
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: AppTheme.surfaceContainerLowest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: AppTheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: AppTheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppTheme.secondary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownMenu<String>(
                          key: ValueKey('quote_stat_$_statusFilter'),
                          initialSelection: _statusFilter,
                          width: 220,
                          selectOnly: true,
                          enableFilter: false,
                          enableSearch: false,
                          dropdownMenuEntries: statusItems,
                          onSelected: (v) {
                            if (v == null) return;
                            setState(() {
                              _statusFilter = v;
                              _currentPage = 1;
                            });
                          },
                          decorationBuilder: animatedDropdownDecorationBuilder(
                            label: Text(
                              _trLocale(context, l10n, 'status',
                                  en: 'Status', he: 'סטטוס', ar: 'الحالة'),
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          menuStyle: appDropdownMenuStyle(),
                          inputDecorationTheme: appDropdownInputDecorationTheme()
                              .copyWith(fillColor: Colors.white),
                          textStyle: GoogleFonts.assistant(
                            color: AppTheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: _trLocale(context, l10n, 'refresh',
                              en: 'Refresh', he: 'רענן', ar: 'تحديث'),
                          onPressed: () {
                            ref.invalidate(quotesProvider);
                            ref.invalidate(customersProvider);
                          },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  ),
                  Expanded(
                    child: AppearOnActivate(
                      active: widget.active,
                      delay: const Duration(milliseconds: 55),
                      slideDy: 18,
                      scaleBegin: 0.988,
                      child: pageRows.isEmpty
                        ? Center(
                            child: Text(
                              _trLocale(context, l10n, 'noQuotesFound',
                                  en: 'No quotes found.',
                                  he: 'לא נמצאו הצעות מחיר.',
                                  ar: 'لم يتم العثور على عروض أسعار.'),
                              style: GoogleFonts.assistant(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Material(
                                        color: AppTheme.surfaceContainerLowest,
                                        child: DataTable(
                                  showCheckboxColumn: false,
                                  horizontalMargin: 16,
                                  columnSpacing: 24,
                                  headingRowHeight: 56,
                                  dataRowMinHeight: 64,
                                  dataRowMaxHeight: 80,
                                  sortColumnIndex: _sortColumnIndex,
                                  sortAscending: _sortAscending,
                                  headingRowColor: WidgetStatePropertyAll(
                                    AppTheme.surfaceContainer
                                        .withValues(alpha: 0.65),
                                  ),
                                  headingTextStyle: GoogleFonts.assistant(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                  dataTextStyle: GoogleFonts.assistant(
                                    color: AppTheme.onSurface,
                                    fontSize: 14,
                                  ),
                                  columns: [
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'quoteNumber',
                                            en: 'Quote #',
                                            he: 'מס׳ הצעה',
                                            ar: 'رقم العرض'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'cardName',
                                            en: 'Card',
                                            he: 'כרטיס',
                                            ar: 'البطاقة'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'customerName',
                                            en: 'Customer',
                                            he: 'לקוח',
                                            ar: 'العميل'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'date',
                                            en: 'Date', he: 'תאריך', ar: 'التاريخ'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'status',
                                            en: 'Status', he: 'סטטוס', ar: 'الحالة'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      numeric: true,
                                      label: Text(
                                        _trLocale(context, l10n, 'total',
                                            en: 'Total', he: 'סה״כ', ar: 'المجموع'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onSort: (i, asc) => setState(() {
                                        _sortColumnIndex = i;
                                        _sortAscending = asc;
                                      }),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        _trLocale(context, l10n, 'actions',
                                            en: 'Actions',
                                            he: 'פעולות',
                                            ar: 'إجراءات'),
                                        style: GoogleFonts.assistant(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                  rows: [
                                    for (var i = 0; i < pageRows.length; i++)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            StaggeredFadeIn(
                                              key: ValueKey('qrow-$_appearGen-$i'),
                                              index: i.clamp(0, 12),
                                              stepMilliseconds: 40,
                                              child: Text(
                                                '#${pageRows[i].quoteNumber ?? pageRows[i].id.substring(0, 6)}',
                                                style: GoogleFonts.assistant(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            onTap: () => _viewQuote(pageRows[i]),
                                          ),
                                          DataCell(
                                            Text(
                                              pageRows[i].cardName ?? '—',
                                              style: GoogleFonts.assistant(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            onTap: () => _openCustomer(pageRows[i]),
                                          ),
                                          DataCell(
                                            Text(
                                              pageRows[i].customerName ?? '—',
                                              style: GoogleFonts.assistant(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            onTap: () => _openCustomer(pageRows[i]),
                                          ),
                                          DataCell(
                                            Text(
                                              AppDateFormat.tableOrDash(
                                                  pageRows[i].createdAt),
                                              style: GoogleFonts.assistant(),
                                            ),
                                          ),
                                          DataCell(
                                            _statusChip(
                                                context, l10n, pageRows[i].status),
                                          ),
                                          DataCell(
                                            Text(
                                              '₪${pageRows[i].totalPrice.toStringAsFixed(0)}',
                                              style: GoogleFonts.assistant(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            _actionsCell([
                                              _roundIconButton(
                                                icon: Icons.visibility_outlined,
                                                tooltip: _trLocale(
                                                    context, l10n, 'viewQuote',
                                                    en: 'View quote',
                                                    he: 'צפה בהצעה',
                                                    ar: 'عرض العرض'),
                                                color: AppTheme.secondary,
                                                onPressed: () =>
                                                    _viewQuote(pageRows[i]),
                                              ),
                                              _roundIconButton(
                                                icon: Icons.send_rounded,
                                                tooltip: _trLocale(context, l10n,
                                                    'resendQuote',
                                                    en: 'Resend WhatsApp',
                                                    he: 'שלח מחדש בוואטסאפ',
                                                    ar: 'إعادة إرسال واتساب'),
                                                color: AppTheme.secondary,
                                                onPressed: (pageRows[i].status ==
                                                            QuoteStatus.expired ||
                                                        pageRows[i].status ==
                                                            QuoteStatus.converted)
                                                    ? null
                                                    : () => _resendQuote(pageRows[i]),
                                              ),
                                              _roundIconButton(
                                                icon: Icons.shopping_cart_checkout,
                                                tooltip: _trLocale(context, l10n,
                                                    'convertToOrder',
                                                    en: 'Convert to order',
                                                    he: 'המר להזמנה',
                                                    ar: 'تحويل إلى طلب'),
                                                color: AppTheme.primary,
                                                onPressed: (pageRows[i].status ==
                                                            QuoteStatus.sent ||
                                                        pageRows[i].status ==
                                                            QuoteStatus.accepted)
                                                    ? () => _convertToOrder(pageRows[i])
                                                    : null,
                                              ),
                                              _roundIconButton(
                                                icon: Icons.timer_off_outlined,
                                                tooltip: _trLocale(context, l10n,
                                                    'markQuoteExpired',
                                                    en: 'Mark expired',
                                                    he: 'סמן כפג תוקף',
                                                    ar: 'تعيين منتهي'),
                                                color: AppTheme.error,
                                                onPressed: (pageRows[i].status ==
                                                            QuoteStatus.sent ||
                                                        pageRows[i].status ==
                                                            QuoteStatus.accepted)
                                                    ? () => _markExpired(pageRows[i])
                                                    : null,
                                              ),
                                            ]),
                                          ),
                                        ],
                                      ),
                                  ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    ),
                  ),
                  if (totalItems > 0)
                    AppearOnActivate(
                      active: widget.active,
                      delay: const Duration(milliseconds: 100),
                      slideDy: 10,
                      scaleBegin: 0.99,
                      child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Row(
                        children: [
                          Text(
                            _trLocale(
                              context,
                              l10n,
                              'showingRange',
                              en:
                                  'Showing ${start + 1}–$end of $totalItems',
                              he:
                                  'מציג ${start + 1}–$end מתוך $totalItems',
                              ar:
                                  'عرض ${start + 1}–$end من $totalItems',
                            ),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _trLocale(context, l10n, 'rowsPerPage',
                                en: 'Rows', he: 'שורות', ar: 'صفوف'),
                            style: GoogleFonts.assistant(
                              color: AppTheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownMenu<int>(
                            key: ValueKey('quotes_rows_$_rowsPerPage'),
                            initialSelection: _rowsPerPage,
                            width: 88,
                            selectOnly: true,
                            enableFilter: false,
                            enableSearch: false,
                            textStyle: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            menuStyle: appDropdownMenuStyle(),
                            inputDecorationTheme:
                                appDropdownInputDecorationTheme()
                                    .copyWith(fillColor: Colors.white),
                            onSelected: (v) {
                              if (v == null) return;
                              setState(() {
                                _rowsPerPage = v;
                                _currentPage = 1;
                              });
                            },
                            dropdownMenuEntries: [
                              for (final n in _rowsPerPageOptions)
                                DropdownMenuEntry<int>(
                                    value: n, label: '$n'),
                            ],
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: page <= 1
                                ? null
                                : () =>
                                    setState(() => _currentPage = page - 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGold
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.primaryGold
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '$page / $totalPages',
                              style: GoogleFonts.assistant(
                                color: AppTheme.primaryGold,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: page >= totalPages
                                ? null
                                : () =>
                                    setState(() => _currentPage = page + 1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        ],
                      ),
                    ),
                    ),
                ],
              ),
              if (_busyQuoteId != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.18),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          '${l10n?.tr('error') ?? 'Error'}: $e',
          style: GoogleFonts.assistant(color: AppTheme.error),
        ),
      ),
    );
  }
}
