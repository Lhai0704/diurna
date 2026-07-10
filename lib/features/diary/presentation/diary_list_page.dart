import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:diurna/features/diary/presentation/diary_edit_page.dart';
import 'package:diurna/features/diary/providers/diary_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:diurna/shared/widgets/sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiaryListPage extends ConsumerWidget {
  const DiaryListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(diaryEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: const [SyncStatusIcon()],
      ),
      body: entries.when(
        data: (items) => items.isEmpty
            ? const EmptyView(message: '还没有日记。')
            : RefreshIndicator(
                onRefresh: () => triggerSync(ref),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _DiaryTile(entry: items[index]);
                  },
                ),
              ),
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDiaryEditPage(context),
        icon: const Icon(Icons.add),
        label: const Text('新建日记'),
      ),
    );
  }
}

class _DiaryTile extends ConsumerWidget {
  const _DiaryTile({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) async {
        await ref.read(diaryRepositoryProvider).delete(entry.id);
        return true;
      },
      child: ListTile(
        title: Text(entry.title),
        subtitle: Text(
          [
            AppDateUtils.formatDate(entry.entryDate),
            if (entry.mood?.isNotEmpty ?? false) entry.mood!,
            if (entry.tags.isNotEmpty) entry.tags.join(', '),
          ].join(' · '),
        ),
        onTap: () => showDiaryEditPage(context, entry: entry),
      ),
    );
  }
}
