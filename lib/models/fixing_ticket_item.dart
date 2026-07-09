class FixingTicketItem {
  final String id;
  final String ticketId;
  final String? sourceOrderId;
  final String? sourceOrderItemId;
  final String name;
  final String? itemNumber;
  final int quantity;
  final String? notes;
  final int warrantyYears;
  final DateTime? deliveryDate;

  FixingTicketItem({
    required this.id,
    required this.ticketId,
    this.sourceOrderId,
    this.sourceOrderItemId,
    required this.name,
    this.itemNumber,
    this.quantity = 1,
    this.notes,
    this.warrantyYears = 0,
    this.deliveryDate,
  });

  factory FixingTicketItem.fromJson(Map<String, dynamic> json) {
    return FixingTicketItem(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      sourceOrderId: json['source_order_id'] as String?,
      sourceOrderItemId: json['source_order_item_id'] as String?,
      name: json['name'] as String? ?? '',
      itemNumber: json['item_number'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
      warrantyYears: (json['warranty_years'] as num?)?.toInt() ?? 0,
      deliveryDate: json['delivery_date'] != null
          ? DateTime.parse(json['delivery_date'])
          : null,
    );
  }

  DateTime? get warrantyEndDate {
    if (deliveryDate == null || warrantyYears <= 0) return null;
    return DateTime(
      deliveryDate!.year + warrantyYears,
      deliveryDate!.month,
      deliveryDate!.day,
    );
  }
}

