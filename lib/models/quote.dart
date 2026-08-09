import 'quote_item.dart';

enum QuoteStatus { sent, accepted, converted, expired }

extension QuoteStatusExtension on QuoteStatus {
  String get dbValue {
    switch (this) {
      case QuoteStatus.sent:
        return 'Sent';
      case QuoteStatus.accepted:
        return 'Accepted';
      case QuoteStatus.converted:
        return 'Converted';
      case QuoteStatus.expired:
        return 'Expired';
    }
  }

  static QuoteStatus fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'accepted':
        return QuoteStatus.accepted;
      case 'converted':
        return QuoteStatus.converted;
      case 'expired':
        return QuoteStatus.expired;
      default:
        return QuoteStatus.sent;
    }
  }
}

class Quote {
  final String id;
  final String customerId;
  final int? quoteNumber;
  final QuoteStatus status;
  final String? notes;
  final double totalPrice;
  final bool vatEnabled;
  final String? pdfUrl;
  final String? convertedOrderId;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined
  final String? cardName;
  final String? customerName;
  final List<QuoteItem> items;

  Quote({
    required this.id,
    required this.customerId,
    this.quoteNumber,
    this.status = QuoteStatus.sent,
    this.notes,
    this.totalPrice = 0,
    this.vatEnabled = true,
    this.pdfUrl,
    this.convertedOrderId,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.cardName,
    this.customerName,
    this.items = const [],
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      quoteNumber: json['quote_number'] as int?,
      status: QuoteStatusExtension.fromString(
        json['status'] as String? ?? 'Sent',
      ),
      notes: json['notes'] as String?,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      vatEnabled: json['vat_enabled'] as bool? ?? true,
      pdfUrl: json['pdf_url'] as String?,
      convertedOrderId: json['converted_order_id'] as String?,
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
      items: json['quote_items'] != null
          ? (json['quote_items'] as List)
                .map((e) => QuoteItem.fromJson(e))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'status': status.dbValue,
      'notes': notes,
      'total_price': totalPrice,
      'vat_enabled': vatEnabled,
      'pdf_url': pdfUrl,
      'converted_order_id': convertedOrderId,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  Quote copyWith({
    String? id,
    String? customerId,
    int? quoteNumber,
    QuoteStatus? status,
    String? notes,
    double? totalPrice,
    bool? vatEnabled,
    String? pdfUrl,
    String? convertedOrderId,
    String? createdBy,
    String? updatedBy,
    String? cardName,
    String? customerName,
    List<QuoteItem>? items,
  }) {
    return Quote(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      totalPrice: totalPrice ?? this.totalPrice,
      vatEnabled: vatEnabled ?? this.vatEnabled,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      convertedOrderId: convertedOrderId ?? this.convertedOrderId,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      cardName: cardName ?? this.cardName,
      customerName: customerName ?? this.customerName,
      items: items ?? this.items,
    );
  }
}
