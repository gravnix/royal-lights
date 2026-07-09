import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';

class InventoryService {
  final SupabaseClient _client;
  InventoryService(this._client);

  Future<List<InventoryItem>> getAll() async {
    final data =
        await _client.from('inventory_items').select().order('description');
    return (data as List).map((e) => InventoryItem.fromJson(e)).toList();
  }

  Future<InventoryItem> create(InventoryItem item) async {
    final data = await _client
        .from('inventory_items')
        .insert(item.toJson())
        .select()
        .single();
    return InventoryItem.fromJson(data);
  }

  Future<InventoryItem> update(String id, Map<String, dynamic> updates) async {
    final data = await _client
        .from('inventory_items')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return InventoryItem.fromJson(data);
  }

  Future<void> delete(String id) async {
    // Best-effort: remove stored photo as well (ignore missing/permission errors).
    const bucket = 'inventory-item-photos';
    final path = '$id/photo.jpg';
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}

    await _client.from('inventory_items').delete().eq('id', id);
  }

  Future<String> uploadPhoto(String itemId, Uint8List imageBytes) async {
    const bucket = 'inventory-item-photos';
    final path = '$itemId/photo.jpg';
    await _client.storage.from(bucket).uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

