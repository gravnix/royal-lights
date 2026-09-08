import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:royal_lights_app/models/customer.dart';
import 'package:royal_lights_app/models/order.dart';
import 'package:royal_lights_app/models/order_item.dart';
import 'package:royal_lights_app/services/order_pdf_service.dart';

/// Orders print through the same renderer as quotes but with the order totals
/// convention: VAT first, discount off the VAT-inclusive total. Getting that
/// backwards would print a figure that disagrees with the stored total_price.
void main() {
  final customer = Customer(
    id: 'c1',
    cardName: 'אבי 2000 בע״מ',
    customerName: 'אבי כהן',
    phones: const ['0501234567'],
    location: 'הרצל 15, טירה',
  );

  final items = [
    OrderItem(
      itemNumber: '7290119110350',
      name: 'גוף תאורה 3 מטר לסלון עם 4 נורות LED בגוון 3000K',
      quantity: 2,
      price: 250,
      extras: 'כבל זהב',
      extrasPrice: 50,
    ),
    OrderItem(
      itemNumber: 'ABC-123',
      name: 'נורה 12W לבן חם',
      quantity: 4,
      price: 45.5,
    ),
  ];

  test('renders an order PDF with assembly fee and a discount', () async {
    final bytes = await OrderPdfService.generate(
      customer: customer,
      order: Order(
        id: 'o1',
        customerId: 'c1',
        orderNumber: 42,
        assemblyRequired: true,
        assemblyPrice: 300,
        discountPercentage: 10,
        discountType: 'percentage',
        totalPrice: 0,
        notes: 'הרכבה בתיאום מראש, 15/09/2026.',
      ),
      items: items,
      languageCode: 'he',
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    try {
      final out = File('build/order_probe.pdf');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes);
    } catch (_) {}
  });

  test('renders an order with no assembly and no discount', () async {
    final bytes = await OrderPdfService.generate(
      customer: customer,
      order: Order(id: 'o2', customerId: 'c1', orderNumber: 43, totalPrice: 0),
      items: items,
      languageCode: 'he',
    );
    expect(bytes.length, greaterThan(1000));
  });
}
