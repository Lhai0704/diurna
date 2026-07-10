import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class LocalTasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get priority => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get itemType => text().nullable()();
  TextColumn get inboxColumn => text().withDefault(const Constant('pending'))();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();
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

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class TaskMutation {
  const TaskMutation(this.id, this.values);

  final String id;
  final Map<String, dynamic> values;
}

@DriftDatabase(
  tables: [
    LocalTasks,
    LocalDiaryEntries,
    LocalCalendarEvents,
    PendingSyncOperations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'diurna'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await customStatement(
          "DELETE FROM pending_sync_operations WHERE entity_type = 'calendar_events'",
        );
        await migrator.deleteTable('local_calendar_events');
        await migrator.createTable(localCalendarEvents);
      }
    },
  );

  Stream<List<LocalTask>> watchTasks(String userId) {
    final query = select(localTasks)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm.desc(table.createdAt),
      ]);
    return query.watch();
  }

  Future<List<LocalTask>> listTasks(String userId) {
    final query = select(localTasks)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm.desc(table.createdAt),
      ]);
    return query.get();
  }

  Stream<List<LocalDiaryEntry>> watchDiaryEntries(String userId) {
    final query = select(localDiaryEntries)
      ..where((table) => table.userId.equals(userId))
      ..orderBy([
        (table) => OrderingTerm.desc(table.entryDate),
        (table) => OrderingTerm.desc(table.createdAt),
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

  Future<void> saveTask(Map<String, dynamic> payload) async {
    await transaction(() async {
      final existing = await _findTask(payload['id'] as String);
      final normalized = <String, dynamic>{
        ...payload,
        if (existing != null)
          'created_at': existing.createdAt.toUtc().toIso8601String(),
      };
      await into(localTasks).insertOnConflictUpdate(_taskCompanion(normalized));
      await _enqueueUpsert('tasks', normalized);
    });
  }

  Future<void> updateTasks(String userId, List<TaskMutation> mutations) async {
    if (mutations.isEmpty) {
      return;
    }
    await transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final mutation in mutations) {
        final existing = await _findTask(mutation.id);
        if (existing == null || existing.userId != userId) {
          continue;
        }
        final payload = <String, dynamic>{
          ...localTaskToRemoteMap(existing),
          ...mutation.values,
          'updated_at': now,
        };
        await into(localTasks).insertOnConflictUpdate(_taskCompanion(payload));
        await _enqueueUpsert('tasks', payload);
      }
    });
  }

  Future<void> deleteTask(String userId, String id) async {
    await transaction(() async {
      final children =
          await (select(localTasks)..where(
                (table) =>
                    table.userId.equals(userId) & table.parentId.equals(id),
              ))
              .get();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final child in children) {
        final payload = <String, dynamic>{
          ...localTaskToRemoteMap(child),
          'parent_id': null,
          'updated_at': now,
        };
        await into(localTasks).insertOnConflictUpdate(_taskCompanion(payload));
        await _enqueueUpsert('tasks', payload);
      }
      await (delete(localTasks)..where(
            (table) => table.id.equals(id) & table.userId.equals(userId),
          ))
          .go();
      await _enqueueDelete(userId, 'tasks', id);
    });
  }

  Future<void> saveDiaryEntry(Map<String, dynamic> payload) async {
    await transaction(() async {
      final id = payload['id'] as String;
      final existing = await _findDiaryEntry(id);
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
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> diaryEntries,
    required List<Map<String, dynamic>> calendarEvents,
  }) async {
    await transaction(() async {
      await _replaceRemoteTasks(userId, tasks);
      await _replaceRemoteDiaryEntries(userId, diaryEntries);
      await _replaceRemoteCalendarEvents(userId, calendarEvents);
    });
  }

  Future<void> _replaceRemoteTasks(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final pendingIds = await _pendingEntityIds(userId, 'tasks');
    final remoteIds = rows.map((row) => row['id'] as String).toSet();
    for (final row in rows) {
      if (!pendingIds.contains(row['id'])) {
        await into(localTasks).insertOnConflictUpdate(_taskCompanion(row));
      }
    }
    final localRows = await (select(
      localTasks,
    )..where((table) => table.userId.equals(userId))).get();
    for (final row in localRows) {
      if (!remoteIds.contains(row.id) && !pendingIds.contains(row.id)) {
        await (delete(
          localTasks,
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

  Future<LocalTask?> _findTask(String id) {
    return (select(
      localTasks,
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

  Future<void> _enqueueUpsert(String entityType, Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    final entityId = payload['id'] as String;
    return into(pendingSyncOperations).insertOnConflictUpdate(
      PendingSyncOperationsCompanion.insert(
        key: '$userId:$entityType:$entityId',
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: 'upsert',
        payloadJson: Value(jsonEncode(payload)),
        createdAt: DateTime.now().toUtc(),
        attemptCount: const Value(0),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> _enqueueDelete(
    String userId,
    String entityType,
    String entityId,
  ) {
    return into(pendingSyncOperations).insertOnConflictUpdate(
      PendingSyncOperationsCompanion.insert(
        key: '$userId:$entityType:$entityId',
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: 'delete',
        payloadJson: const Value(null),
        createdAt: DateTime.now().toUtc(),
        attemptCount: const Value(0),
        lastError: const Value(null),
      ),
    );
  }
}

Map<String, dynamic> localTaskToRemoteMap(LocalTask row) {
  return {
    'id': row.id,
    'user_id': row.userId,
    'title': row.title,
    'note': row.note,
    'due_date': row.dueDate?.toIso8601String().split('T').first,
    'priority': row.priority,
    'is_completed': row.isCompleted,
    'item_type': row.itemType,
    'inbox_column': row.inboxColumn,
    'sort_order': row.sortOrder,
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

LocalTasksCompanion _taskCompanion(Map<String, dynamic> map) {
  return LocalTasksCompanion.insert(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    title: map['title'] as String,
    note: Value(map['note'] as String?),
    dueDate: Value(_parseDateTime(map['due_date'])),
    priority: Value(map['priority'] as int?),
    isCompleted: Value(map['is_completed'] as bool? ?? false),
    itemType: Value(map['item_type'] as String?),
    inboxColumn: Value(map['inbox_column'] as String? ?? 'pending'),
    sortOrder: Value((map['sort_order'] as num?)?.toDouble() ?? 0),
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
