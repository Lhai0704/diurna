class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.userId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
    this.location,
    this.note,
    this.remindAt,
  });

  final String id;
  final String userId;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? location;
  final String? note;
  final DateTime? remindAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      startsAt: DateTime.parse(map['starts_at'] as String),
      endsAt: DateTime.parse(map['ends_at'] as String),
      location: map['location'] as String?,
      note: map['note'] as String?,
      remindAt: map['remind_at'] == null
          ? null
          : DateTime.parse(map['remind_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
