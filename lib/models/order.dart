import 'order_item.dart';

enum OrderStatus {
  active,
  preparing,
  sentToSupplier,
  inAssembly,
  awaitingShipping,
  handled,
  delivered,
  canceled,
}

extension OrderStatusExtension on OrderStatus {
  String get dbValue {
    switch (this) {
      case OrderStatus.active:
        return 'Active';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.sentToSupplier:
        return 'Sent to Supplier';
      case OrderStatus.inAssembly:
        return 'In Assembly';
      case OrderStatus.awaitingShipping:
        return 'Awaiting Shipping';
      case OrderStatus.handled:
        return 'Handled';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.canceled:
        return 'Canceled';
    }
  }

  static OrderStatus fromString(String value) {
    final v = value.trim();
    switch (v) {
      case 'Active':
        return OrderStatus.active;
      case 'Preparing':
        return OrderStatus.preparing;
      case 'Sent to Supplier':
        return OrderStatus.sentToSupplier;
      case 'In Assembly':
        return OrderStatus.inAssembly;
      case 'Awaiting Shipping':
        return OrderStatus.awaitingShipping;
      case 'Handled':
        return OrderStatus.handled;
      case 'Delivered':
        return OrderStatus.delivered;
      case 'Canceled':
        return OrderStatus.canceled;
      default:
        // Avoid collapsing unknown DB values to Active (hides real workflow).
        final lower = v.toLowerCase();
        if (lower == 'preparing') return OrderStatus.preparing;
        if (lower == 'sent to supplier') return OrderStatus.sentToSupplier;
        if (lower == 'in assembly') return OrderStatus.inAssembly;
        if (lower == 'awaiting shipping') return OrderStatus.awaitingShipping;
        if (lower == 'handled') return OrderStatus.handled;
        if (lower == 'delivered') return OrderStatus.delivered;
        if (lower == 'canceled' || lower == 'cancelled') {
          return OrderStatus.canceled;
        }
        if (lower == 'active') return OrderStatus.active;
        return OrderStatus.active;
    }
  }

  /// All statuses in display order (for filters and status change menu).
  static List<OrderStatus> get all => [
        OrderStatus.active,
        OrderStatus.preparing,
        OrderStatus.sentToSupplier,
        OrderStatus.inAssembly,
        OrderStatus.awaitingShipping,
        OrderStatus.handled,
        OrderStatus.delivered,
        OrderStatus.canceled,
      ];
}

class Order {
  final String id;
  final String customerId;
  final int? orderNumber;
  final bool assemblyRequired;
  final DateTime? assemblyDate;
  final DateTime? deliveryDate;
  /// One-time installation / assembly fee (ILS), admin-entered.
  final double assemblyPrice;
  final OrderStatus status;
  final double totalPrice;
  /// Whether 18% VAT is applied to the order total. Default true.
  final bool vatEnabled;
  /// Discount percentage (0–100) applied to the VAT-inclusive grand total.
  final double discountPercentage;
  /// Discount type: 'percentage' or 'fixed_amount'. Default 'percentage'.
  final String discountType;
  final String? notes;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined data
  final String? cardName;
  final String? customerName;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.customerId,
    this.orderNumber,
    this.assemblyRequired = false,
    this.assemblyDate,
    this.deliveryDate,
    this.assemblyPrice = 0,
    this.status = OrderStatus.active,
    this.totalPrice = 0,
    this.vatEnabled = true,
    this.discountPercentage = 0,
    this.discountType = 'percentage',
    this.notes,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.cardName,
    this.customerName,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      orderNumber: json['order_number'] as int?,
      assemblyRequired: json['assembly_required'] as bool? ?? false,
      assemblyDate: json['assembly_date'] != null
          ? DateTime.parse(json['assembly_date'] as String)
          : null,
      deliveryDate: json['delivery_date'] != null
          ? DateTime.parse(json['delivery_date'] as String)
          : null,
      assemblyPrice: (json['assembly_price'] as num?)?.toDouble() ?? 0,
      status: OrderStatusExtension.fromString(
        json['status'] as String? ?? 'Active',
      ),
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      vatEnabled: json['vat_enabled'] as bool? ?? true,
      discountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0,
      discountType: (json['discount_type'] as String?) ?? 'percentage',
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      cardName: json['customers'] != null
          ? json['customers']['card_name'] as String?
          : null,
      customerName: json['customers'] != null
          ? json['customers']['customer_name'] as String?
          : null,
      items: json['order_items'] != null
          ? (json['order_items'] as List)
                .map((e) => OrderItem.fromJson(e))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'assembly_required': assemblyRequired,
      'assembly_date': assemblyDate?.toIso8601String().split('T').first,
      'delivery_date': deliveryDate?.toIso8601String().split('T').first,
      'assembly_price': assemblyPrice,
      'status': status.dbValue,
      'total_price': totalPrice,
      'vat_enabled': vatEnabled,
      'discount_percentage': discountPercentage,
      'discount_type': discountType,
      'notes': notes,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  Order copyWith({
    String? id,
    String? customerId,
    int? orderNumber,
    bool? assemblyRequired,
    DateTime? assemblyDate,
    DateTime? deliveryDate,
    double? assemblyPrice,
    OrderStatus? status,
    double? totalPrice,
    bool? vatEnabled,
    double? discountPercentage,
    String? discountType,
    String? notes,
    String? createdBy,
    String? updatedBy,
    String? cardName,
    String? customerName,
    List<OrderItem>? items,
  }) {
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      orderNumber: orderNumber ?? this.orderNumber,
      assemblyRequired: assemblyRequired ?? this.assemblyRequired,
      assemblyDate: assemblyDate ?? this.assemblyDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      assemblyPrice: assemblyPrice ?? this.assemblyPrice,
      status: status ?? this.status,
      totalPrice: totalPrice ?? this.totalPrice,
      vatEnabled: vatEnabled ?? this.vatEnabled,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      discountType: discountType ?? this.discountType,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      cardName: cardName ?? this.cardName,
      customerName: customerName ?? this.customerName,
      items: items ?? this.items,
    );
  }
}
