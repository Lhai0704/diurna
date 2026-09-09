import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/providers/integration_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('云端数据变化后约 1 分钟会自动单向导出；也可点立即同步。'),
              ),
              _ProviderCard(
                title: 'Notion',
                connection: of('notion'),
                busy: action.isBusy('notion'),
                error: action.errorOf('notion'),
                showModules: true,
              ),
              const SizedBox(height: 16),
              _ProviderCard(
                title: 'Google Calendar',
                connection: of('google'),
                busy: action.isBusy('google'),
                error: action.errorOf('google'),
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
    this.error,
  });

  final String title;
  final IntegrationConnection? connection;
  final bool busy;
  final bool showModules;
  final String? error;

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
            if (connection?.displayName != null) Text(connection!.displayName!),
            if (connection?.lastSyncAt != null)
              Text(
                '上次同步：${DateFormat('yyyy-MM-dd HH:mm').format(connection!.lastSyncAt!.toLocal())}',
              ),
            if (connected)
              Text('结果：${_statusLabel(connection?.lastSyncStatus)}'),
            if (connection?.isReauthRequired == true)
              Text(
                '授权已过期，请断开后重新连接',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (connection?.lastError != null)
              Text(connection!.lastError!),
            if (connected && connection != null)
              ..._inboundStatusLines(context, connection!),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
                  if ((connection?.openConflictCount ?? 0) > 0)
                    OutlinedButton(
                      onPressed: () => context.push(
                        '/settings/integrations/conflicts?connectionId=${connection!.id}',
                      ),
                      child: const Text('查看冲突'),
                    ),
                ],
                if (busy)
                  const Padding(
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

  List<Widget> _inboundStatusLines(
    BuildContext context,
    IntegrationConnection connection,
  ) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final statusColor = switch (connection.inboundStatus) {
      'error' => theme.colorScheme.error,
      'degraded' => theme.colorScheme.tertiary,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final hint = inboundDegradedHint(
      connection.provider,
      connection.inboundStatus,
    );
    final errorCode = safeInboundCode(connection.inboundError);
    final reasons = connection.conflictReasons
        .map(inboundReasonLabel)
        .toSet()
        .toList();
    return [
      const SizedBox(height: 8),
      Text(
        inboundStatusLabel(connection.inboundStatus),
        style: theme.textTheme.bodyMedium?.copyWith(color: statusColor),
      ),
      if (hint != null) Text(hint, style: muted),
      if (connection.lastInboundAt != null)
        Text(
          '上次入站：${DateFormat('yyyy-MM-dd HH:mm').format(connection.lastInboundAt!.toLocal())}',
          style: muted,
        ),
      if (connection.lastInboundResult != null)
        Text(
          '入站结果：${inboundResultLabel(connection.lastInboundResult)}',
          style: muted,
        ),
      if (errorCode != null && connection.inboundError != 'REAUTH_REQUIRED')
        Text('入站错误：$errorCode', style: muted?.copyWith(color: statusColor)),
      if (connection.openConflictCount > 0)
        Text('未处理冲突：${connection.openConflictCount}', style: muted),
      if (connection.remoteDeletedCount > 0)
        Text('远端已删除：${connection.remoteDeletedCount}', style: muted),
      for (final reason in reasons) Text(reason, style: muted),
    ];
  }
}
