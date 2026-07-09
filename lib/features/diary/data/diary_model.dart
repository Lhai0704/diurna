class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.userId,
    required this.entryDate,
    required this.title,
    required this.content,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.mood,
  });

  final String id;
  final String userId;
  final DateTime entryDate;
  final String title;
  final String content;
  final String? mood;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DiaryEntry.fromMap(Map<String, dynamic> map) {
    return DiaryEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      entryDate: DateTime.parse(map['entry_date'] as String),
      title: map['title'] as String,
      content: map['content'] as String,
      mood: map['mood'] as String?,
      tags: ((map['tags'] as List?) ?? const []).cast<String>(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
