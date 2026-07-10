import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:diurna/features/calendar/presentation/event_edit_page.dart';
import 'package:diurna/features/calendar/providers/calendar_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:diurna/shared/widgets/sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(calendarEventsProvider);
    final todayOnly = ref.watch(todayOnlyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日程待办'),
        actions: [
          const SyncStatusIcon(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: const Text('今天'),
              selected: todayOnly,
              onSelected: (value) =>
                  ref.read(todayOnlyProvider.notifier).set(value),
            ),
          ),
        ],
      ),
      body: events.when(
        data: (items) => items.isEmpty
            ? EmptyView(message: todayOnly ? '今天没有待办。' : '还没有日程待办。')
            : RefreshIndicator(
                onRefresh: () => triggerSync(ref),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _EventTile(event: items[index]);
                  },
                ),
              ),
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showEventEditPage(context),
        icon: const Icon(Icons.add),
        label: const Text('新建待办'),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) async {
        await ref.read(calendarRepositoryProvider).delete(event.id);
        return true;
      },
      child: ListTile(
        leading: Checkbox(
          value: event.isCompleted,
          onChanged: (value) => ref
              .read(calendarRepositoryProvider)
              .setCompleted(event, value ?? false),
        ),
        title: Text(
          event.title,
          style: event.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          [
            AppDateUtils.formatDate(event.scheduledDate),
            if (event.remindAt != null)
              '提醒 ${AppDateUtils.formatDateTime(event.remindAt!)}',
          ].join(' · '),
        ),
        onTap: () => showEventEditPage(context, event: event),
      ),
    );
  }
}
