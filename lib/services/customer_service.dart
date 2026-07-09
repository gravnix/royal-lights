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

  Future<void> delete(String id) async {
    // Best-effort: remove stored photo as well (ignore missing/permission errors).
    const bucket = 'customer-photos';
    final path = '$id/photo.jpg';
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}

    await _client.from('customers').delete().eq('id', id);
  }
}
