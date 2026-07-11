enum InboxItemType { idea, action, research, resource }

enum InboxColumn { focus, pending }

extension InboxItemTypeX on InboxItemType {
  String get databaseValue => name;

  String get label => switch (this) {
    InboxItemType.idea => '想法',
    InboxItemType.action => '行动',
    InboxItemType.research => '研究',
    InboxItemType.resource => '资料',
  };

  static InboxItemType? fromDatabase(String? value) {
    for (final type in InboxItemType.values) {
      if (type.databaseValue == value) {
        return type;
      }
    }
    return null;
  }
}

extension InboxColumnX on InboxColumn {
  String get databaseValue => switch (this) {
    InboxColumn.focus => 'focus',
    InboxColumn.pending => 'pending',
  };

  String get label => switch (this) {
    InboxColumn.focus => '关注中',
    InboxColumn.pending => '待整理',
  };

  static InboxColumn fromDatabase(String? value) {
    return value == 'focus' ? InboxColumn.focus : InboxColumn.pending;
  }
}

class InboxItem {
  const InboxItem({
    required this.id,
    required this.userId,
    required this.content,
    required this.column,
    required this.position,
    required this.isArchived,
    required this.isPinned,
    required this.isTopic,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.type,
    this.dueDate,
    this.priority,
    this.parentId,
  });

  final String id;
  final String userId;
  final String content;
  final InboxItemType? type;
  final InboxColumn column;
  final double position;
  final bool isArchived;
  final bool isPinned;
  final bool isTopic;
  final bool isCompleted;
  final DateTime? dueDate;
  final int? priority;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAction => type == InboxItemType.action && !isTopic;

  factory InboxItem.fromMap(Map<String, dynamic> map) {
    return InboxItem(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String,
      type: InboxItemTypeX.fromDatabase(map['item_type'] as String?),
      column: InboxColumnX.fromDatabase(map['inbox_column'] as String?),
      position: (map['position'] as num?)?.toDouble() ?? 0,
      isArchived: map['is_archived'] as bool? ?? false,
      isPinned: map['is_pinned'] as bool? ?? false,
      isTopic: map['is_topic'] as bool? ?? false,
      isCompleted: map['is_completed'] as bool? ?? false,
      dueDate: map['due_date'] == null
          ? null
          : DateTime.parse(map['due_date'] as String),
      priority: map['priority'] as int?,
      parentId: map['parent_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
