import 'dart:convert';
import 'package:drift/drift.dart';
import '../contracts/errors.dart';
import '../contracts/patches.dart';
import '../core/database/app_database.dart';
import '../features/inbox/data/inbox_item.dart';
import '../features/inbox/data/inbox_repository.dart';
import '../features/calendar/data/calendar_repository.dart';
import '../features/diary/data/diary_repository.dart';
import '../features/memo/data/memo_repository.dart';

enum EntityKind {
  inbox('inbox_items'),
  calendar('calendar_events'),
  diary('diary_entries'),
  memos('memos');

  const EntityKind(this.table);
  final String table;
}

class DiurnaService {
  DiurnaService(this.database, this.userId)
    : inbox = InboxRepository(database, userId),
      calendar = CalendarRepository(database, userId),
      diary = DiaryRepository(database, userId),
      memos = MemoRepository(database, userId);
  final AppDatabase database;
  final String userId;
  final InboxRepository inbox;
  final CalendarRepository calendar;
  final DiaryRepository diary;
  final MemoRepository memos;

  Future<Map<String, dynamic>> get(EntityKind kind, String id) async {
    final row = await database.entity(userId, kind.table, id);
    return {...row, 'type': kind.name, 'version': entityVersion(row)};
  }

  Future<Map<String, dynamic>> list(
    EntityKind kind, {
    String? id,
    String? query,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
    bool? archived,
    bool? completed,
    InboxColumn? column,
    InboxItemType? itemType,
    String? topicId,
  }) async {
    if (limit < 1 || limit > 200 || offset < 0) {
      throw const DiurnaException('VALIDATION', 'Invalid pagination');
    }
    if (from != null && to != null && from.isAfter(to)) {
      throw const DiurnaException('VALIDATION', 'from must not follow to');
    }
    if (id != null) {
      return {
        'items': [await get(kind, id)],
        'total': 1,
        'nextOffset': null,
      };
    }
    final rows = switch (kind) {
      EntityKind.inbox => (await database.listInboxItems(
        userId,
      )).map(localInboxItemToRemoteMap).toList(),
      EntityKind.calendar => (await database.listCalendarEvents(
        userId,
      )).map(localCalendarEventToRemoteMap).toList(),
      EntityKind.diary => (await database.listDiaryEntries(
        userId,
      )).map(localDiaryEntryToRemoteMap).toList(),
      EntityKind.memos => (await database.listMemos(
        userId,
      )).map(localMemoToRemoteMap).toList(),
    };
    final matches = rows.where((r) {
      if (kind == EntityKind.inbox) {
        if (archived != null && r['is_archived'] != archived) return false;
        if (column != null && r['inbox_column'] != column.name) return false;
        if (itemType != null && r['item_type'] != itemType.name) return false;
        if (topicId != null && r['parent_id'] != topicId) return false;
      }
      if (completed != null && r['is_completed'] != completed) return false;
      final date = DateTime.parse(
        (r['event_date'] ?? r['entry_date'] ?? r['due_date'] ?? r['updated_at'])
            as String,
      );
      final day = DateTime(date.year, date.month, date.day);
      if (from != null && day.isBefore(from) || to != null && day.isAfter(to)) {
        return false;
      }
      if (query != null) {
        final haystack = [
          r['content'],
          r['title'],
          r['note'],
          ...(r['tags'] as List? ?? []),
        ].whereType<String>().join('\n').toLowerCase();
        if (!haystack.contains(query.toLowerCase())) return false;
      }
      return true;
    }).toList();
    final items = <Map<String, dynamic>>[];
    for (final row in matches.skip(offset).take(limit)) {
      items.add(await get(kind, row['id'] as String));
    }
    return {
      'items': items,
      'total': matches.length,
      'nextOffset': offset + items.length < matches.length
          ? offset + items.length
          : null,
    };
  }

