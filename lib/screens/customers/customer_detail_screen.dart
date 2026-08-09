import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../models/inventory_item.dart';
import '../../models/quote.dart';
import '../../models/quote_item.dart';
import '../../providers/providers.dart';
import '../../services/quote_pdf_service.dart';
import '../../services/whatsapp_service.dart';
import '../../theme/order_status_colors.dart';
import '../orders/order_form_screen.dart';
import '../payments/payments_screen.dart';
import 'customers_screen.dart';

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

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  late Customer _customer;
  bool _deletingCustomer = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _deleteCustomer(AppLocalizations? l10n) async {
    if (_deletingCustomer) return;

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
            'deleteCustomerConfirm',
            en: 'Delete ${_customer.cardName}?',
            he: 'למחוק את ${_customer.cardName}?',
            ar: 'حذف ${_customer.cardName}؟',
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

    setState(() => _deletingCustomer = true);
    try {
      await ref.read(customerServiceProvider).delete(_customer.id);
      ref.invalidate(customersProvider);
      ref.invalidate(customerOrdersProvider(_customer.id));
      ref.invalidate(customerPaymentsProvider(_customer.id));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(
              context,
              l10n,
              'customerDeleted',
              en: 'Customer deleted',
              he: 'הלקוח נמחק',
              ar: 'تم حذف العميل',
            ),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n?.tr('error') ?? 'Error'}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingCustomer = false);
    }
  }

  String? _resolveCustomerWhatsAppPhone(AppLocalizations? l10n) {
    if (_customer.phones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.tr('noPhone') ?? 'No phone number available'),
          backgroundColor: AppTheme.error,
        ),
      );
      return null;
    }
    String phone = _customer.phones.first.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('0')) {
      phone = '972${phone.substring(1)}';
    } else if (!phone.startsWith('972')) {
      phone = '972$phone';
    }
    return phone;
  }

  Future<void> _sendWhatsAppPayload(
    BuildContext context,
    AppLocalizations? l10n,
    String phone,
    String message,
  ) async {
    final result = await WhatsAppService.sendMessage(phone, message);
    if (!context.mounted) return;
    if (result) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.tr('messageSent') ?? 'Message sent'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(l10n?.tr('whatsappError') ?? 'Could not send WhatsApp'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _sendPaymentsReport(
      BuildContext context, AppLocalizations? l10n) async {
    final phone = _resolveCustomerWhatsAppPhone(l10n);
    if (phone == null) return;

    final code = Localizations.localeOf(context).languageCode;
    final payments =
        await ref.read(customerPaymentsProvider(_customer.id).future);
    final message =
        _buildPaymentsReportMessage(languageCode: code, payments: payments);
    if (!context.mounted) return;
    await _sendWhatsAppPayload(context, l10n, phone, message);
  }

  Future<void> _sendOrdersReport(
      BuildContext context, AppLocalizations? l10n) async {
    final phone = _resolveCustomerWhatsAppPhone(l10n);
    if (phone == null) return;

    final code = Localizations.localeOf(context).languageCode;
    final orders = await ref
        .read(customerOrdersWithItemsProvider(_customer.id).future);
    final message =
        _buildOrdersReportMessage(languageCode: code, orders: orders);
    if (!context.mounted) return;
    await _sendWhatsAppPayload(context, l10n, phone, message);
  }

  String _greeting(String lang) {
    final name = _customer.customerName.trim().isNotEmpty
        ? _customer.customerName
        : _customer.cardName;
    return switch (lang) {
      'he' => 'שלום $name,',
      'ar' => 'مرحبًا $name،',
      _ => 'Hello $name,',
    };
  }

  String _normalizeLang(String code) =>
      (code == 'he' || code == 'ar') ? code : 'en';

  String _buildPaymentsReportMessage({
    required String languageCode,
    required List<Payment> payments,
  }) {
    final lang = _normalizeLang(languageCode);
    final money = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd/MM/yyyy');

    final accountHeader = switch (lang) {
      'he' => '💳 דוח חשבון:',
      'ar' => '💳 تقرير الحساب:',
      _ => '💳 Account report:',
    };
    final paymentsListHeader = switch (lang) {
      'he' => 'תשלומים אחרונים:',
      'ar' => 'الدفعات الأخيرة:',
      _ => 'Recent payments:',
    };
    final noPaymentsLine = switch (lang) {
      'he' => 'לא נרשמו תשלומים.',
      'ar' => 'لا توجد دفعات مسجلة.',
      _ => 'No payments on record.',
    };
    final totalBilledLabel = switch (lang) {
      'he' => 'סה"כ לחיוב',
      'ar' => 'إجمالي المستحق',
      _ => 'Total billed',
    };
    final paidLabel = switch (lang) {
      'he' => 'שולם',
      'ar' => 'المدفوع',
      _ => 'Paid',
    };
    final remainingLabel = switch (lang) {
      'he' => 'נשאר',
      'ar' => 'المتبقي',
      _ => 'Remaining',
    };
    final accountStatusLabel = switch (lang) {
      'he' => 'מצב החשבון',
      'ar' => 'حالة الحساب',
      _ => 'Account status',
    };

    final totalPaid =
        payments.fold<double>(0, (sum, p) => sum + p.amount);
    final remaining = _customer.remainingDebt;
    final totalBilled = totalPaid + remaining;

    final lines = <String>[
      accountHeader,
      '$totalBilledLabel: ₪${money.format(totalBilled)}',
      '$paidLabel: ₪${money.format(totalPaid)}',
      '$remainingLabel: ₪${money.format(remaining)}',
      '',
    ];
    if (payments.isNotEmpty) {
      lines.add(paymentsListHeader);
      final sorted = [...payments]..sort((a, b) => b.date.compareTo(a.date));
      for (final p in sorted) {
        lines.add(
            '• ${dateFmt.format(p.date)} - ₪${money.format(p.amount)} (${_paymentTypeLabel(p.type, lang)})');
      }
    } else {
      lines.add(noPaymentsLine);
    }
    lines.add('');
    lines.add(
        '$accountStatusLabel: ${_accountStatusText(_customer.remainingDebt, lang, money)}');

    return [_greeting(lang), lines.join('\n')].join('\n\n');
  }

  String _buildOrdersReportMessage({
    required String languageCode,
    required List<Order> orders,
  }) {
    final lang = _normalizeLang(languageCode);
    final money = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd/MM/yyyy');

    final ordersHeader = switch (lang) {
      'he' => '📋 דוח הזמנות פתוחות:',
      'ar' => '📋 تقرير الطلبات المفتوحة:',
      _ => '📋 Open orders report:',
    };
    final orderLabel = switch (lang) {
      'he' => 'הזמנה',
      'ar' => 'طلب',
      _ => 'Order',
    };
    final qtyLabel = switch (lang) {
      'he' => 'כמות',
      'ar' => 'الكمية',
      _ => 'Qty',
    };
    final extrasLabel = switch (lang) {
      'he' => 'תוספת',
      'ar' => 'إضافة',
      _ => 'Add-on',
    };
    final perUnitLabel = switch (lang) {
      'he' => 'ליח׳',
      'ar' => 'للوحدة',
      _ => 'each',
    };
    final assemblyLineLabel = switch (lang) {
      'he' => 'התקנה / הרכבה',
      'ar' => 'تركيب',
      _ => 'Installation',
    };
    final subtotalLabel = switch (lang) {
      'he' => 'סכום ביניים',
      'ar' => 'المجموع الفرعي',
      _ => 'Subtotal',
    };
    final vatLabel = switch (lang) {
      'he' => 'מע״מ 18%',
      'ar' => 'ض.ق.م 18٪',
      _ => 'VAT 18%',
    };
    final discountLabel = switch (lang) {
      'he' => 'הנחה',
      'ar' => 'خصم',
      _ => 'Discount',
    };
    final finalTotalLabel = switch (lang) {
      'he' => 'סה״כ סופי (כולל מע״מ)',
      'ar' => 'الإجمالي النهائي (شامل الضريبة)',
      _ => 'Final total (incl. VAT)',
    };
    final grandTotalLabel = switch (lang) {
      'he' => 'סה״כ כולל לתשלום',
      'ar' => 'الإجمالي الشامل المستحق',
      _ => 'Grand total due',
    };
    final noOrdersLine = switch (lang) {
      'he' => 'אין הזמנות פתוחות כרגע.',
      'ar' => 'لا توجد طلبات مفتوحة حاليًا.',
      _ => 'No open orders at this time.',
    };

    final openOrders = orders.where((o) =>
        o.status != OrderStatus.canceled &&
        o.status != OrderStatus.handled &&
        o.status != OrderStatus.delivered).toList();

    if (openOrders.isEmpty) {
      return [_greeting(lang), '$ordersHeader\n$noOrdersLine'].join('\n\n');
    }

    openOrders.sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    final blocks = <String>[];
    double grandTotal = 0;
    for (final o in openOrders) {
      grandTotal += o.totalPrice;
      final dateStr =
          o.createdAt != null ? ' - ${dateFmt.format(o.createdAt!)}' : '';
      final orderNo = o.orderNumber != null ? '#${o.orderNumber}' : '';
      final lines = <String>[
        '──────────',
        '$orderLabel $orderNo$dateStr',
        _statusLabel(o.status, lang),
      ];

      double itemsSubtotal = 0;
      for (final it in o.items) {
        final lineTotal = (it.price + it.extrasPrice) * it.quantity;
        itemsSubtotal += lineTotal;
        lines.add(
          '• ${it.name} ($qtyLabel ${formatQty(it.quantity)} × ₪${money.format(it.price)}) = ₪${money.format(it.price * it.quantity)}',
        );
        final hasExtras =
            (it.extras != null && it.extras!.trim().isNotEmpty) ||
                it.extrasPrice > 0;
        if (hasExtras) {
          final extrasName = (it.extras != null && it.extras!.trim().isNotEmpty)
              ? ' "${it.extras!.trim()}"'
              : '';
          lines.add(
            '   ➕ $extrasLabel$extrasName: ₪${money.format(it.extrasPrice)} $perUnitLabel = ₪${money.format(it.extrasPrice * it.quantity)}',
          );
        }
      }

      final subtotalExVat = itemsSubtotal + o.assemblyPrice;
      if (o.assemblyPrice > 0) {
        lines.add('• $assemblyLineLabel: ₪${money.format(o.assemblyPrice)}');
      }
      lines.add('$subtotalLabel: ₪${money.format(subtotalExVat)}');
      if (o.vatEnabled) {
        final vatAmount = subtotalExVat * 0.18;
        lines.add('$vatLabel: ₪${money.format(vatAmount)}');
      }
      if (o.discountPercentage > 0) {
        if (o.discountType == 'fixed_amount') {
          lines.add(
            '$discountLabel: -₪${money.format(o.discountPercentage)}',
          );
        } else {
          final totalWithVat =
              o.vatEnabled ? subtotalExVat * 1.18 : subtotalExVat;
          final discountAmount =
              totalWithVat * (o.discountPercentage / 100);
          lines.add(
            '$discountLabel ${formatQty(o.discountPercentage)}%: -₪${money.format(discountAmount)}',
          );
        }
      }
      lines.add('$finalTotalLabel: ₪${money.format(o.totalPrice)}');
      blocks.add(lines.join('\n'));
    }

    blocks.add('──────────');
    blocks.add('$grandTotalLabel: ₪${money.format(grandTotal)}');

    return [
      _greeting(lang),
      ordersHeader,
      blocks.join('\n'),
    ].join('\n\n');
  }

  String _statusLabel(OrderStatus s, String lang) {
    switch (lang) {
      case 'he':
        switch (s) {
          case OrderStatus.active: return 'פעיל';
          case OrderStatus.preparing: return 'בהכנה';
          case OrderStatus.sentToSupplier: return 'נשלח לספק';
          case OrderStatus.inAssembly: return 'בהרכבה';
          case OrderStatus.awaitingShipping: return 'ממתין למשלוח';
          case OrderStatus.handled: return 'טופל';
          case OrderStatus.delivered: return 'נמסר';
          case OrderStatus.canceled: return 'בוטל';
        }
      case 'ar':
        switch (s) {
          case OrderStatus.active: return 'نشِط';
          case OrderStatus.preparing: return 'قيد التحضير';
          case OrderStatus.sentToSupplier: return 'أُرسل للمورد';
          case OrderStatus.inAssembly: return 'قيد التركيب';
          case OrderStatus.awaitingShipping: return 'بانتظار الشحن';
          case OrderStatus.handled: return 'تمت المعالجة';
          case OrderStatus.delivered: return 'تم التسليم';
          case OrderStatus.canceled: return 'ملغي';
        }
      default:
        return s.dbValue;
    }
  }

  String _paymentTypeLabel(PaymentType t, String lang) {
    switch (lang) {
      case 'he':
        switch (t) {
          case PaymentType.cash: return 'מזומן';
          case PaymentType.credit: return 'אשראי';
          case PaymentType.check: return 'צ\'ק';
          case PaymentType.transfer: return 'העברה';
        }
      case 'ar':
        switch (t) {
          case PaymentType.cash: return 'نقدًا';
          case PaymentType.credit: return 'بطاقة';
          case PaymentType.check: return 'شيك';
          case PaymentType.transfer: return 'تحويل';
        }
      default:
        return t.dbValue;
    }
  }

  String _accountStatusText(double debt, String lang, NumberFormat money) {
    if (debt == 0) {
      return switch (lang) {
        'he' => 'סודר',
        'ar' => 'مسوّى',
        _ => 'Settled',
      };
    }
    if (debt > 0) {
      final amt = '₪${money.format(debt)}';
      return switch (lang) {
        'he' => 'חוב $amt',
        'ar' => 'دين $amt',
        _ => 'Debt $amt',
      };
    }
    final amt = '₪${money.format(debt.abs())}';
    return switch (lang) {
      'he' => 'יתרה $amt',
      'ar' => 'رصيد $amt',
      _ => 'Credit $amt',
    };
  }

  void _openEditDialog(AppLocalizations? l10n) {
    showDialog<Customer>(
      context: context,
      builder: (ctx) => CustomerFormDialog(
        ref: ref,
        l10n: l10n,
        existingCustomer: _customer,
        onCustomerSaved: (updated) {
          setState(() => _customer = updated);
        },
      ),
    );
  }

  Future<void> _openQuoteForm(
      BuildContext context, AppLocalizations? l10n) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _QuoteFormScreen(customer: _customer),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(customerQuotesProvider(_customer.id));
    }
  }

  void _goToOrdersFiltered() {
    ref.read(ordersCustomerFilterProvider.notifier).setFilter(_customer);
    ref.read(selectedNavIndexProvider.notifier).setIndex(2);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final latestCustomers = ref.watch(customersProvider).value;
    if (latestCustomers != null) {
      final latest = latestCustomers.where((c) => c.id == _customer.id).firstOrNull;
      if (latest != null) _customer = latest;
    }
    final ordersAsync = ref.watch(customerOrdersProvider(_customer.id));
    final paymentsAsync = ref.watch(customerPaymentsProvider(_customer.id));
    final quotesAsync = ref.watch(customerQuotesProvider(_customer.id));

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          _customer.cardName,
          style: GoogleFonts.assistant(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppTheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: AppTheme.onSurface),
        actions: const [SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(customersProvider);
          ref.invalidate(customerOrdersProvider(_customer.id));
          ref.invalidate(customerPaymentsProvider(_customer.id));
          ref.invalidate(customerQuotesProvider(_customer.id));
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Two columns once there is room; keep quotes on the physical
            // right even when the app Directionality is RTL.
            final isWide = constraints.maxWidth > 700;

            final notesCard = (_customer.notes != null &&
                    _customer.notes!.isNotEmpty)
                ? _EditableNotesCard(
                    customerId: _customer.id,
                    initialNotes: _customer.notes ?? '',
                    l10n: l10n,
                    onSaved: (next) {
                      setState(() => _customer = _customer.copyWith(notes: next));
                    },
                  )
                : _EditableNotesCard(
                    customerId: _customer.id,
                    initialNotes: '',
                    l10n: l10n,
                    onSaved: (next) {
                      setState(() => _customer = _customer.copyWith(notes: next));
                    },
                  );

            // Left: orders + payments (recent activity).
            final activityColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _OrdersListSection(
                  ordersAsync: ordersAsync,
                  l10n: l10n,
                  onViewAll: _goToOrdersFiltered,
                ),
                const SizedBox(height: 32),
                _PaymentsListSection(
                  customer: _customer,
                  paymentsAsync: paymentsAsync,
                  l10n: l10n,
                ),
              ],
            );

            // Right: existing contact/notes sidebar, with quotes under them.
            final sidebarColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ContactInfoCard(customer: _customer, l10n: l10n),
                const SizedBox(height: 24),
                notesCard,
                const SizedBox(height: 24),
                _QuotesListSection(
                  customer: _customer,
                  quotesAsync: quotesAsync,
                  l10n: l10n,
                ),
              ],
            );

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _HeroBanner(
                    customer: _customer,
                    l10n: l10n,
                    ordersAsync: ordersAsync,
                    onNewOrder: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderFormScreen(initialCustomer: _customer),
                        ),
                      );
                    },
                    onSendQuote: () => _openQuoteForm(context, l10n),
                    onEditDetails: () => _openEditDialog(l10n),
                    onSendPaymentsReport: () =>
                        _sendPaymentsReport(context, l10n),
                    onSendOrdersReport: () =>
                        _sendOrdersReport(context, l10n),
                    onDeleteCustomer: () => _deleteCustomer(l10n),
                    deletingCustomer: _deletingCustomer,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    isWide ? 32 : 24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: isWide
                        ? Row(
                            textDirection: TextDirection.ltr,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(flex: 6, child: activityColumn),
                              const SizedBox(width: 28),
                              Expanded(flex: 5, child: sidebarColumn),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              sidebarColumn,
                              const SizedBox(height: 28),
                              activityColumn,
                            ],
                          ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Hero Banner ─────────────────────────────────────────────────────────────

