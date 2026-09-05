import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../contracts/errors.dart';

import 'package:drift/drift.dart';

part 'app_database.g.dart';

class LocalInboxItems extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get content => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get priority => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get itemType => text().nullable()();
  TextColumn get inboxColumn => text().withDefault(const Constant('pending'))();
  RealColumn get position => real().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isTopic => boolean().withDefault(const Constant(false))();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalDiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get mood => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalCalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  DateTimeColumn get scheduledDate => dateTime()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalMemos extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  RealColumn get position => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PendingSyncOperations extends Table {
  TextColumn get key => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get generation => text().withDefault(const Constant('legacy'))();
  TextColumn get groupId => text().withDefault(const Constant('legacy'))();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class InboxItemMutation {
  const InboxItemMutation(this.id, this.values);

  final String id;
  final Map<String, dynamic> values;
}

class MemoMutation {
  const MemoMutation(this.id, this.values);

  final String id;
  final Map<String, dynamic> values;
}

@DriftDatabase(
  tables: [
    LocalInboxItems,
    LocalDiaryEntries,
    LocalCalendarEvents,
    LocalMemos,
    PendingSyncOperations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createSyncMetadata();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 5) {
        await migrator.addColumn(
          pendingSyncOperations,
          pendingSyncOperations.generation,
        );
        await migrator.addColumn(
          pendingSyncOperations,
          pendingSyncOperations.groupId,
        );
        await _createSyncMetadata();
      }
      if (from < 3) {
        // Retain the exact historical rows and queue before transforming them.
        await customStatement(
          'CREATE TABLE legacy_pending_sync_operations AS SELECT * FROM pending_sync_operations',
        );
      }
      if (from < 2) {
        final columns = await customSelect(
          'PRAGMA table_info(local_calendar_events)',
        ).get();
        if (columns.any((c) => c.read<String>('name') == 'starts_at')) {
          await customStatement(
            'ALTER TABLE local_calendar_events RENAME TO legacy_calendar_events',
          );
          await migrator.createTable(localCalendarEvents);
          for (final record in await customSelect(
            'SELECT * FROM legacy_calendar_events',
          ).get()) {
            final r = record.data;
            final start = DateTime.fromMillisecondsSinceEpoch(
              (r['starts_at'] as int) * 1000,
            );
            final payload = <String, dynamic>{
              'id': r['id'],
              'user_id': r['user_id'],
              'title': r['title'],
              'event_date': _formatDateOnly(start),
              'is_completed': false,
              'note': [
                r['note'],
                if (r['location'] != null) 'Location: ${r['location']}',
                'Legacy end: ${r['ends_at']}',
              ].whereType<String>().join('\n'),
              'remind_at': r['remind_at'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      (r['remind_at'] as int) * 1000,
                    ).toUtc().toIso8601String(),
              'created_at': DateTime.fromMillisecondsSinceEpoch(
                (r['created_at'] as int) * 1000,
              ).toUtc().toIso8601String(),
              'updated_at': DateTime.fromMillisecondsSinceEpoch(
                (r['updated_at'] as int) * 1000,
              ).toUtc().toIso8601String(),
            };
            await into(localCalendarEvents).insert(_calendarCompanion(payload));
            await _enqueueUpsert('calendar_events', payload);
          }
          // Unsupported original payloads remain in the legacy queue backup.
          final rows = await listLegacyUsers('local_calendar_events');
          for (final user in rows) {
            for (final row in await listCalendarEvents(user)) {
              final payload = localCalendarEventToRemoteMap(row);
              await (update(pendingSyncOperations)..where(
                    (t) =>
                        t.userId.equals(user) &
                        t.entityType.equals('calendar_events') &
                        t.entityId.equals(row.id),
                  ))
                  .write(
                    PendingSyncOperationsCompanion(
                      payloadJson: Value(jsonEncode(payload)),
                      generation: const Value('legacy'),
                    ),
                  );
            }
          }
        }
      }
      if (from < 3) {
        await migrator.createTable(localInboxItems);
        for (final record in await customSelect(
          'SELECT * FROM local_tasks',
        ).get()) {
          final r = record.data;
          final topic = r['is_topic'] == 1;
          final action = r['item_type'] == 'action' && !topic;
          final payload = <String, dynamic>{
            'id': r['id'],
            'user_id': r['user_id'],
            'content': [
              r['title'],
              r['note'],
            ].whereType<String>().where((v) => v.isNotEmpty).join('\n'),
            'due_date': action && r['due_date'] != null
                ? _formatDateOnly(
                    DateTime.fromMillisecondsSinceEpoch(
                      (r['due_date'] as int) * 1000,
                    ),
                  )
                : null,
            'priority': action ? r['priority'] ?? 2 : null,
            'is_completed': action && r['is_completed'] == 1,
            'item_type': topic ? 'research' : r['item_type'],
            'inbox_column': r['inbox_column'],
            'position': r['sort_order'],
            'is_archived': r['is_archived'] == 1,
            'is_pinned': r['is_pinned'] == 1,
            'is_topic': topic,
            'parent_id': r['parent_id'],
            'created_at': DateTime.fromMillisecondsSinceEpoch(
              (r['created_at'] as int) * 1000,
            ).toUtc().toIso8601String(),
            'updated_at': DateTime.fromMillisecondsSinceEpoch(
              (r['updated_at'] as int) * 1000,
            ).toUtc().toIso8601String(),
          };
          await into(localInboxItems).insert(_inboxItemCompanion(payload));
          await _enqueueUpsert('inbox_items', payload);
        }
        // Keep the original table. Retired tasks operations are retained in the backup,
        // and represented as conflicts rather than sent to a removed remote table.
        final retired = await (select(
          pendingSyncOperations,
        )..where((t) => t.entityType.equals('tasks'))).get();
        for (final op in retired) {
          await customStatement('INSERT INTO sync_conflicts VALUES (?,?,?,?,?)', [
            const Uuid().v4(),
            op.userId,
            'tasks',
            jsonEncode([
              {
                'id': op.entityId,
                'operation': op.operation,
                'payload': op.payloadJson == null
                    ? null
                    : jsonDecode(op.payloadJson!),
                'generation': op.generation,
              },
            ]),
            jsonEncode({
              'legacy': true,
              'message':
                  'Original tasks operation retained; migrated records are in Inbox.',
            }),
          ]);
          await removePendingOperation(op.key);
        }
      }
      if (from < 4) await migrator.createTable(localMemos);
    },
  );

  Future<List<String>> listLegacyUsers(String table) async {
    if (table != 'local_calendar_events') {
      throw ArgumentError('Unsupported legacy table');
    }
    return (await customSelect(
      'SELECT DISTINCT user_id FROM local_calendar_events',
    ).get()).map((r) => r.read<String>('user_id')).toList();
  }

  Future<void> _createSyncMetadata() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sync_metadata (user_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, revision INTEGER NOT NULL, remote_json TEXT, PRIMARY KEY(user_id,entity_type,entity_id))',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sync_attempts (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, entity_type TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sync_conflicts (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, entity_type TEXT NOT NULL, payload TEXT NOT NULL, remote_json TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS machine_requests (user_id TEXT NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL, entity_id TEXT NOT NULL, PRIMARY KEY(user_id,request_id))',
    );
  }

  Future<List<LocalDiaryEntry>> listDiaryEntries(String userId) =>
      (select(localDiaryEntries)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.entryDate),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();
  Future<List<LocalCalendarEvent>> listCalendarEvents(String userId) =>
      (select(localCalendarEvents)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.scheduledDate),
              (t) => OrderingTerm(expression: t.isCompleted),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();

  Future<Map<String, dynamic>> entity(
    String userId,
    String type,
    String id,
  ) async {
    Map<String, dynamic>? result;
    switch (type) {
      case 'inbox_items':
        final row = await _findInboxItem(id);
        if (row != null && row.userId == userId) {
          result = localInboxItemToRemoteMap(row);
        }
      case 'calendar_events':
        final row = await _findCalendarEvent(id);
        if (row != null && row.userId == userId) {
          result = localCalendarEventToRemoteMap(row);
        }
      case 'diary_entries':
        final row = await _findDiaryEntry(id);
        if (row != null && row.userId == userId) {
          result = localDiaryEntryToRemoteMap(row);
        }
      case 'memos':
        final row = await _findMemo(id);
        if (row != null && row.userId == userId) {
          result = localMemoToRemoteMap(row);
        }
    }
    if (result == null) {
      throw const DiurnaException('NOT_FOUND', 'Entity not found');
    }
    return result;
  }

  Future<String> version(String userId, String type, String id) async {
    final row = await entity(userId, type, id);
    // Content-derived tokens also protect editors across a snapshot replacement.
    return entityVersion(row);
  }

  Future<void> checkVersion(
    String userId,
    String type,
    String id,
    String? expected,
  ) async {
    final actual = await version(userId, type, id);
    if (expected != null && actual != expected) {
      throw const DiurnaException(
        'CONFLICT',
        'Entity changed since it was read',
      );
    }
  }

  Stream<List<LocalInboxItem>> watchInboxItems(String userId) {
    final query = select(localInboxItems)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.position),
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.watch();
  }

  Future<List<LocalInboxItem>> listInboxItems(String userId) {
    final query = select(localInboxItems)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.position),
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Stream<List<LocalDiaryEntry>> watchDiaryEntries(String userId) {
    final query = select(localDiaryEntries)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm.desc(table.entryDate),
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.watch();
  }

  Stream<List<LocalCalendarEvent>> watchCalendarEvents(
    String userId, {
    bool todayOnly = false,
  }) {
    final query = select(localCalendarEvents)
      ..where((table) => table.userId.equals(userId));
    if (todayOnly) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      query.where(
        (table) =>
            table.scheduledDate.isBiggerOrEqualValue(start) &
            table.scheduledDate.isSmallerThanValue(end),
      );
    }
    query.orderBy([
      (table) => OrderingTerm(expression: table.scheduledDate),
      (table) => OrderingTerm(expression: table.isCompleted),
      (table) => OrderingTerm(expression: table.createdAt),
    ]);
    return query.watch();
  }

  Stream<List<LocalMemo>> watchMemos(String userId) {
    final query = select(localMemos)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.position),
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.watch();
  }

  Future<List<LocalMemo>> listMemos(String userId) {
    final query = select(localMemos)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.position),
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<void> saveInboxItem(Map<String, dynamic> payload) async {
    await transaction(() async {
      final existing = await _findInboxItem(payload['id'] as String);
      if (existing != null && existing.userId != payload['user_id']) {
        throw const DiurnaException('NOT_FOUND', 'Entity not found');
      }
      final normalized = <String, dynamic>{
        ...payload,
        if (existing != null)
          'created_at': existing.createdAt.toUtc().toIso8601String(),
      };
      await into(
        localInboxItems,
      ).insertOnConflictUpdate(_inboxItemCompanion(normalized));
      await _enqueueUpsert('inbox_items', normalized);
    });
  }

  Future<void> updateInboxItems(
    String userId,
    List<InboxItemMutation> mutations,
  ) async {
    if (mutations.isEmpty) {
      return;
    }
    await transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      final group = const Uuid().v4();
      for (final mutation in mutations) {
        final existing = await _findInboxItem(mutation.id);
        if (existing == null || existing.userId != userId) {
          throw const DiurnaException('NOT_FOUND', 'Entity not found');
        }
        final payload = <String, dynamic>{
          ...localInboxItemToRemoteMap(existing),
          ...mutation.values,
          'updated_at': now,
        };
        await into(
          localInboxItems,
        ).insertOnConflictUpdate(_inboxItemCompanion(payload));
        await _enqueueUpsert('inbox_items', payload, group: group);
      }
    });
  }

  Future<void> deleteInboxItem(String userId, String id) async {
    await transaction(() async {
      final group = const Uuid().v4();
      final children =
          await (select(localInboxItems)..where(
                (table) =>
                    table.userId.equals(userId) & table.parentId.equals(id),
              ))
              .get();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final child in children) {
        final payload = <String, dynamic>{
          ...localInboxItemToRemoteMap(child),
          'parent_id': null,
          'updated_at': now,
        };
        await into(
          localInboxItems,
        ).insertOnConflictUpdate(_inboxItemCompanion(payload));
        await _enqueueUpsert('inbox_items', payload, group: group);
      }
      await (delete(localInboxItems)..where(
            (table) => table.id.equals(id) & table.userId.equals(userId),
          ))
          .go();
      await _enqueueDelete(userId, 'inbox_items', id, group: group);
    });
  }

  Future<void> saveDiaryEntry(Map<String, dynamic> payload) async {
    await transaction(() async {
      final id = payload['id'] as String;
      final existing = await _findDiaryEntry(id);
      if (existing != null && existing.userId != payload['user_id']) {
        throw const DiurnaException('NOT_FOUND', 'Entity not found');
      }
      final normalized = <String, dynamic>{
        ...payload,
        if (existing != null)
          'created_at': existing.createdAt.toUtc().toIso8601String(),
      };
      await into(
        localDiaryEntries,
      ).insertOnConflictUpdate(_diaryCompanion(normalized));
      await _enqueueUpsert('diary_entries', normalized);
    });
  }

  Future<void> deleteDiaryEntry(String userId, String id) async {
    await transaction(() async {
      await (delete(localDiaryEntries)..where(
            (table) => table.id.equals(id) & table.userId.equals(userId),
          ))
          .go();
      await _enqueueDelete(userId, 'diary_entries', id);
    });
  }

  Future<void> saveCalendarEvent(Map<String, dynamic> payload) async {
    await transaction(() async {
      final id = payload['id'] as String;
      final existing = await _findCalendarEvent(id);
      if (existing != null && existing.userId != payload['user_id']) {
        throw const DiurnaException('NOT_FOUND', 'Entity not found');
      }
      final normalized = <String, dynamic>{
        ...payload,
        if (existing != null)
          'created_at': existing.createdAt.toUtc().toIso8601String(),
      };
      await into(
        localCalendarEvents,
      ).insertOnConflictUpdate(_calendarCompanion(normalized));
      await _enqueueUpsert('calendar_events', normalized);
    });
  }

  Future<void> deleteCalendarEvent(String userId, String id) async {
    await transaction(() async {
      await (delete(localCalendarEvents)..where(
            (table) => table.id.equals(id) & table.userId.equals(userId),
          ))
          .go();
      await _enqueueDelete(userId, 'calendar_events', id);
    });
  }

  Future<void> saveMemo(Map<String, dynamic> payload) async {
    await transaction(() async {
      final id = payload['id'] as String;
      final existing = await _findMemo(id);
      if (existing != null && existing.userId != payload['user_id']) {
        throw const DiurnaException('NOT_FOUND', 'Entity not found');
      }
      final normalized = <String, dynamic>{
        ...payload,
        if (existing != null)
          'created_at': existing.createdAt.toUtc().toIso8601String(),
      };
      await into(localMemos).insertOnConflictUpdate(_memoCompanion(normalized));
      await _enqueueUpsert('memos', normalized);
    });
  }

  Future<void> updateMemos(String userId, List<MemoMutation> mutations) async {
    if (mutations.isEmpty) {
      return;
    }
    await transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      final group = const Uuid().v4();
      for (final mutation in mutations) {
        final existing = await _findMemo(mutation.id);
        if (existing == null || existing.userId != userId) {
          throw const DiurnaException('NOT_FOUND', 'Entity not found');
        }
        final payload = <String, dynamic>{
          ...localMemoToRemoteMap(existing),
          ...mutation.values,
          'updated_at': now,
        };
        await into(localMemos).insertOnConflictUpdate(_memoCompanion(payload));
        await _enqueueUpsert('memos', payload, group: group);
      }
    });
  }

  Future<void> deleteMemo(String userId, String id) async {
    await transaction(() async {
      await (delete(localMemos)..where(
            (table) => table.id.equals(id) & table.userId.equals(userId),
          ))
          .go();
      await _enqueueDelete(userId, 'memos', id);
    });
  }

  Stream<int> watchPendingCount(String userId) {
    final query = select(pendingSyncOperations)
      ..where((table) => table.userId.equals(userId));
    return query.watch().map((rows) => rows.length);
  }

  Future<int> pendingCount(String userId) async {
    final query = select(pendingSyncOperations)
      ..where((table) => table.userId.equals(userId));
    return (await query.get()).length;
  }

  Future<List<PendingSyncOperation>> pendingOperations(String userId) {
    final query = select(pendingSyncOperations)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]);
    return query.get();
  }

  Future<void> removePendingOperation(String key) {
    return (delete(
      pendingSyncOperations,
    )..where((table) => table.key.equals(key))).go();
  }

  Future<void> incrementPendingAttempt(
    PendingSyncOperation operation,
    Object error,
  ) {
    return (update(
      pendingSyncOperations,
    )..where((table) => table.key.equals(operation.key))).write(
      PendingSyncOperationsCompanion(
        attemptCount: Value(operation.attemptCount + 1),
        lastError: Value(error.toString()),
      ),
    );
  }

  Future<void> applyRemoteSnapshot(
    String userId, {
    required List<Map<String, dynamic>> inboxItems,
    required List<Map<String, dynamic>> diaryEntries,
    required List<Map<String, dynamic>> calendarEvents,
    required List<Map<String, dynamic>> memos,
  }) async {
    await transaction(() async {
      await _replaceRemoteInboxItems(userId, inboxItems);
      await _replaceRemoteDiaryEntries(userId, diaryEntries);
      await _replaceRemoteCalendarEvents(userId, calendarEvents);
      await _replaceRemoteMemos(userId, memos);
    });
  }

  Future<void> _replaceRemoteInboxItems(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final pendingIds = await _pendingEntityIds(userId, 'inbox_items');
    final remoteIds = rows.map((row) => row['id'] as String).toSet();
    for (final row in rows) {
      if (!pendingIds.contains(row['id'])) {
        await into(
          localInboxItems,
        ).insertOnConflictUpdate(_inboxItemCompanion(row));
      }
    }
    final localRows = await (select(
      localInboxItems,
    )..where((table) => table.userId.equals(userId))).get();
    for (final row in localRows) {
      if (!remoteIds.contains(row.id) && !pendingIds.contains(row.id)) {
        await (delete(
          localInboxItems,
        )..where((table) => table.id.equals(row.id))).go();
      }
    }
  }

  Future<void> _replaceRemoteDiaryEntries(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final pendingIds = await _pendingEntityIds(userId, 'diary_entries');
    final remoteIds = rows.map((row) => row['id'] as String).toSet();
    for (final row in rows) {
      if (!pendingIds.contains(row['id'])) {
        await into(
          localDiaryEntries,
        ).insertOnConflictUpdate(_diaryCompanion(row));
      }
    }
    final localRows = await (select(
      localDiaryEntries,
    )..where((table) => table.userId.equals(userId))).get();
    for (final row in localRows) {
      if (!remoteIds.contains(row.id) && !pendingIds.contains(row.id)) {
        await (delete(
          localDiaryEntries,
        )..where((table) => table.id.equals(row.id))).go();
      }
    }
  }

  Future<void> _replaceRemoteCalendarEvents(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final pendingIds = await _pendingEntityIds(userId, 'calendar_events');
    final remoteIds = rows.map((row) => row['id'] as String).toSet();
    for (final row in rows) {
      if (!pendingIds.contains(row['id'])) {
        await into(
          localCalendarEvents,
        ).insertOnConflictUpdate(_calendarCompanion(row));
      }
    }
    final localRows = await (select(
      localCalendarEvents,
    )..where((table) => table.userId.equals(userId))).get();
    for (final row in localRows) {
      if (!remoteIds.contains(row.id) && !pendingIds.contains(row.id)) {
        await (delete(
          localCalendarEvents,
        )..where((table) => table.id.equals(row.id))).go();
      }
    }
  }

  Future<void> _replaceRemoteMemos(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final pendingIds = await _pendingEntityIds(userId, 'memos');
    final remoteIds = rows.map((row) => row['id'] as String).toSet();
    for (final row in rows) {
      if (!pendingIds.contains(row['id'])) {
        await into(localMemos).insertOnConflictUpdate(_memoCompanion(row));
      }
    }
    final localRows = await (select(
      localMemos,
    )..where((table) => table.userId.equals(userId))).get();
    for (final row in localRows) {
      if (!remoteIds.contains(row.id) && !pendingIds.contains(row.id)) {
        await (delete(
          localMemos,
        )..where((table) => table.id.equals(row.id))).go();
      }
    }
  }

  Future<Set<String>> _pendingEntityIds(
    String userId,
    String entityType,
  ) async {
    final query = select(pendingSyncOperations)
      ..where(
        (table) =>
            table.userId.equals(userId) & table.entityType.equals(entityType),
      );
    return (await query.get()).map((row) => row.entityId).toSet();
  }

  Future<LocalInboxItem?> _findInboxItem(String id) {
    return (select(
      localInboxItems,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<LocalDiaryEntry?> _findDiaryEntry(String id) {
    return (select(
      localDiaryEntries,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<LocalCalendarEvent?> _findCalendarEvent(String id) {
    return (select(
      localCalendarEvents,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<LocalMemo?> _findMemo(String id) {
    return (select(
      localMemos,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<void> _mergeGroup(
    String userId,
    String type,
    String id,
    String group,
  ) async {
    final old = await (select(
      pendingSyncOperations,
    )..where((t) => t.key.equals('$userId:$type:$id'))).getSingleOrNull();
    if (old != null) {
      await (update(pendingSyncOperations)..where(
            (t) =>
                t.userId.equals(userId) &
                t.entityType.equals(type) &
                t.groupId.equals(old.groupId),
          ))
          .write(PendingSyncOperationsCompanion(groupId: Value(group)));
    }
  }

  Future<void> _enqueueUpsert(
    String entityType,
    Map<String, dynamic> payload, {
    String? group,
  }) async {
    final userId = payload['user_id'] as String;
    final entityId = payload['id'] as String;
    final groupId = group ?? const Uuid().v4();
    await _mergeGroup(userId, entityType, entityId, groupId);
    await into(pendingSyncOperations).insertOnConflictUpdate(
      PendingSyncOperationsCompanion.insert(
        key: '$userId:$entityType:$entityId',
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: 'upsert',
        payloadJson: Value(jsonEncode(payload)),
        generation: Value(const Uuid().v4()),
        groupId: Value(groupId),
        createdAt: DateTime.now().toUtc(),
        attemptCount: const Value(0),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> _enqueueDelete(
    String userId,
    String entityType,
    String entityId, {
    String? group,
  }) async {
    final groupId = group ?? const Uuid().v4();
    await _mergeGroup(userId, entityType, entityId, groupId);
    await into(pendingSyncOperations).insertOnConflictUpdate(
      PendingSyncOperationsCompanion.insert(
        key: '$userId:$entityType:$entityId',
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: 'delete',
        payloadJson: const Value(null),
        generation: Value(const Uuid().v4()),
        groupId: Value(groupId),
        createdAt: DateTime.now().toUtc(),
        attemptCount: const Value(0),
        lastError: const Value(null),
      ),
    );
  }
}

Map<String, dynamic> localInboxItemToRemoteMap(LocalInboxItem row) {
  return {
    'id': row.id,
    'user_id': row.userId,
    'content': row.content,
    'due_date': row.dueDate?.toIso8601String().split('T').first,
    'priority': row.priority,
    'is_completed': row.isCompleted,
    'item_type': row.itemType,
    'inbox_column': row.inboxColumn,
    'position': row.position,
    'is_archived': row.isArchived,
    'is_pinned': row.isPinned,
    'is_topic': row.isTopic,
    'parent_id': row.parentId,
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> localDiaryEntryToRemoteMap(LocalDiaryEntry row) {
  return {
    'id': row.id,
    'user_id': row.userId,
    'entry_date': row.entryDate.toIso8601String().split('T').first,
    'title': row.title,
    'content': row.content,
    'mood': row.mood,
    'tags': (jsonDecode(row.tagsJson) as List).cast<String>(),
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> localCalendarEventToRemoteMap(LocalCalendarEvent row) {
  return {
    'id': row.id,
    'user_id': row.userId,
    'title': row.title,
    'event_date': _formatDateOnly(row.scheduledDate),
    'is_completed': row.isCompleted,
    'note': row.note,
    'remind_at': row.remindAt?.toUtc().toIso8601String(),
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> localMemoToRemoteMap(LocalMemo row) {
  return {
    'id': row.id,
    'user_id': row.userId,
    'title': row.title,
    'content': row.content,
    'position': row.position,
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}

LocalInboxItemsCompanion _inboxItemCompanion(Map<String, dynamic> map) {
  return LocalInboxItemsCompanion.insert(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    content: map['content'] as String,
    dueDate: Value(_parseDateTime(map['due_date'])),
    priority: Value(map['priority'] as int?),
    isCompleted: Value(map['is_completed'] as bool? ?? false),
    itemType: Value(map['item_type'] as String?),
    inboxColumn: Value(map['inbox_column'] as String? ?? 'pending'),
    position: Value((map['position'] as num?)?.toDouble() ?? 0),
    isArchived: Value(map['is_archived'] as bool? ?? false),
    isPinned: Value(map['is_pinned'] as bool? ?? false),
    isTopic: Value(map['is_topic'] as bool? ?? false),
    parentId: Value(map['parent_id'] as String?),
    createdAt: _parseDateTime(map['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now().toUtc(),
  );
}

LocalDiaryEntriesCompanion _diaryCompanion(Map<String, dynamic> map) {
  return LocalDiaryEntriesCompanion.insert(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    entryDate: _parseDateTime(map['entry_date'])!,
    title: map['title'] as String,
    content: map['content'] as String,
    mood: Value(map['mood'] as String?),
    tagsJson: Value(jsonEncode(map['tags'] as List? ?? const <String>[])),
    createdAt: _parseDateTime(map['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now().toUtc(),
  );
}

LocalCalendarEventsCompanion _calendarCompanion(Map<String, dynamic> map) {
  return LocalCalendarEventsCompanion.insert(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    title: map['title'] as String,
    scheduledDate: _parseDateTime(map['event_date'])!,
    isCompleted: Value(map['is_completed'] as bool? ?? false),
    note: Value(map['note'] as String?),
    remindAt: Value(_parseDateTime(map['remind_at'])),
    createdAt: _parseDateTime(map['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now().toUtc(),
  );
}

LocalMemosCompanion _memoCompanion(Map<String, dynamic> map) {
  return LocalMemosCompanion.insert(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    title: map['title'] as String,
    content: Value(map['content'] as String? ?? ''),
    position: Value((map['position'] as num?)?.toDouble() ?? 0),
    createdAt: _parseDateTime(map['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now().toUtc(),
  );
}

String _formatDateOnly(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.parse(value as String);
}