  Future<Map<String, dynamic>> search(
    String query, {
    List<EntityKind>? modules,
    DateTime? from,
    DateTime? to,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    requiredText(query, 'query');
    final result = <String, dynamic>{};
    for (final kind in modules ?? EntityKind.values) {
      final page = await list(
        kind,
        query: query,
        from: from,
        to: to,
        archived: includeArchived ? null : false,
        limit: limit,
        offset: offset,
      );
      page['items'] = (page['items'] as List<Map<String, dynamic>>)
          .map(
            (r) => {
              'type': kind.name,
              'id': r['id'],
              'version': r['version'],
              'summary': (r['title'] ?? r['content']).toString().substring(
                0,
                (r['title'] ?? r['content']).toString().length.clamp(0, 240),
              ),
              'relevantDate':
                  r['event_date'] ??
                  r['entry_date'] ??
                  r['due_date'] ??
                  r['updated_at'],
              'status': {
                'completed': r['is_completed'],
                'archived': r['is_archived'],
                'column': r['inbox_column'],
              },
            },
          )
          .toList();
      result[kind.name] = page;
    }
    return result;
  }

  Future<Map<String, dynamic>> _create(
    EntityKind kind,
    String? requestId,
    Object fingerprint,
    Future<String> Function() create,
  ) => database.transaction(() async {
    final encoded = jsonEncode(fingerprint);
    if (requestId != null) {
      final old = await database
          .customSelect(
            'SELECT * FROM machine_requests WHERE user_id=? AND request_id=?',
            variables: [Variable(userId), Variable(requestId)],
          )
          .getSingleOrNull();
      if (old != null) {
        if (old.read<String>('fingerprint') != encoded) {
          throw const DiurnaException(
            'CONFLICT',
            'Request ID was used with different content',
          );
        }
        return get(kind, old.read<String>('entity_id'));
      }
    }
    final id = await create();
    if (requestId != null) {
      await database.customStatement(
        'INSERT INTO machine_requests VALUES (?,?,?,?)',
        [userId, requestId, encoded, id],
      );
    }
    return get(kind, id);
  });

  Future<Map<String, dynamic>> createInbox(
    String content, {
    String? requestId,
  }) => _create(EntityKind.inbox, requestId, [
    'inbox',
    content,
  ], () => inbox.createQuick(content));
  Future<Map<String, dynamic>> createCalendar({
    required String title,
    required DateTime date,
    String? note,
    DateTime? remindAt,
    String? requestId,
  }) => _create(
    EntityKind.calendar,
    requestId,
    [
      'calendar',
      title,
      date.toIso8601String(),
      note,
      remindAt?.toIso8601String(),
    ],
    () => calendar.save(
      title: title,
      scheduledDate: date,
      note: note,
      remindAt: remindAt,
    ),
  );
  Future<Map<String, dynamic>> createMemo({
    required String title,
    String content = '',
    String? requestId,
  }) => _create(EntityKind.memos, requestId, [
    'memos',
    title,
    content,
  ], () => memos.save(title: title, content: content));
  Future<Map<String, dynamic>> createDiary({
    required String title,
    required String content,
    required DateTime date,
    String? mood,
    List<String> tags = const [],
    String? requestId,
  }) => _create(
    EntityKind.diary,
    requestId,
    ['diary', title, content, date.toIso8601String(), mood, tags],
    () => diary.save(
      title: title,
      content: content,
      entryDate: date,
      mood: mood,
      tags: tags,
    ),
  );

  Future<Map<String, dynamic>> _change(
    EntityKind kind,
    String id,
    String version,
    Future<void> Function() change,
  ) => database.transaction(() async {
    await database.checkVersion(userId, kind.table, id, version);
    await change();
    return get(kind, id);
  });
  Future<Map<String, dynamic>> updateInbox(
    String id,
    String version,
    InboxPatch patch,
  ) => _change(EntityKind.inbox, id, version, () async {
    final old = await inbox.get(id);
    final type = patch.type.or(old.type);
    final topic = patch.isTopic ?? old.isTopic;
    if ((patch.completed != null ||
            patch.priority.supplied ||
            patch.dueDate.supplied) &&
        (type != InboxItemType.action || topic)) {
      throw const DiurnaException(
        'VALIDATION',
        'Action fields require an action',
      );
    }
    await inbox.save(
      item: old,
      content: patch.content ?? old.content,
      type: type,
      isTopic: topic,
      dueDate: patch.dueDate.or(old.dueDate),
      priority: patch.priority.or(old.priority),
      isCompleted: patch.completed ?? old.isCompleted,
    );
    if (patch.pinned != null && patch.pinned != old.isPinned) {
      await inbox.togglePinned(await inbox.get(id), await inbox.list());
    }
  });
  Future<Map<String, dynamic>> archiveInbox(
    String id,
    String version,
    bool archived,
  ) => _change(
    EntityKind.inbox,
    id,
    version,
    () async => inbox.setArchived(await inbox.get(id), archived),
  );
  Future<Map<String, dynamic>> assignInbox(
    String id,
    String version,
    String? topicId,
  ) => _change(
    EntityKind.inbox,
    id,
    version,
    () async => inbox.assignToTopic(await inbox.get(id), topicId),
  );
  Future<Map<String, dynamic>> moveInbox(
    String id,
    String version,
    InboxColumn column,
    String? beforeId,
  ) => _change(
    EntityKind.inbox,
    id,
    version,
    () async => inbox.moveBefore(
      await inbox.get(id),
      column,
      beforeId,
      await inbox.list(),
    ),
  );
  Future<Map<String, dynamic>> updateCalendar(
    String id,
    String version,
    CalendarPatch p,
  ) => _change(EntityKind.calendar, id, version, () async {
    final old = await calendar.get(id);
    await calendar.save(
      id: id,
      title: p.title ?? old.title,
      scheduledDate: p.date ?? old.scheduledDate,
      isCompleted: old.isCompleted,
      note: p.note.or(old.note),
      remindAt: p.remindAt.or(old.remindAt),
    );
  });
  Future<Map<String, dynamic>> completeCalendar(
    String id,
    String version,
    bool completed,
  ) => _change(
    EntityKind.calendar,
    id,
    version,
    () async => calendar.setCompleted(await calendar.get(id), completed),
  );
  Future<Map<String, dynamic>> updateMemo(
    String id,
    String version,
    MemoPatch p,
  ) => _change(EntityKind.memos, id, version, () async {
    if (p.content != null && p.appendContent != null) {
      throw const DiurnaException(
        'VALIDATION',
        'content and appendContent are mutually exclusive',
      );
    }
    final old = await memos.get(id);
    await memos.save(
      id: id,
      title: p.title ?? old.title,
      content: p.appendContent != null
          ? old.content + p.appendContent!
          : p.content ?? old.content,
    );
  });
  Future<Map<String, dynamic>> reorderMemo(
    String id,
    String version,
    String? beforeId,
  ) => _change(EntityKind.memos, id, version, () async {
    final items = await memos.list();
    if (id == beforeId) return;
    final old = items.indexWhere((e) => e.id == id);
    final target = beforeId == null
        ? items.length
        : items.indexWhere((e) => e.id == beforeId);
    if (target < 0) {
      throw const DiurnaException('NOT_FOUND', 'Reorder target not found');
    }
    await memos.reorder(items, old, target > old ? target - 1 : target);
  });
  Future<Map<String, dynamic>> updateDiary(
    String id,
    String version,
    DiaryPatch p,
  ) => _change(EntityKind.diary, id, version, () async {
    final old = await diary.get(id);
    await diary.save(
      id: id,
      title: p.title ?? old.title,
      content: p.content ?? old.content,
      entryDate: p.date ?? old.entryDate,
      mood: p.mood.or(old.mood),
      tags: p.tags ?? old.tags,
    );
  });
  Future<void> delete(EntityKind kind, String id, String version) =>
      database.transaction(() async {
        await database.checkVersion(userId, kind.table, id, version);
        switch (kind) {
          case EntityKind.inbox:
            await inbox.delete(id);
          case EntityKind.calendar:
            await calendar.delete(id);
          case EntityKind.diary:
            await diary.delete(id);
          case EntityKind.memos:
            await memos.delete(id);
        }
      });
}
