import '../../../contracts/errors.dart';
import 'package:diurna_core/src/core/database/app_database.dart';
import 'package:diurna_core/src/features/inbox/data/inbox_item.dart';
import 'package:uuid/uuid.dart';

class InboxRepository {
  InboxRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<InboxItem>> watch() {
    return _database
        .watchInboxItems(_userId)
        .map(
          (rows) => rows
              .map((row) => InboxItem.fromMap(localInboxItemToRemoteMap(row)))
              .toList(),
        );
  }

  Future<List<InboxItem>> list() async {
    final rows = await _database.listInboxItems(_userId);
    return rows
        .map((row) => InboxItem.fromMap(localInboxItemToRemoteMap(row)))
        .toList();
  }

  Future<InboxItem> get(String id) async =>
      InboxItem.fromMap(await _database.entity(_userId, 'inbox_items', id));

  Future<String> createQuick(String content) => _database.transaction(() async {
    content = requiredText(content, 'content');
    final id = _uuid.v4();
    final items = await list();
    final firstPosition = _itemsInColumn(items, InboxColumn.pending)
        .fold<double>(
          0,
          (minimum, item) => minimum < item.position ? minimum : item.position,
        );
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.saveInboxItem({
      'id': id,
      'user_id': _userId,
      'content': content,
      'item_type': null,
      'inbox_column': InboxColumn.pending.databaseValue,
      'position': firstPosition - 1,
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
    return id;
  });

  Future<void> save({
    required InboxItem item,
    required String content,
    required InboxItemType? type,
    required bool isTopic,
    DateTime? dueDate,
    int? priority,
    bool? isCompleted,
  }) => _database.transaction(() async {
    content = requiredText(content, 'content');
    await _database.checkVersion(_userId, 'inbox_items', item.id, item.version);
    if (priority != null && (priority < 1 || priority > 3)) {
      throw const DiurnaException('VALIDATION', 'Priority must be 1..3');
    }
    final action = type == InboxItemType.action && !isTopic;
    final mutations = <InboxItemMutation>[
      InboxItemMutation(item.id, {
        'content': content,
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
              (candidate) =>
                  InboxItemMutation(candidate.id, {'parent_id': null}),
            ),
      );
    }
    await _database.updateInboxItems(_userId, mutations);
  });

  Future<void> setCompleted(InboxItem item, bool completed) =>
      _database.transaction(() async {
        item = await get(item.id);
        if (!item.isAction) {
          throw const DiurnaException(
            'VALIDATION',
            'Only actions can be completed',
          );
        }
        return _update(item.id, {'is_completed': completed});
      });

  Future<void> setType(InboxItem item, InboxItemType? type) =>
      _database.transaction(() async {
        item = await get(item.id);
        if (item.isTopic) {
          throw const DiurnaException('VALIDATION', 'Use topic conversion');
        }
        await save(
          item: item,
          content: item.content,
          type: type,
          isTopic: false,
          dueDate: item.dueDate,
          priority: item.priority,
          isCompleted: item.isCompleted,
        );
      });
  Future<void> convertToAction(InboxItem item) =>
      _database.transaction(() async {
        item = await get(item.id);
        await save(
          item: item,
          content: item.content,
          type: InboxItemType.action,
          isTopic: false,
          dueDate: item.dueDate,
          priority: item.priority,
          isCompleted: item.isCompleted,
        );
      });

  Future<void> setArchived(InboxItem item, bool archived) =>
      _database.transaction(() async {
        item = await get(item.id);
        final mutations = <InboxItemMutation>[
          InboxItemMutation(item.id, {'is_archived': archived}),
        ];
        if (item.isTopic && archived) {
          final items = await list();
          mutations.addAll(
            items
                .where((candidate) => candidate.parentId == item.id)
                .map(
                  (candidate) =>
                      InboxItemMutation(candidate.id, {'parent_id': null}),
                ),
          );
        }
        await _database.updateInboxItems(_userId, mutations);
      });

  Future<void> togglePinned(InboxItem item, List<InboxItem> allItems) =>
      _database.transaction(() async {
        item = await get(item.id);
        allItems = await list();
        final pinned = !item.isPinned;
        final values = <String, dynamic>{'is_pinned': pinned};
        if (pinned) {
          final peers = _itemsInColumn(allItems, item.column);
          final first = peers.isEmpty ? 0.0 : peers.first.position;
          values['position'] = first - 1;
        }
        await _update(item.id, values);
      });

  Future<void> assignToTopic(InboxItem item, String? topicId) =>
      _database.transaction(() async {
        item = await get(item.id);
        if (topicId != null) {
          final parent = await get(topicId);
          if (item.isTopic ||
              item.id == topicId ||
              !parent.isTopic ||
              parent.isArchived ||
              parent.parentId != null) {
            throw const DiurnaException(
              'VALIDATION',
              'Invalid topic relationship',
            );
          }
        }
        return _update(item.id, {'parent_id': topicId});
      });

  Future<void> delete(String id) => _database.transaction(() async {
    await _database.entity(_userId, 'inbox_items', id);
    return _database.deleteInboxItem(_userId, id);
  });

  Future<void> moveToEdge(
    InboxItem item,
    InboxColumn column,
    bool first,
    List<InboxItem> allItems,
  ) => _database.transaction(() async {
    item = await get(item.id);
    allItems = await list();
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
      'position': position,
      'parent_id': null,
    });
  });

  Future<void> moveBefore(
    InboxItem item,
    InboxColumn destination,
    String? targetId,
    List<InboxItem> allItems,
  ) => _database.transaction(() async {
    item = await get(item.id);
    allItems = await list();
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
    if (index < 0) {
      throw const DiurnaException(
        'NOT_FOUND',
        'Move target not found in destination',
      );
    }
    target.insert(index, item);

    final mutations = _orderMutations(target, destination);
    if (sourceColumn != destination) {
      mutations.addAll(_orderMutations(source, sourceColumn));
    }
    await _database.updateInboxItems(_userId, mutations);
  });

  List<InboxItemMutation> _orderMutations(
    List<InboxItem> items,
    InboxColumn column,
  ) {
    return [
      for (var index = 0; index < items.length; index++)
        InboxItemMutation(items[index].id, {
          'inbox_column': column.databaseValue,
          'position': index.toDouble(),
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
    return _database.updateInboxItems(_userId, [InboxItemMutation(id, values)]);
  }
}
