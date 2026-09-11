import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';

class CustomerService {
  final SupabaseClient _client;
  CustomerService(this._client);

  Future<List<Customer>> getAll() async {
    final data = await _client.from('customers').select().order('card_name');
    return (data as List).map((e) => Customer.fromJson(e)).toList();
  }

  Future<Customer> getById(String id) async {
    final data = await _client.from('customers').select().eq('id', id).single();
    return Customer.fromJson(data);
  }

  Future<Map<String, double>> getDebts() async {
    final data = await _client.from('customer_debts').select();
    final Map<String, double> debts = {};
    for (final row in data) {
      debts[row['customer_id'] as String] =
          (row['remaining_debt'] as num?)?.toDouble() ?? 0;
    }
    return debts;
  }

  Future<Customer> create(Customer customer) async {
    final data = await _client
        .from('customers')
        .insert(customer.toJson())
        .select()
        .single();
    return Customer.fromJson(data);
  }

  Future<Customer> update(String id, Map<String, dynamic> updates) async {
    final data = await _client
        .from('customers')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return Customer.fromJson(data);
  }

  /// Upload customer photo to Supabase Storage and return public URL.
  /// Requires a storage bucket named "customer-photos" with public read access.
  Future<String> uploadPhoto(String customerId, Uint8List imageBytes) async {
    const bucket = 'customer-photos';
    final path = '$customerId/photo.jpg';
    await _client.storage.from(bucket).uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from(bucket).getPublicUrl(path);
    return url;
  }

  /// Delete customer photo from Supabase Storage and database.
  Future<void> deletePhoto(String customerId) async {
    const bucket = 'customer-photos';
    final path = '$customerId/photo.jpg';
    
    // Attempt to remove from storage (ignore if it doesn't exist)
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}

    // Update customer record
    await update(customerId, {'image_url': null});
  }

  /// How much history a delete would destroy. Used to spell out the damage in
  /// the confirmation dialog rather than discovering it from a DB error.
  Future<({int orders, int payments})> getDeletionImpact(String id) async {
    final results = await Future.wait([
      _client.from('orders').select('id').eq('customer_id', id),
      _client.from('payments').select('id').eq('customer_id', id),
    ]);
    return (
      orders: (results[0] as List).length,
      payments: (results[1] as List).length,
    );
  }

  /// Deletes the customer and everything hanging off them.
  ///
  /// `orders` and `payments` are declared `ON DELETE RESTRICT`, so deleting the
  /// customer row on its own raises a foreign-key violation for anyone who has
  /// ever ordered or paid — which is essentially every real customer. The
  /// dependants are therefore removed explicitly, in FK order, rather than by
  /// relaxing the constraints to CASCADE: financial history should only ever be
  /// destroyed by this deliberate path, never as a side effect of some other
  /// delete elsewhere in the app.
  ///
  /// `quotes` and `fixing_tickets` already cascade, as do `order_items`,
  /// `quote_items` and `fixing_ticket_items` under their parents.
  ///
  /// **This is irreversible.** Callers must confirm against
  /// [getDeletionImpact] first.
  Future<void> delete(String id) async {
    // Payments first: they reference both the customer and (optionally) an
    // order, so they have to go before the orders they point at.
    await _client.from('payments').delete().eq('customer_id', id);
    await _client.from('orders').delete().eq('customer_id', id);
    await _client.from('customers').delete().eq('id', id);

    // Photo last, and best-effort: if it were removed first, a failed row
    // delete would leave the customer alive with a dead image_url.
    const bucket = 'customer-photos';
    final path = '$id/photo.jpg';
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}
  }
}
