class Task {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.dueDate,
    this.priority = 2,
  });

  final String id;
  final String userId;
  final String title;
  final String? note;
  final DateTime? dueDate;
  final int priority;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      dueDate: map['due_date'] == null
          ? null
          : DateTime.parse(map['due_date'] as String),
      priority: map['priority'] as int? ?? 2,
      isCompleted: map['is_completed'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toUpsertMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'note': note,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'is_completed': isCompleted,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
