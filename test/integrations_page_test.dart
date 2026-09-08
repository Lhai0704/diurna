import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/data/integration_repository.dart';
import 'package:diurna/features/integrations/presentation/integrations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo extends IntegrationRepository {
  _FakeRepo(this.connections) : super.unavailable();

  final List<IntegrationConnection> connections;

  @override
  bool get isAvailable => true;

  @override
  Future<List<IntegrationConnection>> listConnections() async => connections;
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
  });
}
