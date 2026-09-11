import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:royal_lights_app/models/customer.dart';
import 'package:royal_lights_app/models/order.dart';
import 'package:royal_lights_app/screens/orders/order_pdf_sender.dart';
import 'package:royal_lights_app/services/order_service.dart';

/// The shared sender is behind the automatic send on save and both manual
/// buttons, so its contract matters: it never throws, and it reports why a
/// PDF didn't go out instead of failing silently.
void main() {
  // Constructing a client does no I/O; the no-phone path returns before
  // touching it.
  final orderService =
      OrderService(SupabaseClient('http://localhost', 'test-key'));
  final order = Order(id: 'o1', customerId: 'c1', orderNumber: 7);

  test('reports noPhone, without sending, for a customer with no phone',
      () async {
    final result = await sendOrderPdfToCustomer(
      orderService: orderService,
      customer: Customer(id: 'c1', cardName: 'כרטיס', customerName: 'לקוח'),
      order: order,
      items: const [],
      languageCode: 'he',
    );
    expect(result, OrderPdfSend.noPhone);
  });

  test('treats a blank phone as no phone', () async {
    final result = await sendOrderPdfToCustomer(
      orderService: orderService,
      customer: Customer(
        id: 'c1',
        cardName: 'כרטיס',
        customerName: 'לקוח',
        phones: const ['   '],
      ),
      order: order,
      items: const [],
      languageCode: 'he',
    );
    expect(result, OrderPdfSend.noPhone);
  });

  test('every outcome has its own message in every language', () {
    for (final lang in ['he', 'ar', 'en']) {
      final messages =
          OrderPdfSend.values.map((r) => orderPdfSendMessage(r, lang)).toSet();
      expect(messages.length, OrderPdfSend.values.length, reason: lang);
    }
  });

  test('caption names the customer and the order number', () {
    final caption = orderPdfCaption(
      languageCode: 'he',
      customer: Customer(id: 'c1', cardName: 'כרטיס', customerName: 'אבי'),
      orderNumber: 42,
      isUpdate: false,
    );
    expect(caption, contains('אבי'));
    expect(caption, contains('#42'));
  });
}
