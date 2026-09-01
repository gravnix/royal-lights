/// A dated reminder / note shown on the dashboard calendar.
/// Shared across all users — everyone sees every note.
class TimelineNote {
  final String id;

  /// Date-only column: the day the reminder is for.
  final DateTime noteDate;
  final String title;
  final String? body;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TimelineNote({
    required this.id,
    required this.noteDate,
    this.title = '',
    this.body,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory TimelineNote.fromJson(Map<String, dynamic> json) {
    return TimelineNote(
      id: json['id'] as String,
      noteDate: DateTime.parse(json['note_date'] as String),
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
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
      // Date-only column — send YYYY-MM-DD, never a full timestamp.
      'note_date': noteDate.toIso8601String().split('T').first,
      'title': title,
      'body': body,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  TimelineNote copyWith({
    String? id,
    DateTime? noteDate,
    String? title,
    String? body,
    String? createdBy,
    String? updatedBy,
  }) {
    return TimelineNote(
      id: id ?? this.id,
      noteDate: noteDate ?? this.noteDate,
      title: title ?? this.title,
      body: body ?? this.body,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
