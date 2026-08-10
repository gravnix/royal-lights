import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';

class QuoteService {
  final SupabaseClient _client;
  QuoteService(this._client);

  static const _select =
      '*, customers(card_name, customer_name), quote_items(*)';

  Future<List<Quote>> getByCustomer(String customerId) async {
    final data = await _client
        .from('quotes')
        .select(_select)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Quote.fromJson(e)).toList();
  }

  Future<List<Quote>> getAll() async {
    final data = await _client
        .from('quotes')
        .select(_select)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Quote.fromJson(e)).toList();
  }

  Future<Quote> getById(String id) async {
    final data = await _client
        .from('quotes')
        .select(_select)
        .eq('id', id)
        .single();
    return Quote.fromJson(data);
  }

  Future<Quote> create(Quote quote, List<QuoteItem> items) async {
    final quoteData =
        await _client.from('quotes').insert(quote.toJson()).select().single();
    final quoteId = quoteData['id'] as String;

    if (items.isNotEmpty) {
      final itemsJson = items.map((item) {
        final json = item.toJson();
        json['quote_id'] = quoteId;
        return json;
      }).toList();
      await _client.from('quote_items').insert(itemsJson);
    }

    return getById(quoteId);
  }

  Future<void> updateStatus(
      String id, String status, String username) async {
    await _client
        .from('quotes')
        .update({'status': status, 'updated_by': username}).eq('id', id);
  }

  Future<void> setPdfUrl(String id, String pdfUrl) async {
    await _client.from('quotes').update({'pdf_url': pdfUrl}).eq('id', id);
  }

  Future<void> setConvertedOrderId(
      String id, String orderId, String username) async {
    await _client.from('quotes').update({
      'converted_order_id': orderId,
      'status': 'Converted',
      'updated_by': username,
    }).eq('id', id);
  }

  Future<String> uploadPdf(String quoteId, Uint8List pdfBytes) async {
    const bucket = 'quote-pdfs';
    final path = '$quoteId/quote.pdf';
    await _client.storage.from(bucket).uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/pdf',
          ),
        );
    final url = _client.storage.from(bucket).getPublicUrl(path);
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = Uri.parse(url);
    final qp = Map<String, String>.from(uri.queryParameters)..['v'] = ts;
    return uri.replace(queryParameters: qp).toString();
  }
}
