import 'dart:convert';

import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/calendar/data/calendar_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CalendarRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = CalendarRepository(database, 'user-1');
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'saves a date-based calendar todo without legacy event fields',
    () async {
      await repository.save(
        title: '准备周报',
        scheduledDate: DateTime(2026, 7, 11),
        note: '整理本周进度',
      );

      final item = (await repository.watch().first).single;
      expect(item.title, '准备周报');
      expect(item.scheduledDate, DateTime(2026, 7, 11));
      expect(item.isCompleted, isFalse);

      final operation = (await database.pendingOperations('user-1')).single;
      final payload =
          jsonDecode(operation.payloadJson!) as Map<String, dynamic>;
      expect(payload['event_date'], '2026-07-11');
      expect(payload['is_completed'], isFalse);
      expect(payload, isNot(contains('starts_at')));
      expect(payload, isNot(contains('ends_at')));
      expect(payload, isNot(contains('location')));
    },
  );

  test(
    'completed todos are ordered after open todos on the same day',
    () async {
      await repository.save(
        title: '已完成事项',
        scheduledDate: DateTime(2026, 7, 11),
        isCompleted: true,
      );
      await repository.save(
        title: '未完成事项',
        scheduledDate: DateTime(2026, 7, 11),
      );

      final items = await repository.watch().first;
      expect(items.map((item) => item.title), ['未完成事项', '已完成事项']);

      await repository.setCompleted(items.first, true);
      final completedItems = await repository.watch().first;
      expect(completedItems, hasLength(2));
      expect(completedItems.every((item) => item.isCompleted), isTrue);
    },
  );
}
