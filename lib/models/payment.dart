enum PaymentType { cash, credit, check, transfer }

extension PaymentTypeExtension on PaymentType {
  String get dbValue {
    switch (this) {
      case PaymentType.cash:
        return 'Cash';
      case PaymentType.credit:
        return 'Credit';
      case PaymentType.check:
        return 'Check';
      case PaymentType.transfer:
        return 'Transfer';
    }
  }

  static PaymentType fromString(String value) {
    switch (value) {
      case 'Cash':
        return PaymentType.cash;
      case 'Credit':
        return PaymentType.credit;
      case 'Check':
        return PaymentType.check;
      case 'Transfer':
        return PaymentType.transfer;
      default:
        return PaymentType.cash;
    }
  }
}

class Payment {
  final String id;
  final String customerId;
  final String? orderId;
  final DateTime date;
  final PaymentType type;
  final String cardName;
  final String customerName;
  final double amount;
  final String? imageUrl;
  final String? notes;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Payment({
    required this.id,
    required this.customerId,
    this.orderId,
    required this.date,
    this.type = PaymentType.cash,
    required this.cardName,
    required this.customerName,
    this.amount = 0,
    this.imageUrl,
    this.notes,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      orderId: json['order_id'] as String?,
      date: DateTime.parse(json['date'] as String),
      type: PaymentTypeExtension.fromString(json['type'] as String? ?? 'Cash'),
      cardName: json['card_name'] as String,
      customerName: json['customer_name'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      imageUrl: json['image_url'] as String?,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'order_id': orderId,
      'date': date.toIso8601String().split('T').first,
      'type': type.dbValue,
      'card_name': cardName,
      'customer_name': customerName,
      'amount': amount,
      'image_url': imageUrl,
      'notes': notes,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  Payment copyWith({
    String? id,
    String? customerId,
    String? orderId,
    DateTime? date,
    PaymentType? type,
    String? cardName,
    String? customerName,
    double? amount,
    String? imageUrl,
    String? notes,
    String? createdBy,
    String? updatedBy,
  }) {
    return Payment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      orderId: orderId ?? this.orderId,
      date: date ?? this.date,
      type: type ?? this.type,
      cardName: cardName ?? this.cardName,
      customerName: customerName ?? this.customerName,
      amount: amount ?? this.amount,
      imageUrl: imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
