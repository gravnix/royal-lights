import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_date_format.dart';
import '../../config/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../providers/providers.dart';
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
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;

            final rightColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _ContactInfoCard(customer: _customer, l10n: l10n),
                const SizedBox(height: 24),
                if (_customer.notes != null && _customer.notes!.isNotEmpty)
                  _EditableNotesCard(
                    customerId: _customer.id,
                    initialNotes: _customer.notes ?? '',
                    l10n: l10n,
                    onSaved: (next) {
                      setState(() => _customer = _customer.copyWith(notes: next));
                    },
                  ),
                if (_customer.notes == null || _customer.notes!.isEmpty)
                  _EditableNotesCard(
                    customerId: _customer.id,
                    initialNotes: '',
                    l10n: l10n,
                    onSaved: (next) {
                      setState(() => _customer = _customer.copyWith(notes: next));
                    },
                  ),
              ],
            );

            final leftColumn = Column(
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(flex: 5, child: rightColumn),
                              const SizedBox(width: 28),
                              Expanded(flex: 6, child: leftColumn),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              rightColumn,
                              const SizedBox(height: 28),
                              leftColumn,
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

  const _SidebarCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.titleBadge,
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

class _OrdersListSection extends StatelessWidget {
  final AsyncValue<List<Order>> ordersAsync;
  final AppLocalizations? l10n;
  final VoidCallback onViewAll;

  const _OrdersListSection({
    required this.ordersAsync,
    required this.l10n,
    required this.onViewAll,
  });

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

    return ordersAsync.when(
      data: (orders) {
        return _SidebarCard(
          title: title,
          icon: Icons.receipt_long_rounded,
          titleBadge: orders.isEmpty ? null : _countBadge(orders.length),
          trailing: TextButton(
            onPressed: onViewAll,
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
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.outlineVariant.withValues(alpha: 0.12),
                    ),
          itemBuilder: (context, index) {
                      return _OrderRow(order: orders[index], l10n: l10n);
                    },
                  ),
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
