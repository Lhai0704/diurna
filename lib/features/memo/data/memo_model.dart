class Memo {
  const Memo({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String content;
  final double position;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Memo.fromMap(Map<String, dynamic> map) {
    return Memo(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String? ?? '',
      position: (map['position'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
