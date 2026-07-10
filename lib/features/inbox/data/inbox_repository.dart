import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class InboxRepository {
  InboxRepository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  String get _userId => _client.auth.currentUser!.id;

  Future<List<InboxItem>> list() async {
    final rows = await _client
        .from('tasks')
        .select()
        .order('sort_order')
        .order('created_at', ascending: false);
    return rows.map(InboxItem.fromMap).toList();
  }

  Future<void> createQuick(String content) async {
    final items = await list();
    final firstPosition = _itemsInColumn(items, InboxColumn.pending)
        .fold<double>(
          0,
          (minimum, item) => minimum < item.position ? minimum : item.position,
        );
    final now = DateTime.now().toUtc();
    await _client.from('tasks').insert({
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
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
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
    await _update(item.id, {
      'title': content,
      'item_type': isTopic
          ? InboxItemType.research.databaseValue
          : type?.databaseValue,
      'is_topic': isTopic,
      'due_date': action ? dueDate?.toIso8601String() : null,
      'priority': action ? (priority ?? 2) : null,
      'is_completed': action ? (isCompleted ?? false) : false,
      if (isTopic) 'parent_id': null,
    });
    if (item.isTopic && !isTopic) {
      await _client
          .from('tasks')
          .update({
            'parent_id': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('parent_id', item.id);
    }
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
    if (item.isTopic && archived) {
      await _client
          .from('tasks')
          .update({
            'parent_id': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('parent_id', item.id);
    }
    await _update(item.id, {'is_archived': archived});
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

  Future<void> delete(String id) async {
    await _client.from('tasks').delete().eq('id', id);
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

    await _writeOrder(target, destination);
    if (sourceColumn != destination) {
      await _writeOrder(source, sourceColumn);
    }
  }

  Future<void> _writeOrder(List<InboxItem> items, InboxColumn column) async {
    for (var index = 0; index < items.length; index++) {
      await _update(items[index].id, {
        'inbox_column': column.databaseValue,
        'sort_order': index.toDouble(),
        'parent_id': null,
      });
    }
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

  Future<void> _update(String id, Map<String, dynamic> values) async {
    await _client
        .from('tasks')
        .update({
          ...values,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }
}
