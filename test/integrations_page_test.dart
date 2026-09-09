import 'dart:async';

import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/data/integration_repository.dart';
import 'package:diurna/features/integrations/presentation/integrations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo extends IntegrationRepository {
  _FakeRepo(this.connections, {this.syncGate}) : super.unavailable();

  final List<IntegrationConnection> connections;
  final Completer<void>? syncGate;
  final List<String> synced = [];

  @override
  bool get isAvailable => true;

  @override
  Future<List<IntegrationConnection>> listConnections() async => connections;

  @override
  Future<SyncResult> sync(String provider, {String? runId}) async {
    synced.add(provider);
    final gate = syncGate;
    if (gate != null) {
      await gate.future;
    }
    return const SyncResult(ok: true, status: 'success', incomplete: false);
  }
}

IntegrationConnection _connected(String provider) {
  return IntegrationConnection(
    id: provider,
    provider: provider,
    status: 'connected',
    lastSyncStatus: 'success',
    enabledModules: const {'inbox': true, 'memos': true, 'diary': true},
    displayName: provider,
    lastSyncAt: DateTime.utc(2026, 9, 8, 5, 42),
  );
}

void main() {
  testWidgets('shows disconnected providers', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(_FakeRepo(const [])),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notion'), findsOneWidget);
    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.text('未连接'), findsNWidgets(2));
    expect(find.text('连接'), findsNWidgets(2));
    expect(find.textContaining('尚未同步'), findsNothing);
  });

  testWidgets('shows connected Notion state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              IntegrationConnection(
                id: '1',
                provider: 'notion',
                status: 'connected',
                lastSyncStatus: 'success',
                enabledModules: const {
                  'inbox': true,
                  'memos': true,
                  'diary': true,
                },
                displayName: 'Workspace A',
                lastSyncAt: DateTime.utc(2026, 9, 8, 5, 42),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('Workspace A'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
    expect(find.text('断开'), findsOneWidget);
    expect(find.text('结果：同步成功'), findsOneWidget);
    expect(find.text('入站未启用'), findsOneWidget);
  });

  testWidgets('shows Google degraded inbound without disabling the connection', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              IntegrationConnection(
                id: 'g1',
                provider: 'google',
                status: 'connected',
                lastSyncStatus: 'success',
                enabledModules: const {},
                displayName: 'Diurna',
                inboundStatus: 'degraded',
                inboundError: 'WATCH_FAILED',
                lastInboundAt: DateTime.utc(2026, 9, 9, 12),
                lastInboundResult: 'repair',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('入站降级'), findsOneWidget);
    expect(find.textContaining('定时修复仍会同步已关联事件'), findsOneWidget);
    expect(find.textContaining('连接未停用'), findsOneWidget);
    expect(find.text('入站错误：WATCH_FAILED'), findsOneWidget);
    expect(find.text('入站结果：定时修复'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
    expect(find.text('断开'), findsOneWidget);
  });

  testWidgets('shows open conflicts and remote-deleted counts', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              IntegrationConnection(
                id: 'n1',
                provider: 'notion',
                status: 'connected',
                lastSyncStatus: 'success',
                enabledModules: const {
                  'inbox': true,
                  'memos': true,
                  'diary': true,
                },
                inboundStatus: 'active',
                openConflictCount: 2,
                remoteDeletedCount: 1,
                conflictReasons: const [
                  'unsupported_content',
                  'bootstrap_remote_drift',
                ],
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('入站正常'), findsOneWidget);
    expect(find.text('未处理冲突：2'), findsOneWidget);
    expect(find.text('远端已删除：1'), findsOneWidget);
    expect(find.text('不支持的 Notion 正文'), findsOneWidget);
    expect(find.text('远端与本地不一致'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
  });

  testWidgets('timed-event conflicts are indicated without a resolver', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              IntegrationConnection(
                id: 'g1',
                provider: 'google',
                status: 'connected',
                lastSyncStatus: 'success',
                enabledModules: const {},
                inboundStatus: 'active',
                openConflictCount: 1,
                conflictReasons: const ['unsupported_timed_event'],
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('不支持的定时事件'), findsOneWidget);
    expect(find.text('未处理冲突：1'), findsOneWidget);
  });

  testWidgets('does not render token-like inbound errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationRepositoryProvider.overrideWithValue(
            _FakeRepo([
              IntegrationConnection(
                id: 'g1',
                provider: 'google',
                status: 'connected',
                lastSyncStatus: 'success',
                enabledModules: const {},
                inboundStatus: 'error',
                inboundError: 'channel-token-secret',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('token'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('入站错误'), findsOneWidget);
  });

  testWidgets('Notion sync busy state does not disable Google Calendar', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _FakeRepo([
      _connected('notion'),
      _connected('google'),
    ], syncGate: gate);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [integrationRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: IntegrationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('立即同步').first);
    await tester.pump();

    final buttons = tester
        .widgetList<FilledButton>(find.widgetWithText(FilledButton, '立即同步'))
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repo.synced, ['notion']);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
