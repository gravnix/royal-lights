class QuoteItem {
  final String? id;
  final String? quoteId;
  final String? itemNumber;
  final String name;
  final String? imageUrl;
  final double quantity;
  final String? extras;
  final double price;
  final double extrasPrice;
  final String? notes;
  final DateTime? createdAt;

  QuoteItem({
    this.id,
    this.quoteId,
    this.itemNumber,
    required this.name,
    this.imageUrl,
    this.quantity = 1,
    this.extras,
    this.price = 0,
    this.extrasPrice = 0,
    this.notes,
    this.createdAt,
  });

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    return QuoteItem(
      id: json['id'] as String?,
      quoteId: json['quote_id'] as String?,
      itemNumber: json['item_number'] as String?,
      name: json['name'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      extras: json['extras'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      extrasPrice: (json['extras_price'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null && id!.trim().isNotEmpty) 'id': id,
      if (quoteId != null) 'quote_id': quoteId,
      'item_number': itemNumber,
      'name': name,
      'image_url': imageUrl,
      'quantity': quantity,
      'extras': extras,
      'price': price,
      'extras_price': extrasPrice,
      'notes': notes,
    };
  }

  QuoteItem copyWith({
    String? id,
    String? quoteId,
    String? itemNumber,
    String? name,
    String? imageUrl,
    double? quantity,
    String? extras,
    double? price,
    double? extrasPrice,
    String? notes,
  }) {
    return QuoteItem(
      id: id ?? this.id,
      quoteId: quoteId ?? this.quoteId,
      itemNumber: itemNumber ?? this.itemNumber,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      quantity: quantity ?? this.quantity,
      extras: extras ?? this.extras,
      price: price ?? this.price,
      extrasPrice: extrasPrice ?? this.extrasPrice,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  double get lineTotal => (price + extrasPrice) * quantity;
}
