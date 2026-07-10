import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:uuid/uuid.dart';

class InboxRepository {
  InboxRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<InboxItem>> watch() {
    return _database
        .watchTasks(_userId)
        .map(
          (rows) => rows
              .map((row) => InboxItem.fromMap(localTaskToRemoteMap(row)))
              .toList(),
        );
  }

  Future<List<InboxItem>> list() async {
    final rows = await _database.listTasks(_userId);
    return rows
        .map((row) => InboxItem.fromMap(localTaskToRemoteMap(row)))
        .toList();
  }

  Future<void> createQuick(String content) async {
    final items = await list();
    final firstPosition = _itemsInColumn(items, InboxColumn.pending)
        .fold<double>(
          0,
          (minimum, item) => minimum < item.position ? minimum : item.position,
        );
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.saveTask({
      'id': _uuid.v4(),
      'user_id': _userId,
      'title': content,
      'note': null,
      'item_type': null,
      'inbox_column': InboxColumn.pending.databaseValue,
      'sort_order': firstPosition - 1,
      'is_archived': false,
      'is_pinned': false,
      'is_topic': false,
      'parent_id': null,
      'due_date': null,
      'priority': null,
      'is_completed': false,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> save({
    required InboxItem item,
    required String content,
    required InboxItemType? type,
    required bool isTopic,
    DateTime? dueDate,
    int? priority,
    bool? isCompleted,
  }) async {
    final action = type == InboxItemType.action && !isTopic;
    final mutations = <TaskMutation>[
      TaskMutation(item.id, {
        'title': content,
        'item_type': isTopic
            ? InboxItemType.research.databaseValue
            : type?.databaseValue,
        'is_topic': isTopic,
        'due_date': action ? dueDate?.toIso8601String().split('T').first : null,
        'priority': action ? (priority ?? 2) : null,
        'is_completed': action ? (isCompleted ?? false) : false,
        if (isTopic) 'parent_id': null,
      }),
    ];
    if (item.isTopic && !isTopic) {
      final items = await list();
      mutations.addAll(
        items
            .where((candidate) => candidate.parentId == item.id)
            .map(
              (candidate) => TaskMutation(candidate.id, {'parent_id': null}),
            ),
      );
    }
    await _database.updateTasks(_userId, mutations);
  }

  Future<void> setCompleted(InboxItem item, bool completed) {
    return _update(item.id, {'is_completed': completed});
  }

  Future<void> setType(InboxItem item, InboxItemType? type) {
    return _update(item.id, {
      'item_type': type?.databaseValue,
      if (type == InboxItemType.action) 'priority': item.priority ?? 2,
      if (type != InboxItemType.action) ...{
        'due_date': null,
        'priority': null,
        'is_completed': false,
      },
    });
  }

  Future<void> convertToAction(InboxItem item) {
    return _update(item.id, {
      'item_type': InboxItemType.action.databaseValue,
      'is_topic': false,
      'priority': item.priority ?? 2,
    });
  }

  Future<void> setArchived(InboxItem item, bool archived) async {
    final mutations = <TaskMutation>[
      TaskMutation(item.id, {'is_archived': archived}),
    ];
    if (item.isTopic && archived) {
      final items = await list();
      mutations.addAll(
        items
            .where((candidate) => candidate.parentId == item.id)
            .map(
              (candidate) => TaskMutation(candidate.id, {'parent_id': null}),
            ),
      );
    }
    await _database.updateTasks(_userId, mutations);
  }

  Future<void> togglePinned(InboxItem item, List<InboxItem> allItems) async {
    final pinned = !item.isPinned;
    final values = <String, dynamic>{'is_pinned': pinned};
    if (pinned) {
      final peers = _itemsInColumn(allItems, item.column);
      final first = peers.isEmpty ? 0.0 : peers.first.position;
      values['sort_order'] = first - 1;
    }
    await _update(item.id, values);
  }

  Future<void> assignToTopic(InboxItem item, String? topicId) {
    return _update(item.id, {'parent_id': topicId});
  }

  Future<void> delete(String id) {
    return _database.deleteTask(_userId, id);
  }

  Future<void> moveToEdge(
    InboxItem item,
    InboxColumn column,
    bool first,
    List<InboxItem> allItems,
  ) async {
    final peers = _itemsInColumn(
      allItems,
      column,
    ).where((candidate) => candidate.id != item.id).toList();
    final position = peers.isEmpty
        ? 0.0
        : first
        ? peers.first.position - 1
        : peers.last.position + 1;
    await _update(item.id, {
      'inbox_column': column.databaseValue,
      'sort_order': position,
      'parent_id': null,
    });
  }

  Future<void> moveBefore(
    InboxItem item,
    InboxColumn destination,
    String? targetId,
    List<InboxItem> allItems,
  ) async {
    if (item.id == targetId) {
      return;
    }
    final sourceColumn = item.column;
    final source = _itemsInColumn(
      allItems,
      sourceColumn,
    ).where((candidate) => candidate.id != item.id).toList();
    final target = sourceColumn == destination
        ? source
        : _itemsInColumn(
            allItems,
            destination,
          ).where((candidate) => candidate.id != item.id).toList();
    final index = targetId == null
        ? target.length
        : target.indexWhere((candidate) => candidate.id == targetId);
    target.insert(index < 0 ? target.length : index, item);

    final mutations = _orderMutations(target, destination);
    if (sourceColumn != destination) {
      mutations.addAll(_orderMutations(source, sourceColumn));
    }
    await _database.updateTasks(_userId, mutations);
  }

  List<TaskMutation> _orderMutations(
    List<InboxItem> items,
    InboxColumn column,
  ) {
    return [
      for (var index = 0; index < items.length; index++)
        TaskMutation(items[index].id, {
          'inbox_column': column.databaseValue,
          'sort_order': index.toDouble(),
          'parent_id': null,
        }),
    ];
  }

  List<InboxItem> _itemsInColumn(List<InboxItem> items, InboxColumn column) {
    final result = items
        .where(
          (item) =>
              item.column == column &&
              item.parentId == null &&
              !item.isArchived,
        )
        .toList();
    result.sort((a, b) => a.position.compareTo(b.position));
    return result;
  }

  Future<void> _update(String id, Map<String, dynamic> values) {
    return _database.updateTasks(_userId, [TaskMutation(id, values)]);
  }
}
