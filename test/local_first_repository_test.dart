import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:diurna/features/inbox/data/inbox_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late InboxRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = InboxRepository(database, 'user-1');
  });

  tearDown(() async {
    await database.close();
  });

  test('quick capture is immediately available locally and queued', () async {
    await repository.createQuick('本地立即可见');

    final items = await repository.list();
    expect(items, hasLength(1));
    expect(items.single.content, '本地立即可见');
    expect(items.single.column, InboxColumn.pending);
    expect(await database.pendingCount('user-1'), 1);
  });

  test(
    'repeated changes to one item coalesce into one sync operation',
    () async {
      await repository.createQuick('需要整理');
      final item = (await repository.list()).single;

      await repository.setType(item, InboxItemType.action);
      final updated = (await repository.list()).single;
      await repository.setCompleted(updated, true);

      final operations = await database.pendingOperations('user-1');
      expect(operations, hasLength(1));
      expect(operations.single.operation, 'upsert');
    },
  );

  test('local delete replaces a pending upsert with a delete', () async {
    await repository.createQuick('稍后删除');
    final item = (await repository.list()).single;

    await repository.delete(item.id);

    expect(await repository.list(), isEmpty);
    final operations = await database.pendingOperations('user-1');
    expect(operations, hasLength(1));
    expect(operations.single.operation, 'delete');
  });

  test('remote snapshot cannot resurrect a locally pending delete', () async {
    await repository.createQuick('不应复活');
    final item = (await repository.list()).single;
    final staleRemoteRow = localTaskToRemoteMap(
      (await database.listTasks('user-1')).single,
    );
    await repository.delete(item.id);

    await database.applyRemoteSnapshot(
      'user-1',
      tasks: [staleRemoteRow],
      diaryEntries: const [],
      calendarEvents: const [],
    );

    expect(await repository.list(), isEmpty);
    expect(await database.pendingCount('user-1'), 1);
  });

  test(
    'deleting a topic keeps its children and detaches them locally',
    () async {
      await repository.createQuick('主题');
      await repository.createQuick('子项');
      final initialItems = await repository.list();
      final topic = initialItems.firstWhere((item) => item.content == '主题');
      final child = initialItems.firstWhere((item) => item.content == '子项');
      await repository.save(
        item: topic,
        content: topic.content,
        type: InboxItemType.research,
        isTopic: true,
      );
      final savedTopic = (await repository.list()).firstWhere(
        (item) => item.id == topic.id,
      );
      await repository.assignToTopic(child, savedTopic.id);

      await repository.delete(savedTopic.id);

      final remaining = await repository.list();
      expect(remaining, hasLength(1));
      expect(remaining.single.content, '子项');
      expect(remaining.single.parentId, isNull);
    },
  );
}
