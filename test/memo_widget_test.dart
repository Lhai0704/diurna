import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/core/config/env.dart';
import 'package:diurna/features/memo/data/memo_repository.dart';
import 'package:diurna/features/memo/presentation/memo_page.dart';
import 'package:diurna/features/memo/providers/memo_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late MemoRepository repository;

  setUpAll(AppEnv.load);

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MemoRepository(database, 'user-1');
  });

  tearDown(() async {
    await database.close();
  });

  Widget app(Widget child) {
    return ProviderScope(
      overrides: [memoRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('wide board creates a memo and protects unsaved changes', (
    tester,
  ) async {
    await repository.save(title: '现有备忘录', content: '原正文');
    await tester.pumpWidget(
      app(const SizedBox(width: 900, height: 600, child: MemoBoard())),
    );
    await tester.pumpAndSettle();

    expect(find.text('现有备忘录'), findsWidgets);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(1), '尚未保存的正文');
    await tester.tap(find.widgetWithText(TextButton, '新建'));
    await tester.pumpAndSettle();

    expect(find.text('有未保存的修改'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '尚未保存的正文');

    await tester.tap(find.widgetWithText(TextButton, '新建'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '放弃'));
    await tester.pumpAndSettle();
    final draftFields = find.byType(TextField);
    await tester.enterText(draftFields.first, '新备忘录');
    await tester.enterText(draftFields.at(1), '保留\n换行');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final items = await repository.list();
    expect(items.map((item) => item.title), ['新备忘录', '现有备忘录']);
    expect(items.first.content, '保留\n换行');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('memo page switches between wide and mobile layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(app(const MemoPage()));
    await tester.pumpAndSettle();
    expect(find.text('备忘录列表'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 760);
    await tester.pumpAndSettle();
    expect(find.text('新建备忘录'), findsOneWidget);
    expect(find.text('备忘录列表'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('mobile detail validates title and guards back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app(const MemoDetailPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入标题'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '手机备忘录');
    await tester.enterText(fields.at(1), '尚未保存');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('新建备忘录'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '尚未保存',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
