int _warrantyYearsFromJson(dynamic value) {
  final n = (value as num?)?.toInt();
  if (n == 3) return 3;
  if (n == 5) return 5;
  return 0;
}

/// Parses user-entered decimal text that may use commas and/or dots
/// (e.g. `1,234.56` thousands+decimal, `1234,56` decimal comma only).
double parseDecimalInput(String raw, {double fallback = 0}) {
  var t = raw.trim();
  if (t.isEmpty) return fallback;

  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');

  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      // European: 1.234,56
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // US / IL: 1,234.56
      t = t.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    final after = t.substring(lastComma + 1);
    if (after.isNotEmpty && after.length <= 2) {
      t = t.replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
  }

  final v = double.tryParse(t);
  if (v == null || v.isNaN) return fallback;
  return v;
}

/// Formats a (possibly fractional) quantity for display.
/// Returns "1" for whole numbers, "1.5" / "1.25" for fractional values
/// (trailing zeros stripped, max 3 decimals).
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

class OrderItem {
  final String? id;
  final String? orderId;
  final String? itemNumber; // 1. Item Number (Barcode)
  final String name; // 2. Name
  final String? imageUrl; // 3. Image
  /// Quantity. May be fractional (e.g. 1.5 m of cable, 0.75 kg).
  final double quantity; // 4. Quantity
  final String? extras; // 5. Extras
  /// Line-level text; order form uses this for the per-line supplier (WhatsApp) note.
  final String? notes; // 6. Notes (optional)
  final double price; // 7. Unit price
  /// Add-ons price per unit (scales with quantity).
  final double extrasPrice;
  final bool assemblyRequired; // 8. Assembly Required
  final String? roomId; // 9. Room (legacy FK; optional when room_name is set)
  /// Persisted free-text room (column `room_name`).
  final String? roomLabel;
  final String? supplierId; // 10. Supplier
  /// Planned or actual delivery / shipping date for this line.
  final DateTime? deliveryDate;
  final bool existingInStore; // 11. Existing In Store
  /// Confirmed received from supplier (partial order fulfillment).
  final bool supplierReceived;
  /// Confirmed ready for customer pickup (partial readiness supported).
  final bool readyForPickup;
  /// Links to inventory item (when line was picked from inventory).
  final String? inventoryItemId;
  /// True once inventory stock was deducted after order completion.
  final bool inventoryDeducted;
  /// 0 = none, 3 = three-year, 5 = five-year warranty.
  final int warrantyYears;
  /// When warranty starts counting (usually delivery date once it begins).
  final DateTime? warrantyStartDate;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined data (not persisted)
  final String? roomName;
  final String? supplierName;
  final String? supplierPhone;

  OrderItem({
    this.id,
    this.orderId,
    this.itemNumber,
    required this.name,
    this.imageUrl,
    this.quantity = 1,
    this.extras,
    this.notes,
    this.price = 0,
    this.extrasPrice = 0,
    this.assemblyRequired = false,
    this.roomId,
    this.roomLabel,
    this.supplierId,
    this.deliveryDate,
    this.existingInStore = false,
    this.supplierReceived = false,
    this.readyForPickup = false,
    this.inventoryItemId,
    this.inventoryDeducted = false,
    this.warrantyYears = 0,
    this.warrantyStartDate,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.roomName,
    this.supplierName,
    this.supplierPhone,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String?,
      orderId: json['order_id'] as String?,
      itemNumber: json['item_number'] as String?,
      name: json['name'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      extras: json['extras'] as String?,
      notes: json['notes'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      extrasPrice: (json['extras_price'] as num?)?.toDouble() ?? 0,
      assemblyRequired: json['assembly_required'] as bool? ?? false,
      roomId: json['room_id'] as String?,
      roomLabel: json['room_name'] as String?,
      supplierId: json['supplier_id'] as String?,
      deliveryDate: json['delivery_date'] != null
          ? DateTime.parse(json['delivery_date'] as String)
          : null,
      existingInStore: json['existing_in_store'] as bool? ?? false,
      supplierReceived: json['supplier_received'] as bool? ?? false,
      readyForPickup: json['ready_for_pickup'] as bool? ?? false,
      inventoryItemId: json['inventory_item_id'] as String?,
      inventoryDeducted: json['inventory_deducted'] as bool? ?? false,
      warrantyYears: _warrantyYearsFromJson(json['warranty_years']),
      warrantyStartDate: json['warranty_start_date'] != null
          ? DateTime.parse(json['warranty_start_date'] as String)
          : null,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      roomName: json['rooms'] != null ? json['rooms']['name'] as String? : null,
      supplierName: json['suppliers'] != null
          ? json['suppliers']['company_name'] as String?
          : null,
      supplierPhone: json['suppliers'] != null
          ? json['suppliers']['phone'] as String?
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final roomLabelTrimmed = roomLabel?.trim();
    return {
      if (id != null && id!.trim().isNotEmpty) 'id': id,
      if (orderId != null) 'order_id': orderId,
      'item_number': itemNumber,
      'name': name,
      'image_url': imageUrl,
      'quantity': quantity,
      'extras': extras,
      'notes': notes,
      'price': price,
      'extras_price': extrasPrice,
      'assembly_required': assemblyRequired,
      'room_id': roomId,
      'room_name':
          (roomLabelTrimmed != null && roomLabelTrimmed.isNotEmpty)
              ? roomLabelTrimmed
              : null,
      'supplier_id': supplierId,
      'delivery_date': deliveryDate?.toIso8601String().split('T').first,
      'existing_in_store': existingInStore,
      'supplier_received': supplierReceived || existingInStore,
      'ready_for_pickup': readyForPickup,
      'inventory_item_id': inventoryItemId,
      'inventory_deducted': inventoryDeducted,
      'warranty_years': warrantyYears,
      'warranty_start_date': warrantyStartDate?.toIso8601String().split('T').first,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  OrderItem copyWith({
    String? id,
    String? orderId,
    String? itemNumber,
    String? name,
    String? imageUrl,
    double? quantity,
    String? extras,
    String? notes,
    double? price,
    double? extrasPrice,
    bool? assemblyRequired,
    String? roomId,
    String? roomLabel,
    String? supplierId,
    DateTime? deliveryDate,
    bool? existingInStore,
    bool? supplierReceived,
    bool? readyForPickup,
    String? inventoryItemId,
    bool? inventoryDeducted,
    int? warrantyYears,
    DateTime? warrantyStartDate,
    String? createdBy,
    String? updatedBy,
  }) {
    return OrderItem(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      itemNumber: itemNumber ?? this.itemNumber,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity ?? this.quantity,
      extras: extras ?? this.extras,
      notes: notes ?? this.notes,
      price: price ?? this.price,
      extrasPrice: extrasPrice ?? this.extrasPrice,
      assemblyRequired: assemblyRequired ?? this.assemblyRequired,
      roomId: roomId ?? this.roomId,
      roomLabel: roomLabel ?? this.roomLabel,
      supplierId: supplierId ?? this.supplierId,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      existingInStore: existingInStore ?? this.existingInStore,
      supplierReceived: supplierReceived ?? this.supplierReceived,
      readyForPickup: readyForPickup ?? this.readyForPickup,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      inventoryDeducted: inventoryDeducted ?? this.inventoryDeducted,
      warrantyYears: warrantyYears ?? this.warrantyYears,
      warrantyStartDate: warrantyStartDate ?? this.warrantyStartDate,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
