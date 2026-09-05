import 'package:diurna_core/diurna_core.dart';
import 'package:diurna_core/src/core/sync/versioned_sync_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  late DiurnaService service;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = DiurnaService(db, 'u1');
  });
  tearDown(() => db.close());
  test('stale versions fail without writing, append preserves body', () async {
    final memo = await service.createMemo(title: 'MCP', content: ' body\n');
    final updated = await service.updateMemo(
      memo['id'],
      memo['version'],
      const MemoPatch(appendContent: 'auth'),
    );
    expect(updated['content'], ' body\nauth');
    await expectLater(
      service.updateMemo(
        memo['id'],
        memo['version'],
        const MemoPatch(title: 'stale'),
      ),
      throwsA(isA<DiurnaException>()),
    );
    expect((await service.get(EntityKind.memos, memo['id']))['title'], 'MCP');
  });
  test('request ID retries create once and mismatched retries fail', () async {
    final a = await service.createMemo(title: 'A', requestId: 'request');
    expect(
      (await service.createMemo(title: 'A', requestId: 'request'))['id'],
      a['id'],
    );
    await expectLater(
      service.createMemo(title: 'B', requestId: 'request'),
      throwsA(isA<DiurnaException>()),
    );
    expect((await service.memos.list()).length, 1);
  });
  test('search treats wildcard characters literally and spans tags', () async {
    await service.createMemo(title: '100%_done');
    await service.createDiary(
      title: 'day',
      content: 'body',
      date: DateTime(2026, 9, 5),
      tags: ['MCP'],
    );
    expect(((await service.search('%_'))['memos']['items'] as List).length, 1);
    expect(((await service.search('mcp'))['diary']['items'] as List).length, 1);
    expect(() => parseDate('2026-02-30'), throwsA(isA<DiurnaException>()));
  });
  test('unknown updates and cross-user reads do not create entities', () async {
    final a = await service.createMemo(title: 'private');
    await expectLater(
      DiurnaService(db, 'u2').get(EntityKind.memos, a['id']),
      throwsA(isA<DiurnaException>()),
    );
    await expectLater(
      service.memos.save(id: 'missing', title: 'x', content: ''),
      throwsA(isA<DiurnaException>()),
    );
  });
  test('topic relationships and completion constraints are enforced', () async {
    final a = await service.createInbox('topic');
    final topic = await service.updateInbox(
      a['id'],
      a['version'],
      const InboxPatch(isTopic: true),
    );
    await expectLater(
      service.assignInbox(topic['id'], topic['version'], topic['id']),
      throwsA(isA<DiurnaException>()),
    );
    final child = await service.createInbox('child');
    await service.assignInbox(child['id'], child['version'], topic['id']);
    await service.archiveInbox(topic['id'], topic['version'], true);
    expect((await service.inbox.get(child['id'])).parentId, isNull);
    await expectLater(
      service.inbox.setCompleted(await service.inbox.get(child['id']), true),
      throwsA(isA<DiurnaException>()),
    );
  });
  test(
    'frozen attempt survives newer local edits and ACK preserves them',
    () async {
      final a = await service.createMemo(title: 'before');
      final store = VersionedSyncStore(db, 'u1');
      final attempt = (await store.attempts()).single;
      await service.updateMemo(
        a['id'],
        a['version'],
        const MemoPatch(title: 'after'),
      );
      expect((await store.attempts()).single.id, attempt.id);
      await store.acknowledge(attempt, [
        {'id': a['id'], 'revision': 1},
      ]);
      expect(await db.pendingCount('u1'), 1);
      final next = (await store.attempts()).single;
      expect(next.changes.single['expected_revision'], 1);
      expect(next.changes.single['payload']['title'], 'after');
    },
  );
}
