import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment.dart';

class PaymentService {
  /// Uses the same public bucket as inventory photos (already provisioned in Supabase).
  static const String receiptBucket = 'inventory-item-photos';

  /// Optional dedicated bucket from [20260520140000_add_payment_receipts_bucket.sql].
  static const String legacyReceiptBucket = 'payment-receipts';

  static const String _paymentsFolder = 'payments';

  final SupabaseClient _client;
  PaymentService(this._client);

  /// Path stored in [payments.image_url] for new uploads.
  static String receiptStoragePath(String paymentId) =>
      '$_paymentsFolder/$paymentId/receipt.jpg';

  static String _bucketForStoredPath(String stored) {
    if (stored.startsWith('$_paymentsFolder/')) {
      return receiptBucket;
    }
    return legacyReceiptBucket;
  }

  /// Builds a browser-loadable URL from [stored] (storage path or legacy full URL).
  static String? resolveReceiptDisplayUrl(
    SupabaseClient client,
    String? stored, {
    String? cacheBustToken,
  }) {
    final s = stored?.trim() ?? '';
    if (s.isEmpty) return null;

    final String baseUrl;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      baseUrl = s;
    } else {
      final bucket = _bucketForStoredPath(s);
      baseUrl = client.storage.from(bucket).getPublicUrl(s);
    }

    if (cacheBustToken == null || cacheBustToken.isEmpty) {
      return baseUrl;
    }
    try {
      final uri = Uri.parse(baseUrl);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['v'] = cacheBustToken;
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return '$baseUrl?v=$cacheBustToken';
    }
  }

  bool hasReceiptImage(Payment payment) =>
      payment.imageUrl != null && payment.imageUrl!.trim().isNotEmpty;

  String? receiptDisplayUrl(Payment payment) => resolveReceiptDisplayUrl(
        _client,
        payment.imageUrl,
        cacheBustToken: payment.updatedAt?.millisecondsSinceEpoch.toString(),
      );

  Future<List<Payment>> getAll({String? username}) async {
    var query = _client.from('payments').select();
    if (username != null) {
      query = query.eq('created_by', username);
    }
    final data = await query.order('date', ascending: false);
    return (data as List).map((e) => Payment.fromJson(e)).toList();
  }

  Future<List<Payment>> getByCustomer(String customerId) async {
    final data = await _client
        .from('payments')
        .select()
        .eq('customer_id', customerId)
        .order('date', ascending: false);
    return (data as List).map((e) => Payment.fromJson(e)).toList();
  }

  Future<Payment> create(Payment payment, {String? id}) async {
    final row = payment.toJson();
    if (id != null) {
      row['id'] = id;
    }
    final data = await _client.from('payments').insert(row).select().single();
    return Payment.fromJson(data);
  }

  Future<Payment> update(String id, Map<String, dynamic> updates) async {
    final data = await _client
        .from('payments')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return Payment.fromJson(data);
  }

  Future<void> delete(String id) async {
    await _client.from('payments').delete().eq('id', id);
  }

  /// Deletes payment row and best-effort receipt file in storage.
  Future<void> deleteWithReceipt(Payment payment) async {
    final stored = payment.imageUrl?.trim();
    if (stored != null && stored.isNotEmpty) {
      try {
        final bucket = stored.startsWith('$_paymentsFolder/')
            ? receiptBucket
            : legacyReceiptBucket;
        await _client.storage.from(bucket).remove([stored]);
      } catch (_) {
        // Row delete still proceeds if storage object is already gone.
      }
    }
    await delete(payment.id);
  }

  /// Upload to storage; returns the storage path stored in [image_url].
  Future<String> uploadReceiptPhoto(String paymentId, Uint8List imageBytes) async {
    final path = receiptStoragePath(paymentId);
    await _client.storage.from(receiptBucket).uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return path;
  }

  /// Upload receipt bytes and persist storage path on the payment row.
  Future<Payment> attachReceiptPhoto(
    String paymentId,
    Uint8List imageBytes, {
    String? updatedBy,
  }) async {
    final path = await uploadReceiptPhoto(paymentId, imageBytes);
    final updated = await update(paymentId, {
      'image_url': path,
      if (updatedBy != null) 'updated_by': updatedBy,
    });
    if (!hasReceiptImage(updated)) {
      throw StateError('image_url was not saved on payment $paymentId');
    }
    return updated;
  }

  Future<double> getTotalUnpaidDebts() async {
    final data = await _client.from('customer_debts').select('remaining_debt');
    double total = 0;
    for (final row in data) {
      final debt = (row['remaining_debt'] as num?)?.toDouble() ?? 0;
      if (debt > 0) total += debt;
    }
    return total;
  }
}
