import 'dart:typed_data';

import '../models/customer.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';
import 'quote_pdf_service.dart';

/// Order PDF — the customer-facing summary sent over WhatsApp.
///
/// An order and a quote print the same document apart from the heading and
/// the totals convention, so this maps an Order onto [QuotePdfService] rather
/// than forking 900 lines of layout. Everything the quote PDF gains — the bidi
/// handling, the unit-price column, the letterhead — applies here for free.
class OrderPdfService {
  static Future<void> warmUp(String languageCode) =>
      QuotePdfService.warmUp(languageCode);

  static Future<Uint8List> generate({
    required Customer customer,
    required Order order,
    required List<OrderItem> items,
    required String languageCode,
  }) {
    return QuotePdfService.generate(
      customer: customer,
      // The renderer takes its numbers off this shape; only the fields it
      // reads are populated.
      quote: Quote(
        id: order.id,
        customerId: order.customerId,
        quoteNumber: order.orderNumber,
        totalPrice: order.totalPrice,
        vatEnabled: order.vatEnabled,
        discountPercentage: order.discountPercentage,
        discountType: order.discountType,
        notes: order.notes,
      ),
      items: items
          .map((i) => QuoteItem(
                itemNumber: i.itemNumber,
                name: i.name,
                imageUrl: i.imageUrl,
                quantity: i.quantity,
                extras: i.extras,
                price: i.price,
                extrasPrice: i.extrasPrice,
              ))
          .toList(),
      languageCode: languageCode,
      kind: PdfDocKind.order,
      // Assembly is charged once for the order, not per line, so it is a
      // separate row in the totals rather than a phantom item.
      extraFee: order.assemblyRequired ? order.assemblyPrice : 0,
    );
  }
}
