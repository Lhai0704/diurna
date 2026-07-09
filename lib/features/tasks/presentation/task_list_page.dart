import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:diurna/features/tasks/presentation/task_edit_page.dart';
import 'package:diurna/features/tasks/providers/task_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskListPage extends ConsumerWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: tasks.when(
        data: (items) => items.isEmpty
            ? const EmptyView(message: '还没有待办事项。')
            : RefreshIndicator(
                onRefresh: () => ref.refresh(tasksProvider.future),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final task = items[index];
                    return _TaskTile(task: task);
                  },
                ),
              ),
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskEditPage(context),
        icon: const Icon(Icons.add),
        label: const Text('新建待办'),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = [
      if (task.dueDate != null) '截止 ${AppDateUtils.formatDate(task.dueDate!)}',
      '优先级 ${task.priority}',
      if (task.note?.isNotEmpty ?? false) task.note!,
    ];

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) async {
        await ref.read(taskRepositoryProvider).delete(task.id);
        ref.invalidate(tasksProvider);
        return true;
      },
      child: ListTile(
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (value) async {
            await ref
                .read(taskRepositoryProvider)
                .setCompleted(task, value ?? false);
            ref.invalidate(tasksProvider);
          },
        ),
        title: Text(
          task.title,
          style: task.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(subtitleParts.join(' · ')),
        onTap: () => showTaskEditPage(context, task: task),
      ),
    );
  }
}
