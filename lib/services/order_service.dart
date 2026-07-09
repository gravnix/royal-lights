import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/order_item.dart';

class OrderService {
  final SupabaseClient _client;
  OrderService(this._client);

  Future<List<Order>> getAll() async {
    final data = await _client
        .from('orders')
        .select(
          '*, customers(card_name, customer_name), '
          'order_items(*, rooms(name), suppliers(company_name, phone))',
        )
        .order('created_at', ascending: false);
    return (data as List).map((e) => Order.fromJson(e)).toList();
  }

  Future<List<Order>> getByCustomer(String customerId) async {
    final data = await _client
        .from('orders')
        .select(
          '*, customers(card_name, customer_name), '
          'order_items(*, rooms(name), suppliers(company_name, phone))',
        )
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Order.fromJson(e)).toList();
  }

  /// Fetches all orders for a customer including order_items (for fixing screen).
  Future<List<Order>> getByCustomerWithItems(String customerId) async {
    final data = await _client
        .from('orders')
        .select(
          '*, customers(card_name, customer_name), order_items(*, rooms(name), suppliers(company_name, phone))',
        )
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Order.fromJson(e)).toList();
  }

  Future<Order> getById(String id) async {
    final data = await _client
        .from('orders')
        .select(
          '*, customers(card_name, customer_name), order_items(*, rooms(name), suppliers(company_name, phone))',
        )
        .eq('id', id)
        .single();
    return Order.fromJson(data);
  }

  Future<List<Order>> getAssemblyOrders() async {
    final data = await _client
        .from('orders')
        .select(
          '*, customers(card_name, customer_name), order_items(*, rooms(name), suppliers(company_name, phone))',
        )
        .eq('assembly_required', true)
        .neq('status', 'Canceled')
        .neq('status', 'Handled')
        .order('assembly_date', ascending: true);
    return (data as List).map((e) => Order.fromJson(e)).toList();
  }

  Future<Order> create(Order order, List<OrderItem> items) async {
    // Insert order
    final orderData =
        await _client.from('orders').insert(order.toJson()).select().single();
    final orderId = orderData['id'] as String;

    // Insert items
    if (items.isNotEmpty) {
      final itemsJson = items.map((item) {
        final json = item.toJson();
        json['order_id'] = orderId;
        return json;
      }).toList();
      await _client.from('order_items').insert(itemsJson);
    }

    return getById(orderId);
  }

  Future<Order> update(String id, Map<String, dynamic> updates) async {
    await _client.from('orders').update(updates).eq('id', id);
    return getById(id);
  }

  Future<void> updateStatus(String id, String status, String username) async {
    await _client
        .from('orders')
        .update({'status': status, 'updated_by': username}).eq('id', id);
  }

  /// Marks line items as received from supplier (workflow). [itemIds] are order_items.id.
  Future<void> markItemsSupplierReceived(
    Iterable<String> itemIds,
    String username,
  ) async {
    final ids = itemIds.where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return;
    await _client.from('order_items').update({
      'supplier_received': true,
      'updated_by': username,
    }).inFilter('id', ids);
  }

  /// Marks line items as ready for customer pickup (partial readiness supported).
  /// [itemIds] are order_items.id.
  Future<void> markItemsReadyForPickup(
    Iterable<String> itemIds,
    String username,
  ) async {
    final ids = itemIds.where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return;
    await _client.from('order_items').update({
      'ready_for_pickup': true,
      'updated_by': username,
    }).inFilter('id', ids);
  }

  /// Deducts inventory stock for an order that was completed (Delivered),
  /// only for order lines linked to inventory via `inventory_item_id`,
  /// and only once per line (`inventory_deducted`).
  Future<void> deductInventoryForOrder(String orderId, String username) async {
    await _client.rpc(
      'deduct_inventory_for_order',
      params: {
        'p_order_id': orderId,
        'p_username': username,
      },
    );
  }

  /// Starts warranty counting for order items (if not started yet).
  ///
  /// Rule:
  /// - If order status is Delivered -> start date = delivery_date if set, else today.
  /// - Else if delivery_date <= today -> start date = delivery_date.
  /// - Only applies to items with warranty_years > 0 and warranty_start_date is null.
  Future<void> startWarrantyIfEligible(String orderId, String username) async {
    final order = await _client
        .from('orders')
        .select('status, delivery_date')
        .eq('id', orderId)
        .single();

    final status = order['status'] as String?;
    final deliveryRaw = order['delivery_date'] as String?;
    final deliveryDate =
        deliveryRaw != null ? DateTime.parse(deliveryRaw) : null;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    DateTime? start;
    if (status == OrderStatus.delivered.dbValue) {
      start = deliveryDate ?? todayDate;
    } else if (deliveryDate != null) {
      final dd =
          DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day);
      if (!dd.isAfter(todayDate)) start = dd;
    }
    if (start == null) return;

    await _client
        .from('order_items')
        .update({
          'warranty_start_date': start.toIso8601String().split('T').first,
          'updated_by': username,
        })
        .eq('order_id', orderId)
        .gt('warranty_years', 0)
        .isFilter('warranty_start_date', null);
  }

  Future<void> cancelOrder(String id, String username) async {
    await _client
        .from('orders')
        .update({'status': 'Canceled', 'updated_by': username}).eq('id', id);
  }

  Future<void> updateItems(
    String orderId,
    List<OrderItem> items,
    String username,
  ) async {
    // Safety guard: never delete all items when saving an empty list.
    // An empty list means items failed to load, not that the user deleted them.
    if (items.isEmpty) return;

    // Delete existing items
    await _client.from('order_items').delete().eq('order_id', orderId);

    // Insert new items
    final itemsJson = items.map((item) {
      final json = item.toJson();
      json['order_id'] = orderId;
      json['created_by'] = username;
      json['updated_by'] = username;
      return json;
    }).toList();
    await _client.from('order_items').insert(itemsJson);
  }

  /// Uploads a manually-picked photo for an order item to the
  /// `order-item-photos` bucket and returns a public URL with cache-buster.
  /// `fileKey` should be stable per-row (e.g. the saved `order_items.id`,
  /// or a generated id for unsaved rows).
  Future<String> uploadOrderItemPhoto(
    String fileKey,
    Uint8List imageBytes,
  ) async {
    const bucket = 'order-item-photos';
    final path = '$fileKey/photo.jpg';
    await _client.storage.from(bucket).uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from(bucket).getPublicUrl(path);
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = Uri.parse(url);
    final qp = Map<String, String>.from(uri.queryParameters)..['v'] = ts;
    return uri.replace(queryParameters: qp).toString();
  }

  Future<int> getOpenOrdersCount() async {
    final data =
        await _client.from('orders').select('id').eq('status', 'Active');
    return (data as List).length;
  }

  Future<int> getUpcomingAssembliesCount() async {
    final data = await _client
        .from('orders')
        .select('id')
        .eq('assembly_required', true)
        .inFilter('status', ['Active', 'In Assembly']);
    return (data as List).length;
  }
}
