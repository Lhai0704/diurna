import 'dart:async';
import 'dart:convert';
import 'package:diurna_core/diurna_core.dart';
import 'package:diurna_core/src/core/sync/versioned_sync_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

class TestRemote implements VersionedSyncRemoteDataSource {
  final tables = {
    for (final t in [
      'inbox_items',
      'calendar_events',
      'diary_entries',
      'memos',
    ])
      t: <String, Map<String, dynamic>>{},
  };
  final receipts = <String, Map<String, dynamic>>{};
  final events = StreamController<int>.broadcast();
  int generation = 0, fetches = 0, commits = 0;
  bool failCommit = false;
  Completer<void>? commitGate;
  Completer<void>? commitStarted;
  @override
  Future<Map<String, dynamic>> commit(SyncAttempt attempt) async {
    commits++;
    if (failCommit) throw StateError("offline");
    commitStarted?.complete();
    commitStarted = null;
    await commitGate?.future;
    commitGate = null;
    if (receipts.containsKey(attempt.id)) return receipts[attempt.id]!;
    final table = tables[attempt.entityType]!;
    if (attempt.changes.any(
      (c) => (table[c['id']]?['revision'] ?? 0) != c['expected_revision'],
    )) {
      return {'ok': false, 'code': 'CONFLICT', 'remote': table.values.toList()};
    }
    final revisions = <Map<String, dynamic>>[];
    for (final change in attempt.changes) {
      final rev = (table[change['id']]?['revision'] as int? ?? 0) + 1;
      if (change['operation'] == 'delete') {
        table.remove(change['id']);
      } else {
        table[change['id']] = {
          ...change['payload'] as Map<String, dynamic>,
          'revision': rev,
        };
      }
      revisions.add({'id': change['id'], 'revision': rev});
      generation++;
    }
    events.add(generation);
    return receipts[attempt.id] = {'ok': true, 'revisions': revisions};
  }

  @override
  Future<RemoteSnapshot> fetchSnapshot() async {
    fetches++;
    List<Map<String, dynamic>> rows(String t) =>
        (jsonDecode(jsonEncode(tables[t]!.values.toList())) as List)
            .cast<Map<String, dynamic>>();
    return RemoteSnapshot(
      inboxItems: rows('inbox_items'),
      calendarEvents: rows('calendar_events'),
      diaryEntries: rows('diary_entries'),
      memos: rows('memos'),
      generation: generation,
    );
  }

  @override
  Stream<int> changes(String userId) => events.stream;
  @override
  Future<void> close() async {}
  @override
  Future<void> upsert(String table, Map<String, dynamic> payload) =>
      throw UnimplementedError();
  @override
  Future<void> delete(String table, String id) => throw UnimplementedError();
}

void main() {
  test('queue and remote events respect failure backoff', () async {
    final db = AppDatabase(NativeDatabase.memory()), remote = TestRemote();
    final service = DiurnaService(db, 'u');
    final sync = SyncService(database: db, remote: remote, userId: 'u');
    try {
      await service.createMemo(title: 'first');
      remote.failCommit = true;
      sync.start();
      await sync.syncNow();
      expect(sync.snapshot.phase, SyncPhase.failed);
      final attempts = remote.commits;
      await service.createMemo(title: 'second');
      remote.events.add(10);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(remote.commits, attempts);
      expect(await db.pendingCount('u'), 2);
    } finally {
      await sync.dispose();
      await db.close();
      await remote.events.close();
    }
  });

  test(
    'two local clients detect conflict while unrelated writes synchronize',
    () async {
      final a = AppDatabase(NativeDatabase.memory()),
          b = AppDatabase(NativeDatabase.memory());
      final remote = TestRemote();
      final sa = DiurnaService(a, 'u'), sb = DiurnaService(b, 'u');
      final syncA = SyncService(database: a, remote: remote, userId: 'u'),
          syncB = SyncService(database: b, remote: remote, userId: 'u');
      try {
        final initial = await sa.createMemo(title: 'base');
        await syncA.syncNow();
        await syncB.syncNow();
        final av = await sa.get(EntityKind.memos, initial['id']),
            bv = await sb.get(EntityKind.memos, initial['id']);
        await sa.updateMemo(
          av['id'],
          av['version'],
          const MemoPatch(title: 'A'),
        );
        await sb.updateMemo(
          bv['id'],
          bv['version'],
          const MemoPatch(title: 'B'),
        );
        await sb.createMemo(title: 'unrelated');
        await syncA.syncNow();
        await syncB.syncNow();
        expect(syncB.snapshot.conflictCount, 1);
        expect((await sb.memos.get(bv['id'])).title, 'B');
        expect(
          remote.tables['memos']!.values.map((r) => r['title']),
          containsAll(['A', 'unrelated']),
        );
        final conflict = (await syncB.conflicts()).single;
        await syncB.resolveConflict(conflict['id'], useLocal: true);
        expect(syncB.snapshot.conflictCount, 0);
        expect(remote.tables['memos']![bv['id']]!['title'], 'B');
      } finally {
        await syncA.dispose();
        await syncB.dispose();
        await a.close();
        await b.close();
        await remote.events.close();
      }
    },
  );
  test(
    'local edit during upload survives ACK and is sent by follow-up sync',
    () async {
      final db = AppDatabase(NativeDatabase.memory()), remote = TestRemote();
      final s = DiurnaService(db, 'u');
      final sync = SyncService(database: db, remote: remote, userId: 'u');
      final started = remote.commitStarted = Completer<void>();
      final gate = remote.commitGate = Completer<void>();
      try {
        final memo = await s.createMemo(title: 'before');
        final running = sync.syncNow();
        await started.future;
        await s.updateMemo(
          memo['id'],
          memo['version'],
          const MemoPatch(title: 'after'),
        );
        gate.complete();
        await running;
        await sync.syncNow();
        expect(await db.pendingCount('u'), 0);
        expect(remote.tables['memos']![memo['id']]!['title'], 'after');
      } finally {
        await sync.dispose();
        await db.close();
        await remote.events.close();
      }
    },
  );
  test('remote burst is debounced and own events do not loop', () async {
    final db = AppDatabase(NativeDatabase.memory()), remote = TestRemote();
    final s = DiurnaService(db, 'u');
    final sync = SyncService(database: db, remote: remote, userId: 'u');
    try {
      sync.start();
      await sync.syncNow();
      final memo = await s.createMemo(title: 'own');
      await sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final before = remote.fetches;
      remote.tables['memos']![memo['id']]!['title'] = 'remote';
      remote.generation++;
      for (var i = 0; i < 20; i++) {
        remote.events.add(remote.generation);
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect((await s.memos.get(memo['id'])).title, 'remote');
      expect(remote.fetches, before + 1);
      final settled = remote.fetches;
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(remote.fetches, settled);
    } finally {
      await sync.dispose();
      await db.close();
      await remote.events.close();
    }
  });
  test(
    'disposing during upload leaves the frozen attempt for later recovery',
    () async {
      final db = AppDatabase(NativeDatabase.memory()), remote = TestRemote();
      final s = DiurnaService(db, 'u');
      final sync = SyncService(database: db, remote: remote, userId: 'u');
      final started = remote.commitStarted = Completer<void>();
      final gate = remote.commitGate = Completer<void>();
      await s.createMemo(title: 'retained');
      final running = sync.syncNow();
      await started.future;
      final disposing = sync.dispose();
      gate.complete();
      await running;
      await disposing;
      expect(await db.pendingCount('u'), 1);
      expect(await VersionedSyncStore(db, 'u').attempts(), hasLength(1));
      await db.close();
      await remote.events.close();
    },
  );
}
