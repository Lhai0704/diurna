import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/providers/integration_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class IntegrationsPage extends ConsumerStatefulWidget {
  const IntegrationsPage({super.key});

  @override
  ConsumerState<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends ConsumerState<IntegrationsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(integrationConnectionsProvider);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(integrationConnectionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(integrationConnectionsProvider);
    final action = ref.watch(integrationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('外部连接'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(integrationConnectionsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: connections.when(
        loading: () => const LoadingView(),
        error: (error, _) => EmptyView(message: error.toString()),
        data: (items) {
          IntegrationConnection? of(String provider) {
            for (final item in items) {
              if (item.provider == provider && item.isConnected) {
                return item;
              }
            }
            return null;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (action.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    action.error.toString(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              _ProviderCard(
                title: 'Notion',
                connection: of('notion'),
                busy: action.isLoading,
                showModules: true,
              ),
              const SizedBox(height: 16),
              _ProviderCard(
                title: 'Google Calendar',
                connection: of('google'),
                busy: action.isLoading,
                showModules: false,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProviderCard extends ConsumerWidget {
  const _ProviderCard({
    required this.title,
    required this.connection,
    required this.busy,
    required this.showModules,
  });

  final String title;
  final IntegrationConnection? connection;
  final bool busy;
  final bool showModules;

  String get provider => title == 'Notion' ? 'notion' : 'google';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = connection?.isConnected ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(connected ? '已连接' : '未连接'),
            if (connection?.displayName != null)
              Text(connection!.displayName!),
            if (connection?.lastSyncAt != null)
              Text(
                '上次同步：${DateFormat('yyyy-MM-dd HH:mm').format(connection!.lastSyncAt!.toLocal())}',
              ),
            if (connected)
              Text('结果：${_statusLabel(connection?.lastSyncStatus)}'),
            if (connection?.lastError != null) Text(connection!.lastError!),
            if (showModules && connection != null)
              ...['inbox', 'memos', 'diary'].map((key) {
                final enabled = connection!.enabledModules[key] != false;
                return CheckboxListTile(
                  dense: true,
                  title: Text(switch (key) {
                    'inbox' => 'Inbox',
                    'memos' => 'Memo',
                    _ => 'Diary',
                  }),
                  value: enabled,
                  onChanged: busy
                      ? null
                      : (value) {
                          final next = Map<String, dynamic>.from(
                            connection!.enabledModules,
                          );
                          next[key] = value ?? false;
                          ref
                              .read(integrationControllerProvider.notifier)
                              .updateModules(provider, next);
                        },
                );
              }),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (!connected)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => ref
                              .read(integrationControllerProvider.notifier)
                              .connect(provider),
                    child: const Text('连接'),
                  )
                else ...[
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => ref
                              .read(integrationControllerProvider.notifier)
                              .sync(provider),
                    child: const Text('立即同步'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => ref
                              .read(integrationControllerProvider.notifier)
                              .disconnect(provider),
                    child: const Text('断开'),
                  ),
                ],
                if (busy) const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String? status) {
    return switch (status) {
      'success' => '同步成功',
      'partial' => '部分失败',
      'failed' => '同步失败',
      'pending' => '待同步',
      _ => '尚未同步',
    };
  }
}
