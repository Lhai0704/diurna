import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/core/sync/sync_remote_data_source.dart';
import 'package:diurna/core/sync/sync_service.dart';
import 'package:diurna/features/inbox/data/inbox_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _FakeRemoteDataSource remote;
  late InboxRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemoteDataSource();
    repository = InboxRepository(database, 'user-1');
  });

  tearDown(() async {
    await database.close();
  });

  test('pushes queued writes and clears the queue', () async {
    await repository.createQuick('后台上传');
    final service = SyncService(
      database: database,
      remote: remote,
      userId: 'user-1',
    );

    await service.syncNow();

    expect(remote.inboxItems.values.single['content'], '后台上传');
    expect(await database.pendingCount('user-1'), 0);
    expect(service.snapshot.phase, SyncPhase.idle);
    await service.dispose();
  });

  test('keeps failed writes and succeeds on manual retry', () async {
    await repository.createQuick('断网后重试');
    remote.failRequests = true;
    final service = SyncService(
      database: database,
      remote: remote,
      userId: 'user-1',
    );

    await service.syncNow();
    expect(service.snapshot.phase, SyncPhase.failed);
    expect(await database.pendingCount('user-1'), 1);

    remote.failRequests = false;
    await service.syncNow();
    expect(service.snapshot.phase, SyncPhase.idle);
    expect(await database.pendingCount('user-1'), 0);
    expect(remote.inboxItems.values.single['content'], '断网后重试');
    await service.dispose();
  });

  test('pulls an existing remote snapshot into the local database', () async {
    final now = DateTime.utc(2026, 7, 11).toIso8601String();
    remote.inboxItems['remote-1'] = {
      'id': 'remote-1',
      'user_id': 'user-1',
      'content': '来自其他设备',
      'due_date': null,
      'priority': null,
      'is_completed': false,
      'item_type': null,
      'inbox_column': 'pending',
      'position': 0.0,
      'is_archived': false,
      'is_pinned': false,
      'is_topic': false,
      'parent_id': null,
      'created_at': now,
      'updated_at': now,
    };
    final service = SyncService(
      database: database,
      remote: remote,
      userId: 'user-1',
    );

    await service.syncNow();

    final items = await repository.list();
    expect(items.single.content, '来自其他设备');
    expect(await database.pendingCount('user-1'), 0);
    await service.dispose();
  });
}

class _FakeRemoteDataSource implements SyncRemoteDataSource {
  final Map<String, Map<String, dynamic>> inboxItems = {};
  final Map<String, Map<String, dynamic>> diaryEntries = {};
  final Map<String, Map<String, dynamic>> calendarEvents = {};
  bool failRequests = false;

  @override
  Future<void> upsert(String table, Map<String, dynamic> payload) async {
    _throwIfFailed();
    _table(table)[payload['id'] as String] = Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> delete(String table, String id) async {
    _throwIfFailed();
    _table(table).remove(id);
  }

  @override
  Future<RemoteSnapshot> fetchSnapshot() async {
    _throwIfFailed();
    return RemoteSnapshot(
      inboxItems: inboxItems.values.map(Map<String, dynamic>.from).toList(),
      diaryEntries: diaryEntries.values.map(Map<String, dynamic>.from).toList(),
      calendarEvents: calendarEvents.values
          .map(Map<String, dynamic>.from)
          .toList(),
    );
  }

  Map<String, Map<String, dynamic>> _table(String table) {
    return switch (table) {
      'inbox_items' => inboxItems,
      'diary_entries' => diaryEntries,
      'calendar_events' => calendarEvents,
      _ => throw ArgumentError.value(table, 'table'),
    };
  }

  void _throwIfFailed() {
    if (failRequests) {
      throw Exception('network unavailable');
    }
  }
}
