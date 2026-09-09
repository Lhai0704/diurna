import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/providers/integration_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExternalConflictsPage extends ConsumerWidget {
  const ExternalConflictsPage({super.key, this.connectionId});

  final String? connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(externalConflictsProvider(connectionId));
    final action = ref.watch(integrationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('外部同步冲突'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () =>
                ref.invalidate(externalConflictsProvider(connectionId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: conflicts.when(
        loading: () => const LoadingView(),
        error: (error, _) => EmptyView(message: error.toString()),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(message: '没有待处理的外部冲突');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final busy = action.isBusy('conflict:${item.id}');
              final error = action.errorOf('conflict:${item.id}');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.provider == 'google' ? 'Google Calendar' : 'Notion'} · ${conflictEntityTypeLabel(item.entityType)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(inboundReasonLabel(item.reason)),
                      if (item.entityLabel != null)
                        Text('日期：${item.entityLabel}'),
                      if (item.fieldCategories.isNotEmpty)
                        Text(
                          '差异：${item.fieldCategories.map(conflictFieldLabel).join('、')}',
                        ),
                      Text('本地版本：${item.localRevision}'),
                      if (item.blockedReason == 'remote_gone')
                        Text(
                          '外部条目已删除。选择“使用 Diurna”会保留本地副本并停止同步该条；不会从 Diurna 删除。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (!item.canKeepLocal)
                        Text(
                          conflictRecurrenceBlockedLabel(),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else if (!item.canUseRemote)
                        Text(
                          inboundReasonLabel(
                            item.blockedReason ?? 'unsupported_content',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (error != null)
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: item.canKeepLocal
                                  ? () => ref
                                        .read(
                                          integrationControllerProvider
                                              .notifier,
                                        )
                                        .resolveConflict(
                                          item,
                                          'keep_local',
                                        )
                                  : null,
                              child: const Text('使用 Diurna'),
                            ),
                            OutlinedButton(
                              onPressed: item.canUseRemote
                                  ? () => ref
                                        .read(
                                          integrationControllerProvider
                                              .notifier,
                                        )
                                        .resolveConflict(
                                          item,
                                          'use_remote',
                                        )
                                  : null,
                              child: const Text('使用外部'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