class _HeroBanner extends ConsumerStatefulWidget {
  final Customer customer;
  final AppLocalizations? l10n;
  final AsyncValue<List<Order>> ordersAsync;
  final VoidCallback onNewOrder;
  final VoidCallback onSendQuote;
  final VoidCallback onEditDetails;
  final VoidCallback onSendPaymentsReport;
  final VoidCallback onSendOrdersReport;
  final VoidCallback onDeleteCustomer;
  final bool deletingCustomer;

  const _HeroBanner({
    required this.customer,
    required this.l10n,
    required this.ordersAsync,
    required this.onNewOrder,
    required this.onSendQuote,
    required this.onEditDetails,
    required this.onSendPaymentsReport,
    required this.onSendOrdersReport,
    required this.onDeleteCustomer,
    required this.deletingCustomer,
  });

  @override
  ConsumerState<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<_HeroBanner> {
  bool _isUpdatingPhoto = false;

  Future<void> _deletePhotoIfExists() async {
    setState(() => _isUpdatingPhoto = true);
    try {
      await ref.read(customerServiceProvider).deletePhoto(widget.customer.id);
      ref.invalidate(customersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPhoto = false);
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    final bytes = await xFile.readAsBytes();

    setState(() => _isUpdatingPhoto = true);
    try {
      final url = await ref
          .read(customerServiceProvider)
          .uploadPhoto(widget.customer.id, bytes);
      await ref
          .read(customerServiceProvider)
          .update(widget.customer.id, {'image_url': url});
      ref.invalidate(customersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPhoto = false);
    }
  }

  Future<void> _showPhotoPicker() async {
    final l10n = widget.l10n;
    final hasExisting = widget.customer.imageUrl != null &&
        widget.customer.imageUrl!.isNotEmpty;

    if (_isUpdatingPhoto) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        Widget tile({
          required IconData icon,
          required String title,
          required String value,
          Color? color,
        }) {
          return ListTile(
            leading: Icon(icon, color: color ?? AppTheme.secondary),
            title: Text(
              title,
              style: GoogleFonts.assistant(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color ?? AppTheme.onSurface,
              ),
            ),
            onTap: () => Navigator.pop(ctx, value),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
      child: Column(
              mainAxisSize: MainAxisSize.min,
        children: [
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: 18, end: 18, top: 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n?.tr('selectImageSource') ?? 'Select Image Source',
                      style: GoogleFonts.assistant(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                tile(
                  icon: Icons.camera_alt_outlined,
                  title: l10n?.tr('camera') ?? 'Camera',
                  value: 'camera',
                ),
                tile(
                  icon: Icons.photo_library_outlined,
                  title: l10n?.tr('gallery') ?? 'Gallery',
                  value: 'gallery',
                ),
                if (hasExisting) ...[
                  const Divider(height: 10),
                  tile(
                    icon: Icons.delete_outline,
                    title: l10n?.tr('deletePhoto') ?? 'Delete Photo',
                    value: 'delete',
                    color: AppTheme.error,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'camera':
        await _pickAndUpload(ImageSource.camera);
        break;
      case 'gallery':
        await _pickAndUpload(ImageSource.gallery);
        break;
      case 'delete':
        await _deletePhotoIfExists();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final ordersAsync = widget.ordersAsync;
    final l10n = widget.l10n;
    final onEditDetails = widget.onEditDetails;
    final onSendPaymentsReport = widget.onSendPaymentsReport;
    final onSendOrdersReport = widget.onSendOrdersReport;
    final onNewOrder = widget.onNewOrder;
    final onSendQuote = widget.onSendQuote;
    final onDeleteCustomer = widget.onDeleteCustomer;
    final deletingCustomer = widget.deletingCustomer;

    var isVip = false;
    if (ordersAsync.hasValue) {
      final completed = ordersAsync.value!
          .where((o) => o.status == OrderStatus.delivered)
          .length;
      if (completed >= 5) isVip = true;
    }

    final hasDebt = customer.remainingDebt > 0;
    final hasPhoto =
        customer.imageUrl != null && customer.imageUrl!.isNotEmpty;

    ButtonStyle actionStyle(Color rim, Color fg) => ElevatedButton.styleFrom(
          backgroundColor: AppTheme.surfaceContainerLowest,
          foregroundColor: fg,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(48, 46),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: rim.withValues(alpha: 0.95), width: 1.5),
          ),
        );

    Widget avatar = GestureDetector(
      onTap: _isUpdatingPhoto ? null : _showPhotoPicker,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.surfaceContainerLowest,
                width: 3,
              ),
              color: AppTheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _isUpdatingPhoto
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : hasPhoto
                    ? CachedNetworkImage(
                        imageUrl: customer.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Text(
                          customer.cardName.isNotEmpty
                              ? customer.cardName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.assistant(
                            color: AppTheme.secondary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLowest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: 14,
                  color: AppTheme.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: 168,
            width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
            decoration: BoxDecoration(
                        image: hasPhoto
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(
                                  customer.imageUrl!,
                                ),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.black.withValues(alpha: 0.45),
                                  BlendMode.darken,
                                ),
                              )
                            : null,
                        gradient: hasPhoto
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFFE8DED5),
                                  Color(0xFFC9B8A8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: hasPhoto ? const Color(0xFF1B2430) : null,
                      ),
                    ),
                    if (hasPhoto)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.05),
                              Colors.black.withValues(alpha: 0.65),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Icon(
                          Icons.home_work_outlined,
                          size: 72,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: IconButton.filled(
                        onPressed: _isUpdatingPhoto ? null : _showPhotoPicker,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceContainerLowest
                              .withValues(alpha: 0.94),
                          foregroundColor: AppTheme.secondary,
                          elevation: 0,
                          padding: const EdgeInsets.all(10),
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.wallpaper_rounded, size: 22),
                        tooltip: l10n?.tr('takePhoto') ?? 'Background photo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 18),
              Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                    Text(
                  customer.cardName,
                      style: GoogleFonts.assistant(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                  customer.customerName,
                      style: GoogleFonts.assistant(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    if (customer.remainingDebt > 0 ||
                        isVip) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isVip)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFD4A300),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                        _trOrLocale(
                                          context,
                                          l10n,
                                          'vipBadge',
                                          en: 'VIP',
                                          he: 'V.I.P',
                                          ar: 'VIP',
                                        ),
                                    style: GoogleFonts.assistant(
                                      color: const Color(0xFFB8860B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (hasDebt)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color:
                                      AppTheme.error.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                  Icons.account_balance_wallet_outlined,
                                    color: AppTheme.error,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                        '${_trOrLocale(
                                          context,
                                          l10n,
                                          'openDebtLabel',
                                          en: 'Open balance',
                                          he: 'חוב פתוח',
                                          ar: 'رصيد مفتوح',
                                        )} · ₪${customer.remainingDebt.toStringAsFixed(0)}',
                                    style: GoogleFonts.assistant(
                                      color: AppTheme.error,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                ),
              ],
            ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: onEditDetails,
                        style: actionStyle(
                          AppTheme.outlineVariant.withValues(alpha: 0.55),
                          AppTheme.onSurface,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'editCustomerDetails',
                            en: 'Edit details',
                            he: 'עריכת פרטים',
                            ar: 'تعديل البيانات',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: onSendPaymentsReport,
                        style: actionStyle(AppTheme.success, AppTheme.success),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'sendPaymentsReport',
                            en: 'Send payments report',
                            he: 'שלח דוח תשלומים',
                            ar: 'إرسال تقرير الدفعات',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: onSendOrdersReport,
                        style: actionStyle(AppTheme.success, AppTheme.success),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'sendOrdersReport',
                            en: 'Send orders report',
                            he: 'שלח דוח הזמנות',
                            ar: 'إرسال تقرير الطلبات',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => showPaymentDialog(
                          context,
                          ref,
                          l10n,
                          initialCustomer: customer,
                        ),
                        style: actionStyle(
                          AppTheme.secondary,
                          AppTheme.secondary,
                        ),
                        icon: const Icon(Icons.payment_rounded, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'newPayment',
                            en: 'New payment',
                            he: 'תשלום חדש',
                            ar: 'دفعة جديدة',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: onSendQuote,
                        style: actionStyle(
                          AppTheme.secondary,
                          AppTheme.secondary,
                        ),
                        icon: const Icon(
                            Icons.request_quote_outlined, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'sendQuote',
                            en: 'Send quote',
                            he: 'שלח הצעת מחיר',
                            ar: 'إرسال عرض سعر',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: onNewOrder,
                        style:
                            actionStyle(AppTheme.primary, AppTheme.primary),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'newOrder',
                            en: 'New order',
                            he: 'הזמנה חדשה',
                            ar: 'طلب جديد',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: deletingCustomer ? null : onDeleteCustomer,
                        style: actionStyle(AppTheme.error, AppTheme.error),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(
                          _trOrLocale(
                            context,
                            l10n,
                            'delete',
                            en: 'Delete',
                            he: 'מחק',
                            ar: 'حذف',
                          ),
                          style: GoogleFonts.assistant(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Builder(
                builder: (context) {
                  final debt = customer.remainingDebt;
                  final bool inDebt = debt > 0;
                  final bool overpaid = debt < 0;
                  final double amountToShow =
                      overpaid ? (-debt) : debt; // display as positive

                  final Color textColor = inDebt
                      ? AppTheme.error
                      : (overpaid ? AppTheme.success : AppTheme.onSurface);
                  final Color bgColor = inDebt
                      ? AppTheme.error.withValues(alpha: 0.12)
                      : (overpaid
                          ? AppTheme.success.withValues(alpha: 0.12)
                          : AppTheme.surfaceContainerHighest
                              .withValues(alpha: 0.35));
                  final Color borderColor = inDebt
                      ? AppTheme.error.withValues(alpha: 0.35)
                      : (overpaid
                          ? AppTheme.success.withValues(alpha: 0.35)
                          : AppTheme.outlineVariant.withValues(alpha: 0.22));

                  final String label = inDebt
                      ? _trOrLocale(
                          context,
                          l10n,
                          'openDebtLabel',
                          en: 'Open balance',
                          he: 'חוב פתוח',
                          ar: 'رصيد مفتوح',
                        )
                      : (overpaid
                          ? _trOrLocale(
                              context,
                              l10n,
                              'balanceOverpaidLabel',
                              en: 'Overpaid',
                              he: 'עודף ששולם',
                              ar: 'مدفوعات زائدة',
                            )
                          : _trOrLocale(
                              context,
                              l10n,
                              'balanceZeroLabel',
                              en: 'Balance due',
                              he: 'יתרת לתשלום',
                              ar: 'الحد المستحق',
                            ));

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      '$label · ₪${amountToShow.toStringAsFixed(0)}',
                      style: GoogleFonts.assistant(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Contact Info Card ───────────────────────────────────────────────────────

class _ContactInfoCard extends StatelessWidget {
  final Customer customer;
  final AppLocalizations? l10n;

  const _ContactInfoCard({required this.customer, required this.l10n});

  Future<void> _dial(
    BuildContext context,
    AppLocalizations? l10n,
    String raw,
  ) async {
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.tr('error') ?? 'Error'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openMaps(BuildContext context, String query) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    return _SidebarCard(
      title: _trOrLocale(
        context,
        l10n,
        'contactDetails',
        en: 'Contact',
        he: 'פרטי התקשרות',
        ar: 'بيانات الاتصال',
      ),
      icon: Icons.contact_page_outlined,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ContactRow(
            icon: Icons.person_outline_rounded,
            text: customer.customerName,
            onTap: () {},
          ),
          if (customer.phones.isNotEmpty) const SizedBox(height: 14),
          if (customer.phones.isNotEmpty)
            _ContactRow(
              icon: Icons.phone_outlined,
              text: customer.phones.join(', '),
              onTap: () => _dial(context, l10n, customer.phones.first),
            ),
          if (customer.phones.isNotEmpty) const SizedBox(height: 14),
          if (customer.location != null && customer.location!.isNotEmpty)
            _ContactRow(
              icon: Icons.location_on_outlined,
              text: customer.location!,
              onTap: () => _openMaps(context, customer.location!),
            ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _ContactRow(
      {required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 22, color: AppTheme.secondary),
              const SizedBox(width: 14),
        Expanded(
          child: Text(
                  text,
                  textAlign: TextAlign.start,
                  style: GoogleFonts.assistant(
                    fontSize: 15,
                    color: AppTheme.onSurface,
              fontWeight: FontWeight.w600,
                    height: 1.4,
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

// ─── Notes Card ─────────────────────────────────────────────────────────────

class _EditableNotesCard extends ConsumerStatefulWidget {
  final String customerId;
  final String initialNotes;
  final AppLocalizations? l10n;
  final ValueChanged<String> onSaved;

  const _EditableNotesCard({
    required this.customerId,
    required this.initialNotes,
    required this.l10n,
    required this.onSaved,
  });

  @override
  ConsumerState<_EditableNotesCard> createState() => _EditableNotesCardState();
}

class _EditableNotesCardState extends ConsumerState<_EditableNotesCard> {
  late final TextEditingController _ctrl;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNotes);
  }

  @override
  void didUpdateWidget(covariant _EditableNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.initialNotes != widget.initialNotes) {
      _ctrl.text = widget.initialNotes;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final username = ref.read(currentUsernameProvider);
    final next = _ctrl.text.trim();
    try {
      await ref.read(customerServiceProvider).update(
        widget.customerId,
        {'notes': next, 'updated_by': username},
      );
      ref.invalidate(customersProvider);
      if (mounted) {
        setState(() => _editing = false);
        widget.onSaved(next);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.l10n?.tr('error') ?? 'Error'}: $e'),
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
    return _SidebarCard(
      title: _trOrLocale(
        context,
        l10n,
        'systemNotes',
        en: 'Notes',
        he: 'הערות מערכת',
        ar: 'ملاحظات النظام',
      ),
      icon: Icons.sticky_note_2_outlined,
      trailing: IconButton(
        tooltip: _editing ? (l10n?.tr('cancel') ?? 'Cancel') : (l10n?.tr('edit') ?? 'Edit'),
        onPressed: _saving
            ? null
            : () {
                setState(() {
                  if (_editing) {
                    _ctrl.text = widget.initialNotes;
                  }
                  _editing = !_editing;
                });
              },
        icon: Icon(
          _editing ? Icons.close_rounded : Icons.edit_outlined,
          color: AppTheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            enabled: _editing && !_saving,
            maxLines: 4,
            style: GoogleFonts.assistant(
              fontSize: 14,
              color: AppTheme.onSurface,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.secondaryContainer.withValues(alpha: 0.20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AppTheme.outlineVariant.withValues(alpha: 0.22),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AppTheme.outlineVariant.withValues(alpha: 0.22),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppTheme.secondary, width: 1.8),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _ctrl.text = widget.initialNotes;
                            _editing = false;
                          });
                        },
                  child: Text(l10n?.tr('cancel') ?? 'Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: AppTheme.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n?.tr('save') ?? 'Save'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Widget? titleBadge;
  /// When non-null, shows an expand/collapse control in the header.
  final bool? expanded;
  final VoidCallback? onToggleExpanded;

  const _SidebarCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.titleBadge,
    this.expanded,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: AppTheme.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.start,
                      style: GoogleFonts.assistant(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        height: 3,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.secondary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (titleBadge != null) ...[
                const SizedBox(width: 8),
                titleBadge!,
              ],
              if (expanded != null && onToggleExpanded != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: expanded!
                      ? _trOrLocale(context, null, 'collapse',
                          en: 'Collapse', he: 'כווץ', ar: 'طي')
                      : _trOrLocale(context, null, 'expand',
                          en: 'Expand', he: 'הרחב', ar: 'توسيع'),
                  onPressed: onToggleExpanded,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    expanded!
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ─── Orders List Section ────────────────────────────────────────────────────

class _OrdersListSection extends StatefulWidget {
  final AsyncValue<List<Order>> ordersAsync;
  final AppLocalizations? l10n;
  final VoidCallback onViewAll;

  const _OrdersListSection({
    required this.ordersAsync,
    required this.l10n,
    required this.onViewAll,
  });

  @override
  State<_OrdersListSection> createState() => _OrdersListSectionState();
}

class _OrdersListSectionState extends State<_OrdersListSection> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  AppLocalizations? get l10n => widget.l10n;

  Widget _countBadge(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.secondary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        n.toString(),
        style: GoogleFonts.assistant(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.secondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _trOrLocale(
      context,
      l10n,
      'orderHistory',
      en: 'Order history',
      he: 'היסטוריית הזמנות',
      ar: 'سجل الطلبات',
    );
    final viewAllLabel = _trOrLocale(
      context,
      l10n,
      'viewAll',
      en: 'View all',
      he: 'צפה בכולם',
      ar: 'عرض الكل',
    );

    return widget.ordersAsync.when(
      data: (orders) {
        final canToggle = orders.length > _collapsedCount;
        final visible = (!_expanded && canToggle)
            ? orders.take(_collapsedCount).toList()
            : orders;

        return _SidebarCard(
          title: title,
          icon: Icons.receipt_long_rounded,
          titleBadge: orders.isEmpty ? null : _countBadge(orders.length),
          expanded: canToggle ? _expanded : null,
          onToggleExpanded: canToggle
              ? () => setState(() => _expanded = !_expanded)
              : null,
          trailing: TextButton(
            onPressed: widget.onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              viewAllLabel,
              style: GoogleFonts.assistant(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          child: orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _trOrLocale(
                      context,
                      l10n,
                      'noOrdersForCustomer',
                      en: 'This customer has no orders yet.',
                      he: 'ללקוח זה אין עדיין הזמנות.',
                      ar: 'لا توجد طلبات لهذا العميل بعد.',
                    ),
                    textAlign: TextAlign.start,
                    style: GoogleFonts.assistant(
                      color: AppTheme.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 1,
                          color: AppTheme.outlineVariant
                              .withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, index) {
                          return _OrderRow(
                              order: visible[index], l10n: l10n);
                        },
                      ),
                    ),
                    if (canToggle) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _expanded
                                ? _trOrLocale(context, l10n, 'showLess',
                                    en: 'Show less',
                                    he: 'הצג פחות',
                                    ar: 'عرض أقل')
                                : _trOrLocale(context, l10n, 'showMore',
                                    en: 'Show more (${orders.length - _collapsedCount})',
                                    he: 'הצג עוד (${orders.length - _collapsedCount})',
                                    ar: 'عرض المزيد (${orders.length - _collapsedCount})'),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
      loading: () => _SidebarCard(
        title: title,
        icon: Icons.receipt_long_rounded,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _SidebarCard(
        title: title,
        icon: Icons.receipt_long_rounded,
        child: Text(
          '${l10n?.tr('error') ?? 'Error'}: $e',
          textAlign: TextAlign.start,
          style: GoogleFonts.assistant(color: AppTheme.error),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Order order;
  final AppLocalizations? l10n;

  const _OrderRow({required this.order, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final statusColor = orderStatusColor(order.status);
    final statusLabel =
        orderStatusLocalizedLabel(order.status, l10n);
    final created = order.createdAt ?? DateTime.now();
    final dateStr = AppDateFormat.table(created);
    final bodiesWord = _trOrLocale(
      context,
      l10n,
      'bodies',
      en: 'items',
      he: 'גופים',
      ar: 'وحدات',
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderFormScreen(orderId: order.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.secondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '#${order.orderNumber ?? order.id.substring(0, 6)}',
                      textAlign: TextAlign.start,
                      style: GoogleFonts.assistant(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.items.length} $bodiesWord · $dateStr',
                      textAlign: TextAlign.start,
                      style: GoogleFonts.assistant(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '₪${order.totalPrice.toStringAsFixed(0)}',
                    textAlign: TextAlign.end,
                    style: GoogleFonts.assistant(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
          decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                      ),
          ),
          child: Text(
                      statusLabel,
                      style: GoogleFonts.assistant(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
              color: statusColor,
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
  }
}

// ─── Payments List Section ──────────────────────────────────────────────────

class _PaymentsListSection extends ConsumerWidget {
  final Customer customer;
  final AsyncValue<List<Payment>> paymentsAsync;
  final AppLocalizations? l10n;

  const _PaymentsListSection({
    required this.customer,
    required this.paymentsAsync,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _trOrLocale(
      context,
      l10n,
      'recentPaymentActivity',
      en: 'Recent payments',
      he: 'פעילות תשלומים אחרונה',
      ar: 'آخر المدفوعات',
    );
    final viewAllLabel = _trOrLocale(
      context,
      l10n,
      'viewAll',
      en: 'View all',
      he: 'צפה בכולם',
      ar: 'عرض الكل',
    );

    void goPayments() {
      ref.read(paymentsCustomerFilterProvider.notifier).setFilter(customer);
      ref.read(selectedNavIndexProvider.notifier).setIndex(4);
      Navigator.of(context).pop();
    }

    return paymentsAsync.when(
      data: (payments) {
        return _SidebarCard(
          title: title,
          icon: Icons.payments_rounded,
          trailing: TextButton(
            onPressed: goPayments,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              viewAllLabel,
              style: GoogleFonts.assistant(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          child: payments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _trOrLocale(
                      context,
                      l10n,
                      'noPaymentsForCustomer',
                      en: 'No payments recorded for this customer yet.',
                      he: 'אין תשלומים רשומים ללקוח זה.',
                      ar: 'لا توجد مدفوعات مسجلة لهذا العميل بعد.',
                    ),
                    textAlign: TextAlign.start,
                    style: GoogleFonts.assistant(
                      color: AppTheme.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.12),
                    ),
                    itemBuilder: (context, index) {
                      return _PaymentRow(
                        payment: payments[index],
                        l10n: l10n,
                      );
                    },
                  ),
                ),
        );
      },
      loading: () => _SidebarCard(
        title: title,
        icon: Icons.payments_rounded,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _SidebarCard(
        title: title,
        icon: Icons.payments_rounded,
        child: Text(
          '${l10n?.tr('error') ?? 'Error'}: $e',
          textAlign: TextAlign.start,
          style: GoogleFonts.assistant(color: AppTheme.error),
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  final AppLocalizations? l10n;

  const _PaymentRow({required this.payment, required this.l10n});

  String _typeLabel(BuildContext context) {
    switch (payment.type) {
      case PaymentType.cash:
        return _trOrLocale(
          context,
          l10n,
          'cash',
          en: 'Cash',
          he: 'מזומן',
          ar: 'نقدي',
        );
      case PaymentType.credit:
        return _trOrLocale(
          context,
          l10n,
          'credit',
          en: 'Credit',
          he: 'אשראי',
          ar: 'بطاقة ائتمان',
        );
      case PaymentType.check:
        return _trOrLocale(
          context,
          l10n,
          'check',
          en: 'Check',
          he: 'צ\'ק',
          ar: 'شيك',
        );
      case PaymentType.transfer:
        return _trOrLocale(
          context,
          l10n,
          'transfer',
          en: 'Transfer',
          he: 'העברה',
          ar: 'تحويل',
        );
    }
  }

  IconData _typeIcon() {
    switch (payment.type) {
      case PaymentType.credit:
        return Icons.credit_card_rounded;
      case PaymentType.cash:
        return Icons.payments_rounded;
      case PaymentType.check:
        return Icons.receipt_long_rounded;
      case PaymentType.transfer:
        return Icons.swap_horiz_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = AppDateFormat.table(payment.date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(_typeIcon(), color: AppTheme.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _typeLabel(context),
                  textAlign: TextAlign.start,
                  style: GoogleFonts.assistant(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  textAlign: TextAlign.start,
                  style: GoogleFonts.assistant(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+ ₪${payment.amount.toStringAsFixed(0)}',
            textAlign: TextAlign.end,
            style: GoogleFonts.assistant(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quotes List Section ────────────────────────────────────────────────────

class _QuotesListSection extends ConsumerStatefulWidget {
  final Customer customer;
  final AsyncValue<List<Quote>> quotesAsync;
  final AppLocalizations? l10n;

  const _QuotesListSection({
    required this.customer,
    required this.quotesAsync,
    required this.l10n,
  });

  @override
  ConsumerState<_QuotesListSection> createState() => _QuotesListSectionState();
}

class _QuotesListSectionState extends ConsumerState<_QuotesListSection> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  Customer get customer => widget.customer;
  AppLocalizations? get l10n => widget.l10n;

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

  String _statusLabel(BuildContext context, QuoteStatus s) {
    switch (s) {
      case QuoteStatus.sent:
        return _trOrLocale(context, l10n, 'quoteStatusSent',
            en: 'Sent', he: 'נשלחה', ar: 'مُرسل');
      case QuoteStatus.accepted:
        return _trOrLocale(context, l10n, 'quoteStatusAccepted',
            en: 'Accepted', he: 'התקבלה', ar: 'مقبول');
      case QuoteStatus.converted:
        return _trOrLocale(context, l10n, 'quoteStatusConverted',
            en: 'Converted', he: 'הומרה', ar: 'محوّل');
      case QuoteStatus.expired:
        return _trOrLocale(context, l10n, 'quoteStatusExpired',
            en: 'Expired', he: 'פגה תוקף', ar: 'منتهي الصلاحية');
    }
  }

  Future<void> _viewQuote(BuildContext context, Quote quote) async {
    final url = quote.pdfUrl?.trim() ?? '';
    if (url.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, l10n, 'quotePdfMissing',
                en: 'Quote PDF is not available.',
                he: 'קובץ הצעת המחיר אינו זמין.',
                ar: 'ملف عرض السعر غير متوفر.'),
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final title = _trOrLocale(
      context,
      l10n,
      'viewQuoteTitle',
      en: 'Quote #${quote.quoteNumber ?? ''}',
      he: 'הצעה מס׳ ${quote.quoteNumber ?? ''}',
      ar: 'عرض رقم ${quote.quoteNumber ?? ''}',
    );
    final pdfFileName = 'quote_${quote.quoteNumber ?? quote.id}.pdf';

    // Prefetch so print/share/preview share one download.
    Uint8List? pdfBytes;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      pdfBytes = response.bodyBytes;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trOrLocale(context, l10n, 'quotePdfLoadError',
                en: 'Could not load the quote PDF.',
                he: 'לא ניתן לטעון את קובץ ההצעה.',
                ar: 'تعذر تحميل ملف العرض.'),
            style: GoogleFonts.assistant(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final bytes = pdfBytes;

    Widget roundAction({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      bool primary = false,
    }) {
      final radius = BorderRadius.circular(12);
      if (primary) {
        return FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: AppTheme.onPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          backgroundColor: AppTheme.surfaceContainerLowest,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: AppTheme.primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 760,
            height: MediaQuery.sizeOf(ctx).height * 0.88,
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTheme.outlineVariant.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Header — matches app card language.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.request_quote_outlined,
                          color: AppTheme.secondary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.assistant(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: AppTheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Container(
                                height: 3,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: AppTheme.surfaceContainerHighest
                            .withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(ctx).pop(),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.close_rounded,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppTheme.outlineVariant.withValues(alpha: 0.25),
                ),
                // Preview — no built-in black action bar.
                Expanded(
                  child: ColoredBox(
                    color: AppTheme.surfaceContainerLow,
                    child: PdfPreview(
                      build: (format) async => bytes,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      useActions: false,
                      pdfFileName: pdfFileName,
                      previewPageMargin: const EdgeInsets.all(18),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppTheme.outlineVariant.withValues(alpha: 0.25),
                ),
                // Rounded action buttons matching the app.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      roundAction(
                        icon: Icons.open_in_new_rounded,
                        label: _trOrLocale(context, l10n, 'openInBrowser',
                            en: 'Open', he: 'פתח', ar: 'فتح'),
                        onPressed: () async {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                      roundAction(
                        icon: Icons.download_rounded,
                        label: _trOrLocale(context, l10n, 'download',
                            en: 'Download', he: 'הורדה', ar: 'تنزيل'),
                        onPressed: () async {
                          await Printing.sharePdf(
                            bytes: bytes,
                            filename: pdfFileName,
                          );
                        },
                      ),
                      roundAction(
                        icon: Icons.print_rounded,
                        label: _trOrLocale(context, l10n, 'print',
                            en: 'Print', he: 'הדפס', ar: 'طباعة'),
                        onPressed: () async {
                          await Printing.layoutPdf(
                            onLayout: (format) async => bytes,
                            name: pdfFileName,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _convertToOrder(
      BuildContext context, WidgetRef ref, Quote quote) async {
    final fullQuote = await ref.read(quoteServiceProvider).getById(quote.id);
    if (!context.mounted) return;

    final username = ref.read(currentUsernameProvider);
    final customers = ref.read(customersProvider).value;
    final cust =
        customers?.where((c) => c.id == fullQuote.customerId).firstOrNull;

    await ref
        .read(quoteServiceProvider)
        .updateStatus(quote.id, 'Converted', username);

    if (!context.mounted) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          initialCustomer: cust,
          initialQuoteItems: fullQuote.items,
        ),
      ),
    );

    if (context.mounted) {
      ref.invalidate(customerQuotesProvider(customer.id));
      ref.invalidate(ordersProvider);
      ref.invalidate(customerOrdersProvider(customer.id));

      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _trOrLocale(context, l10n, 'quoteConverted',
                  en: 'Quote converted to order',
                  he: 'הצעת המחיר הומרה להזמנה',
                  ar: 'تم تحويل العرض إلى طلب'),
              style: GoogleFonts.assistant(),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Widget _quoteRow(BuildContext context, WidgetRef ref, Quote quote) {
    final created = quote.createdAt ?? DateTime.now();
    final dateStr = AppDateFormat.table(created);
    final statusColor = _statusColor(quote.status);
    final statusText = _statusLabel(context, quote.status);
    final canConvert =
        quote.status == QuoteStatus.sent || quote.status == QuoteStatus.accepted;
    final hasPdf = (quote.pdfUrl ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasPdf ? () => _viewQuote(context, quote) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      AppTheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.request_quote_outlined,
                  color: AppTheme.secondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${quote.quoteNumber ?? quote.id.substring(0, 6)}',
                      style: GoogleFonts.assistant(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: GoogleFonts.assistant(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₪${quote.totalPrice.toStringAsFixed(0)}',
                    style: GoogleFonts.assistant(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: GoogleFonts.assistant(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _trOrLocale(context, l10n, 'viewQuote',
                    en: 'View quote', he: 'צפה בהצעה', ar: 'عرض العرض'),
                onPressed: () => _viewQuote(context, quote),
                icon: Icon(
                  Icons.visibility_outlined,
                  color: hasPdf
                      ? AppTheme.secondary
                      : AppTheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
              if (canConvert) ...[
                const SizedBox(width: 4),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () => _convertToOrder(context, ref, quote),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceContainerLowest,
                      foregroundColor: AppTheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(
                          color: AppTheme.primary,
                          width: 1.2,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                    label: Text(
                      _trOrLocale(
                        context,
                        l10n,
                        'convertToOrder',
                        en: 'Convert to order',
                        he: 'המר להזמנה',
                        ar: 'تحويل إلى طلب',
                      ),
                      style: GoogleFonts.assistant(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _trOrLocale(
      context,
      l10n,
      'quoteHistory',
      en: 'Quotes',
      he: 'הצעות מחיר',
      ar: 'عروض الأسعار',
    );

    return widget.quotesAsync.when(
      data: (quotes) {
        final canToggle = quotes.length > _collapsedCount;
        final visible = (!_expanded && canToggle)
            ? quotes.take(_collapsedCount).toList()
            : quotes;

        return _SidebarCard(
          title: title,
          icon: Icons.request_quote_outlined,
          expanded: canToggle ? _expanded : null,
          onToggleExpanded:
              canToggle ? () => setState(() => _expanded = !_expanded) : null,
          titleBadge: quotes.isEmpty
              ? null
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.secondary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    quotes.length.toString(),
                    style: GoogleFonts.assistant(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
          child: quotes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _trOrLocale(
                      context,
                      l10n,
                      'noQuotesForCustomer',
                      en: 'No quotes for this customer.',
                      he: 'אין הצעות מחיר ללקוח זה.',
                      ar: 'لا توجد عروض أسعار لهذا العميل.',
                    ),
                    textAlign: TextAlign.start,
                    style: GoogleFonts.assistant(
                      color: AppTheme.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 1,
                          color:
                              AppTheme.outlineVariant.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, index) {
                          return _quoteRow(context, ref, visible[index]);
                        },
                      ),
                    ),
                    if (canToggle) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _expanded
                                ? _trOrLocale(context, l10n, 'showLess',
                                    en: 'Show less',
                                    he: 'הצג פחות',
                                    ar: 'عرض أقل')
                                : _trOrLocale(context, l10n, 'showMore',
                                    en:
                                        'Show more (${quotes.length - _collapsedCount})',
                                    he:
                                        'הצג עוד (${quotes.length - _collapsedCount})',
                                    ar:
                                        'عرض المزيد (${quotes.length - _collapsedCount})'),
                            style: GoogleFonts.assistant(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
      loading: () => _SidebarCard(
        title: title,
        icon: Icons.request_quote_outlined,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _SidebarCard(
        title: title,
        icon: Icons.request_quote_outlined,
        child: Text(
          '${l10n?.tr('error') ?? 'Error'}: $e',
          style: GoogleFonts.assistant(color: AppTheme.error),
        ),
      ),
    );
  }
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

class _QuoteFormScreen extends ConsumerStatefulWidget {
  final Customer customer;
  const _QuoteFormScreen({required this.customer});

  @override
  ConsumerState<_QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends ConsumerState<_QuoteFormScreen> {
  final List<_QuoteItemRow> _items = [];
  final _notesController = TextEditingController();
  OverlayEntry? _inventoryOverlayEntry;
  bool _isSending = false;
  bool _inStockOnly = true;

  @override
  void initState() {
    super.initState();
    _items.add(_QuoteItemRow());
  }

  @override
  void dispose() {
    _hideInventoryDropdown();
    _notesController.dispose();
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

  double get _vat => _subtotal * 0.18;

  double get _grandTotal => _subtotal + _vat;

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

    if (widget.customer.phones.isEmpty) {
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
        customerId: widget.customer.id,
        totalPrice: _grandTotal,
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
        customer: widget.customer,
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

      String phone =
          widget.customer.phones.first.replaceAll(RegExp(r'\D'), '');
      if (phone.startsWith('0')) {
        phone = '972${phone.substring(1)}';
      } else if (!phone.startsWith('972')) {
        phone = '972$phone';
      }

      final customerDisplayName =
          widget.customer.customerName.trim().isNotEmpty
              ? widget.customer.customerName
              : widget.customer.cardName;

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
                    child: Text(
                      '${widget.customer.cardName} — ${widget.customer.customerName}',
                      style: GoogleFonts.assistant(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface,
                      ),
                    ),
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
                                  _trOrLocale(
                                    context,
                                    l10n,
                                    'quoteSelectedStock',
                                    en: 'Available now:',
                                    he: 'זמין כעת:',
                                    ar: 'متوفر الآن:',
                                  ) +
                                      ' ${selectedInv.availableStock}',
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
                const SizedBox(height: 4),
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
