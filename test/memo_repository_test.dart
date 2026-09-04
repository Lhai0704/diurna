import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/memo/data/memo_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late MemoRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MemoRepository(database, 'user-1');
  });

  tearDown(() async {
    await database.close();
  });

  test('creates at the top and preserves body whitespace', () async {
    await repository.save(title: ' 第一条 ', content: '第一行\n  第二行  ');
    await repository.save(title: '第二条', content: '');

    final items = await repository.list();
    expect(items.map((item) => item.title), ['第二条', '第一条']);
    expect(items.last.content, '第一行\n  第二行  ');
    expect(await database.pendingCount('user-1'), 2);
  });

  test('rejects a blank title without creating a queued write', () async {
    expect(
      () => repository.save(title: '   ', content: '正文'),
      throwsArgumentError,
    );
    expect(await repository.list(), isEmpty);
    expect(await database.pendingCount('user-1'), 0);
  });

  test('updates coalesce and keep the manual position', () async {
    final id = await repository.save(title: '标题', content: '旧正文');
    final original = (await repository.list()).single;

    await repository.save(id: id, title: '新标题', content: '新正文');

    final updated = (await repository.list()).single;
    expect(updated.title, '新标题');
    expect(updated.content, '新正文');
    expect(updated.position, original.position);
    expect(await database.pendingCount('user-1'), 1);
  });

  test('reorder normalizes positions and syncs the resulting order', () async {
    await repository.save(title: 'A', content: '');
    await repository.save(title: 'B', content: '');
    await repository.save(title: 'C', content: '');
    final before = await repository.list();

    await repository.reorder(before, 0, 2);

    final after = await repository.list();
    expect(after.map((item) => item.title), ['B', 'A', 'C']);
    expect(after.map((item) => item.position), [0, 1, 2]);
    expect(await database.pendingCount('user-1'), 3);
  });

  test(
    'a pending local delete cannot be resurrected by a stale snapshot',
    () async {
      final id = await repository.save(title: '稍后删除', content: '正文');
      final stale = localMemoToRemoteMap(
        (await database.listMemos('user-1')).single,
      );
      await repository.delete(id);

      await database.applyRemoteSnapshot(
        'user-1',
        inboxItems: const [],
        diaryEntries: const [],
        calendarEvents: const [],
        memos: [stale],
      );

      expect(await repository.list(), isEmpty);
      final operations = await database.pendingOperations('user-1');
      expect(operations.single.operation, 'delete');
    },
  );

  test('memo queries stay isolated by user', () async {
    final otherRepository = MemoRepository(database, 'user-2');
    await repository.save(title: '用户一', content: '');
    await otherRepository.save(title: '用户二', content: '');

    expect((await repository.list()).single.title, '用户一');
    expect((await otherRepository.list()).single.title, '用户二');
  });
}
