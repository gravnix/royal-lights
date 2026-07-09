import 'fixing_ticket_item.dart';

enum FixingTicketStatus {
  pending,
  fixed,
}

extension FixingTicketStatusX on FixingTicketStatus {
  String get dbValue => switch (this) {
        FixingTicketStatus.pending => 'Pending',
        FixingTicketStatus.fixed => 'Fixed',
      };

  static FixingTicketStatus fromDb(String? v) => switch (v) {
        'Fixed' => FixingTicketStatus.fixed,
        _ => FixingTicketStatus.pending,
      };
}

class FixingTicket {
  final String id;
  final String customerId;
  final FixingTicketStatus status;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? fixedAt;

  // Joined (customers)
  final String? cardName;
  final String? customerName;

  // Embedded
  final List<FixingTicketItem> items;

  FixingTicket({
    required this.id,
    required this.customerId,
    this.status = FixingTicketStatus.pending,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.fixedAt,
    this.cardName,
    this.customerName,
    this.items = const [],
  });

  factory FixingTicket.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['fixing_ticket_items'] as List?) ?? const [];
    return FixingTicket(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      status: FixingTicketStatusX.fromDb(json['status'] as String?),
      createdBy: json['created_by'] as String?,
      updatedBy: json['updated_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      fixedAt:
          json['fixed_at'] != null ? DateTime.parse(json['fixed_at']) : null,
      cardName: json['customers'] != null
          ? json['customers']['card_name'] as String?
          : null,
      customerName: json['customers'] != null
          ? json['customers']['customer_name'] as String?
          : null,
      items: itemsJson
          .map((e) => FixingTicketItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

