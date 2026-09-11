import 'package:flutter/foundation.dart';

import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/order_pdf_service.dart';
import '../../services/order_service.dart';
import '../../services/whatsapp_service.dart';

/// What happened when an order PDF was sent to the customer.
enum OrderPdfSend { sent, noPhone, failed }

/// Generates the order PDF, uploads it, and sends it to the customer on
/// WhatsApp.
///
/// The single implementation behind all three entry points: the automatic
/// send when an order is saved, the button on the order screen, and the
/// button in the orders list.
///
/// Never throws — a failed send must not undo a save or break a list — but
/// reports the outcome so the caller can tell the operator what happened.
Future<OrderPdfSend> sendOrderPdfToCustomer({
  required OrderService orderService,
  required Customer customer,
  required Order order,
  required List<OrderItem> items,
  required String languageCode,
  bool isUpdate = false,
}) async {
  final phone = customer.phones.isNotEmpty ? customer.phones.first.trim() : '';
  if (phone.isEmpty) return OrderPdfSend.noPhone;

  try {
    await OrderPdfService.warmUp(languageCode);
    final pdfBytes = await OrderPdfService.generate(
      customer: customer,
      order: order,
      items: items,
      languageCode: languageCode,
    );
    final pdfUrl = await orderService.uploadPdf(order.id, pdfBytes);

    final sent = await WhatsAppService.sendDocument(
      phone,
      pdfUrl,
      orderPdfCaption(
        languageCode: languageCode,
        customer: customer,
        orderNumber: order.orderNumber,
        isUpdate: isUpdate,
      ),
      fileName: 'order-${order.orderNumber ?? order.id}.pdf',
    );
    return sent ? OrderPdfSend.sent : OrderPdfSend.failed;
  } catch (e) {
    debugPrint('Order PDF send failed: $e');
    return OrderPdfSend.failed;
  }
}

/// Short WhatsApp caption accompanying the order PDF. The figures live in the
/// document, so this only has to say what arrived.
String orderPdfCaption({
  required String languageCode,
  required Customer customer,
  required int? orderNumber,
  required bool isUpdate,
}) {
  final name = customer.customerName.trim().isNotEmpty
      ? customer.customerName
      : customer.cardName;
  final numText = orderNumber != null ? ' #$orderNumber' : '';
  return switch (languageCode) {
    'he' => isUpdate
        ? 'שלום $name,\nההזמנה$numText עודכנה. הפרטים המלאים בקובץ המצורף.'
        : 'שלום $name,\nתודה על הזמנתך$numText! הפרטים המלאים בקובץ המצורף.',
    'ar' => isUpdate
        ? 'مرحبًا $name،\nتم تحديث الطلب$numText. التفاصيل في الملف المرفق.'
        : 'مرحبًا $name،\nشكرًا على طلبك$numText! التفاصيل في الملف المرفق.',
    _ => isUpdate
        ? 'Hello $name,\nYour order$numText has been updated. Full details are in the attached PDF.'
        : 'Hello $name,\nThank you for your order$numText! Full details are in the attached PDF.',
  };
}

/// One-line description of [result] for a snackbar.
String orderPdfSendMessage(OrderPdfSend result, String languageCode) {
  return switch (result) {
    OrderPdfSend.sent => switch (languageCode) {
        'he' => 'PDF ההזמנה נשלח ללקוח בוואטסאפ',
        'ar' => 'تم إرسال ملف PDF للطلب إلى العميل عبر واتساب',
        _ => 'Order PDF sent to the customer on WhatsApp',
      },
    OrderPdfSend.noPhone => switch (languageCode) {
        'he' => 'ה-PDF לא נשלח — אין ללקוח מספר טלפון',
        'ar' => 'لم يُرسل ملف PDF — لا يوجد رقم هاتف للعميل',
        _ => 'PDF not sent — the customer has no phone number',
      },
    OrderPdfSend.failed => switch (languageCode) {
        'he' => 'שליחת ה-PDF ללקוח נכשלה',
        'ar' => 'فشل إرسال ملف PDF إلى العميل',
        _ => 'Sending the PDF to the customer failed',
      },
  };
}
