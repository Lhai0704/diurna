import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/data/integration_repository.dart';
import 'package:diurna/features/integrations/presentation/external_conflicts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo extends IntegrationRepository {
  _FakeRepo(this.conflicts) : super.unavailable();

  List<ExternalConflictSummary> conflicts;
  final List<({String id, String choice, int revision})> resolved = [];
  ConflictResolveResult nextResult = const ConflictResolveResult(
    ok: true,
    result: 'resolved_local',
  );

  @override
  bool get isAvailable => true;

  @override
  Future<List<ExternalConflictSummary>> listConflicts({
    String? connectionId,
  }) async {
    return conflicts;
  }

  @override
  Future<ConflictResolveResult> resolveConflict({
    required String conflictId,
    required String choice,
    required int expectedLocalRevision,
  }) async {
    resolved.add((
      id: conflictId,
      choice: choice,
      revision: expectedLocalRevision,
    ));
    if (!nextResult.ok) {
      return nextResult;
    }
    conflicts = [
      for (final item in conflicts)
        if (item.id != conflictId) item,
    ];
    return nextResult;
  }
}

ExternalConflictSummary _diaryConflict() {
  return const ExternalConflictSummary(
    id: 'c1',
    connectionId: 'n1',
    provider: 'notion',
    entityType: 'diary_entries',
    entityId: 'e1',
    reason: 'bootstrap_remote_drift',
    localRevision: 1,
    lastSyncedRevision: 1,
    canKeepLocalPush: true,
    canUseRemote: true,
    entityLabel: '2026-07-31',
    fieldCategories: ['title', 'content'],
  );
}

void main() {
  testWidgets('shows safe summary without snapshots and both actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([_diaryConflict()]),
          ),
        ],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notion · 日记'), findsOneWidget);
    expect(find.text('远端与本地不一致'), findsOneWidget);
    expect(find.text('日期：2026-07-31'), findsOneWidget);
    expect(find.text('差异：标题、正文'), findsOneWidget);
    expect(find.text('使用 Diurna'), findsOneWidget);
    expect(find.text('使用外部'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('recurring Google events disable both resolve actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              const ExternalConflictSummary(
                id: 'c-recurring',
                connectionId: 'g1',
                provider: 'google',
                entityType: 'calendar_events',
                entityId: 'e-recurring',
                reason: 'unsupported_recurrence',
                localRevision: 1,
                lastSyncedRevision: 1,
                canKeepLocal: false,
                canKeepLocalPush: false,
                canUseRemote: false,
                blockedReason: 'unsupported_recurrence',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final keepLocal = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '使用 Diurna'),
    );
    final useRemote = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '使用外部'),
    );
    expect(keepLocal.onPressed, isNull);
    expect(useRemote.onPressed, isNull);
    expect(find.textContaining('无法自动处理'), findsOneWidget);
  });

  testWidgets('unsupported remote disables Use External', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              const ExternalConflictSummary(
                id: 'c2',
                connectionId: 'n1',
                provider: 'notion',
                entityType: 'diary_entries',
                entityId: 'e2',
                reason: 'unsupported_content',
                localRevision: 1,
                lastSyncedRevision: 1,
                canKeepLocalPush: true,
                canUseRemote: false,
                blockedReason: 'unsupported_content',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final useRemote = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '使用外部'),
    );
    expect(useRemote.onPressed, isNull);
    expect(find.text('不支持的 Notion 正文'), findsWidgets);
  });

  testWidgets('Keep Diurna sends expected local revision', (tester) async {
    final repo = _FakeRepo([_diaryConflict()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [integrationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 Diurna'));
    await tester.pumpAndSettle();
    expect(repo.resolved, hasLength(1));
    expect(repo.resolved.single.choice, 'keep_local');
    expect(repo.resolved.single.revision, 1);
    expect(find.text('没有待处理的外部冲突'), findsOneWidget);
  });

  testWidgets('stale conflict shows a safe error', (tester) async {
    final repo = _FakeRepo([_diaryConflict()])
      ..nextResult = const ConflictResolveResult(
        ok: false,
        errorCode: 'STALE_CONFLICT',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [integrationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用外部'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地已变化，请刷新后重新选择'), findsOneWidget);
    expect(find.text('使用 Diurna'), findsOneWidget);
  });

  testWidgets('verify failure shows a safe retry label, not FunctionException', (
    tester,
  ) async {
    final repo = _FakeRepo([_diaryConflict()])
      ..nextResult = const ConflictResolveResult(
        ok: false,
        result: 'error',
        errorCode: 'PROVIDER_VERIFY_FAILED',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [integrationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ExternalConflictsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 Diurna'));
    await tester.pumpAndSettle();
    expect(find.textContaining('外部写入尚未通过校验'), findsOneWidget);
    expect(find.textContaining('FunctionException'), findsNothing);
    expect(find.textContaining('PROVIDER_VERIFY_FAILED'), findsNothing);
    expect(find.text('使用 Diurna'), findsOneWidget);
  });
}
