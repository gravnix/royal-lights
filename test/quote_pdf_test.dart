import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:royal_lights_app/models/customer.dart';
import 'package:royal_lights_app/models/quote.dart';
import 'package:royal_lights_app/models/quote_item.dart';
import 'package:royal_lights_app/services/quote_pdf_service.dart';

/// The quote PDF is the only artefact that leaves the building, and a reversed
/// digit in it reads as a typo rather than a bug. These render a Hebrew quote
/// whose item names, notes and address all mix Hebrew with digits and Latin —
/// the exact shape that bidi handling gets wrong — and dump the result to
/// `build/quote_probe.pdf` for eyeballing.
void main() {
  group('QuotePdfService.generate', () {
    final customer = Customer(
      id: 'c1',
      cardName: 'אבי 2000 בע״מ',
      customerName: 'אבי כהן',
      phones: const ['0501234567'],
      location: 'הרצל 15, טירה',
    );

    final quote = Quote(
      id: 'q1',
      customerId: 'c1',
      quoteNumber: 15,
      totalPrice: 1250,
      notes: 'הלקוח ביקש 2 יחידות נוספות עד לתאריך 15/09/2026, '
          'סה״כ 7 יחידות במחיר 1,250.00 ש״ח כולל התקנה.',
    );

    final items = [
      QuoteItem(
        itemNumber: '7290119110350',
        name: 'גוף תאורה 3 מטר לסלון עם 4 נורות LED בגוון 3000K',
        quantity: 2,
        price: 250,
        extras: 'כבל זהב',
        extrasPrice: 50,
      ),
      QuoteItem(
        itemNumber: 'ABC-123',
        name: 'נורה 12W לבן חם',
        quantity: 4,
        price: 45.5,
      ),
      QuoteItem(name: 'התקנה', quantity: 1, price: 300),
    ];

    test('produces a PDF for a Hebrew quote with mixed-direction text',
        () async {
      final bytes = await QuotePdfService.generate(
        customer: customer,
        quote: quote,
        items: items,
        languageCode: 'he',
      );

      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      // Dump for manual inspection; harmless if the directory is read-only.
      try {
        final out = File('build/quote_probe.pdf');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes);
      } catch (_) {}
    });

    test('produces a PDF in English and Arabic too', () async {
      for (final lang in ['en', 'ar']) {
        final bytes = await QuotePdfService.generate(
          customer: customer,
          quote: quote,
          items: items,
          languageCode: lang,
        );
        expect(bytes.length, greaterThan(1000), reason: lang);
      }
    });

    test('renders a percentage discount before VAT', () async {
      final bytes = await QuotePdfService.generate(
        customer: customer,
        quote: Quote(
          id: 'q2',
          customerId: 'c1',
          quoteNumber: 16,
          totalPrice: 0,
          discountPercentage: 10,
          discountType: 'percentage',
          notes: 'הנחה של 10% לפני מע״מ.',
        ),
        items: items,
        languageCode: 'he',
      );
      expect(bytes.length, greaterThan(1000));
      try {
        final out = File('build/quote_discount_pct.pdf');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes);
      } catch (_) {}
    });

    test('renders a fixed-amount discount', () async {
      final bytes = await QuotePdfService.generate(
        customer: customer,
        quote: Quote(
          id: 'q3',
          customerId: 'c1',
          quoteNumber: 17,
          totalPrice: 0,
          discountPercentage: 150,
          discountType: 'fixed_amount',
        ),
        items: items,
        languageCode: 'he',
      );
      expect(bytes.length, greaterThan(1000));
      try {
        File('build/quote_discount_fixed.pdf').writeAsBytesSync(bytes);
      } catch (_) {}
    });

    test('handles an empty item list without throwing', () async {
      final bytes = await QuotePdfService.generate(
        customer: customer,
        quote: quote,
        items: const [],
        languageCode: 'he',
      );
      expect(bytes.length, greaterThan(1000));
    });
  });
}
