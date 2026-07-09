class InventoryItem {
  final String id;
  final String description;
  final String? supplierId;
  final String? imageUrl;
  final String? brand;
  final String? barcode;
  final double? consumerPrice;
  final int availableStock;
  final bool isWeighted;
  final bool isVatExempt;
  /// 0 = none, 3 = three-year, 5 = five-year warranty.
  final int warrantyYears;
  final bool autoRestockEnabled;
  /// When `availableStock` drops below this number, a restock order is created.
  /// `0` disables threshold checks.
  final int autoRestockThreshold;
  /// Quantity to request when auto-restock triggers (min 1).
  final int autoRestockQuantity;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    required this.id,
    required this.description,
    this.supplierId,
    this.imageUrl,
    this.brand,
    this.barcode,
    this.consumerPrice,
    this.availableStock = 0,
    this.isWeighted = false,
    this.isVatExempt = false,
    this.warrantyYears = 0,
    this.autoRestockEnabled = false,
    this.autoRestockThreshold = 0,
    this.autoRestockQuantity = 1,
    this.createdAt,
    this.updatedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      description: json['description'] as String? ?? '',
      supplierId: json['supplier_id'] as String?,
      imageUrl: json['image_url'] as String?,
      brand: json['brand'] as String?,
      barcode: json['barcode'] as String?,
      consumerPrice: (json['consumer_price'] as num?)?.toDouble(),
      availableStock: (json['available_stock'] as num?)?.toInt() ?? 0,
      isWeighted: json['is_weighted'] as bool? ?? false,
      isVatExempt: json['is_vat_exempt'] as bool? ?? false,
      warrantyYears: (json['warranty_years'] as num?)?.toInt() ?? 0,
      autoRestockEnabled: json['auto_restock_enabled'] as bool? ?? false,
      autoRestockThreshold: (json['auto_restock_threshold'] as num?)?.toInt() ?? 0,
      autoRestockQuantity: (json['auto_restock_quantity'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'supplier_id': supplierId,
      'image_url': imageUrl,
      'brand': brand,
      'barcode': barcode,
      'consumer_price': consumerPrice,
      'available_stock': availableStock,
      'is_weighted': isWeighted,
      'is_vat_exempt': isVatExempt,
      'warranty_years': warrantyYears,
      'auto_restock_enabled': autoRestockEnabled,
      'auto_restock_threshold': autoRestockThreshold,
      'auto_restock_quantity': autoRestockQuantity,
    };
  }

  InventoryItem copyWith({
    String? id,
    String? description,
    String? supplierId,
    String? imageUrl,
    String? brand,
    String? barcode,
    double? consumerPrice,
    int? availableStock,
    bool? isWeighted,
    bool? isVatExempt,
    int? warrantyYears,
    bool? autoRestockEnabled,
    int? autoRestockThreshold,
    int? autoRestockQuantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      description: description ?? this.description,
      supplierId: supplierId ?? this.supplierId,
      imageUrl: imageUrl ?? this.imageUrl,
      brand: brand ?? this.brand,
      barcode: barcode ?? this.barcode,
      consumerPrice: consumerPrice ?? this.consumerPrice,
      availableStock: availableStock ?? this.availableStock,
      isWeighted: isWeighted ?? this.isWeighted,
      isVatExempt: isVatExempt ?? this.isVatExempt,
      warrantyYears: warrantyYears ?? this.warrantyYears,
      autoRestockEnabled: autoRestockEnabled ?? this.autoRestockEnabled,
      autoRestockThreshold: autoRestockThreshold ?? this.autoRestockThreshold,
      autoRestockQuantity: autoRestockQuantity ?? this.autoRestockQuantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

