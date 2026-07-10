import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:diurna/features/inbox/presentation/inbox_edit_sheet.dart';
import 'package:diurna/features/inbox/providers/inbox_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InboxFilter { all, idea, action, research, resource, untyped, archived }

extension InboxFilterX on InboxFilter {
  String get label => switch (this) {
    InboxFilter.all => '全部',
    InboxFilter.idea => '想法',
    InboxFilter.action => '行动',
    InboxFilter.research => '研究',
    InboxFilter.resource => '资料',
    InboxFilter.untyped => '无类型',
    InboxFilter.archived => '已归档',
  };

  InboxItemType? get type => switch (this) {
    InboxFilter.idea => InboxItemType.idea,
    InboxFilter.action => InboxItemType.action,
    InboxFilter.research => InboxItemType.research,
    InboxFilter.resource => InboxItemType.resource,
    _ => null,
  };
}

class InboxBoard extends ConsumerStatefulWidget {
  const InboxBoard({
    required this.expanded,
    this.onExpand,
    this.headerAction,
    super.key,
  });

  final bool expanded;
  final VoidCallback? onExpand;
  final Widget? headerAction;

  @override
  ConsumerState<InboxBoard> createState() => _InboxBoardState();
}

class _InboxBoardState extends ConsumerState<InboxBoard> {
  InboxFilter _filter = InboxFilter.all;
  String _query = '';

  Future<void> _refresh() async {
    await triggerSync(ref);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inboxItemsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        if (widget.expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: '搜索内容关键词',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        Expanded(
          child: items.when(
            data: (allItems) {
              final visible = allItems.where(_matchesFilter).toList();
              if (visible.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 220,
                        child: EmptyView(
                          message: _filter == InboxFilter.archived
                              ? '还没有已归档内容。'
                              : '还没有符合条件的收集内容。',
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _InboxColumns(
                visibleItems: visible,
                allItems: allItems,
                expanded: widget.expanded,
                onRefresh: _refresh,
              );
            },
            error: (error, stackTrace) => EmptyView(message: error.toString()),
            loading: () => const LoadingView(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text('收集箱', style: Theme.of(context).textTheme.titleLarge),
          ),
          PopupMenuButton<InboxFilter>(
            initialValue: _filter,
            tooltip: '筛选：${_filter.label}',
            icon: Badge(
              isLabelVisible: _filter != InboxFilter.all,
              smallSize: 7,
              child: const Icon(Icons.filter_list),
            ),
            itemBuilder: (context) => [
              for (final filter in InboxFilter.values)
                PopupMenuItem(
                  value: filter,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: _filter == filter
                            ? const Icon(Icons.check, size: 18)
                            : null,
                      ),
                      Text(filter.label),
                    ],
                  ),
                ),
            ],
            onSelected: (value) => setState(() => _filter = value),
          ),
          if (widget.onExpand != null)
            IconButton(
              tooltip: '展开收集箱',
              onPressed: widget.onExpand,
              icon: const Icon(Icons.open_in_full),
            ),
          ?widget.headerAction,
          IconButton(
            tooltip: '快速记录',
            onPressed: () => showQuickCapture(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(InboxItem item) {
    final archivedFilter = _filter == InboxFilter.archived;
    if (item.isArchived != archivedFilter || item.parentId != null) {
      return false;
    }
    if (_query.isNotEmpty &&
        !item.content.toLowerCase().contains(_query.toLowerCase())) {
      return false;
    }
    if (_filter == InboxFilter.untyped) {
      return item.type == null;
    }
    if (_filter.type != null) {
      return item.type == _filter.type;
    }
    return true;
  }
}

class _InboxColumns extends StatelessWidget {
  const _InboxColumns({
    required this.visibleItems,
    required this.allItems,
    required this.expanded,
    required this.onRefresh,
  });

  final List<InboxItem> visibleItems;
  final List<InboxItem> allItems;
  final bool expanded;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final focus = visibleItems
        .where((item) => item.column == InboxColumn.focus)
        .toList();
    final pending = visibleItems
        .where((item) => item.column == InboxColumn.pending)
        .toList();
    focus.sort((a, b) => a.position.compareTo(b.position));
    pending.sort((a, b) => a.position.compareTo(b.position));

    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 16 : 8, 0, expanded ? 16 : 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: expanded ? 11 : 1,
            child: _InboxColumnView(
              column: InboxColumn.focus,
              items: focus,
              allItems: allItems,
              onRefresh: onRefresh,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: expanded ? 9 : 1,
            child: _InboxColumnView(
              column: InboxColumn.pending,
              items: pending,
              allItems: allItems,
              onRefresh: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxColumnView extends ConsumerWidget {
  const _InboxColumnView({
    required this.column,
    required this.items,
    required this.allItems,
    required this.onRefresh,
  });

  final InboxColumn column;
  final List<InboxItem> items;
  final List<InboxItem> allItems;
  final Future<void> Function() onRefresh;

  Future<void> _moveToEnd(WidgetRef ref, InboxItem item) async {
    await ref
        .read(inboxRepositoryProvider)
        .moveBefore(item, column, null, allItems);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<InboxItem>(
      onWillAcceptWithDetails: (details) => !details.data.isArchived,
      onAcceptWithDetails: (details) => _moveToEnd(ref, details.data),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: hovering
                ? colorScheme.primaryContainer.withValues(alpha: 0.28)
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hovering
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${items.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView.builder(
                    key: PageStorageKey(column.databaseValue),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _DropBeforeTarget(item: item, allItems: allItems);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DropBeforeTarget extends ConsumerWidget {
  const _DropBeforeTarget({required this.item, required this.allItems});

  final InboxItem item;
  final List<InboxItem> allItems;

  Future<void> _accept(WidgetRef ref, InboxItem dragged) async {
    await ref
        .read(inboxRepositoryProvider)
        .moveBefore(dragged, item.column, item.id, allItems);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<InboxItem>(
      onWillAcceptWithDetails: (details) =>
          details.data.id != item.id && !details.data.isArchived,
      onAcceptWithDetails: (details) => _accept(ref, details.data),
      builder: (context, candidates, rejected) {
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: candidates.isEmpty ? 0 : 4,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Theme.of(context).colorScheme.primary,
            ),
            LayoutBuilder(
              builder: (context, constraints) => LongPressDraggable<InboxItem>(
                data: item,
                maxSimultaneousDrags: item.isArchived ? 0 : 1,
                feedback: SizedBox(
                  width: constraints.maxWidth,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8,
                    child: _InboxCard(
                      item: item,
                      allItems: allItems,
                      interactive: false,
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.28,
                  child: _InboxCard(item: item, allItems: allItems),
                ),
                child: _InboxCard(item: item, allItems: allItems),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _ItemAction {
  edit,
  setType,
  moveOtherColumn,
  moveFirst,
  moveLast,
  convertToTask,
  assignTopic,
  pin,
  archive,
  delete,
}

class _InboxCard extends ConsumerWidget {
  const _InboxCard({
    required this.item,
    required this.allItems,
    this.interactive = true,
  });

  final InboxItem item;
  final List<InboxItem> allItems;
  final bool interactive;

  List<InboxItem> get _children => allItems
      .where(
        (candidate) => candidate.parentId == item.id && !candidate.isArchived,
      )
      .toList();

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ItemAction action,
  ) async {
    final repository = ref.read(inboxRepositoryProvider);
    switch (action) {
      case _ItemAction.edit:
        await showInboxEditSheet(context, item: item);
      case _ItemAction.setType:
        final type = await _chooseType(context);
        if (!context.mounted) {
          return;
        }
        if (type.didChoose) {
          await _run(context, ref, () => repository.setType(item, type.value));
        }
      case _ItemAction.moveOtherColumn:
        final target = item.column == InboxColumn.focus
            ? InboxColumn.pending
            : InboxColumn.focus;
        await _run(
          context,
          ref,
          () => repository.moveToEdge(item, target, true, allItems),
        );
      case _ItemAction.moveFirst:
        await _run(
          context,
          ref,
          () => repository.moveToEdge(item, item.column, true, allItems),
        );
      case _ItemAction.moveLast:
        await _run(
          context,
          ref,
          () => repository.moveToEdge(item, item.column, false, allItems),
        );
      case _ItemAction.convertToTask:
        await showInboxEditSheet(context, item: item, convertToAction: true);
      case _ItemAction.assignTopic:
        final choice = await _chooseTopic(context);
        if (!context.mounted) {
          return;
        }
        if (choice.didChoose) {
          await _run(
            context,
            ref,
            () => repository.assignToTopic(item, choice.topicId),
          );
        }
      case _ItemAction.pin:
        await _run(context, ref, () => repository.togglePinned(item, allItems));
      case _ItemAction.archive:
        await _run(
          context,
          ref,
          () => repository.setArchived(item, !item.isArchived),
        );
      case _ItemAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除内容？'),
            content: const Text('删除后无法恢复；如需保留，请使用归档。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (!context.mounted) {
          return;
        }
        if (confirmed == true) {
          await _run(context, ref, () => repository.delete(item.id));
        }
    }
  }

  Future<_TypeChoice> _chooseType(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('设置类型'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('none'),
            child: const Text('无类型'),
          ),
          for (final type in InboxItemType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(type.databaseValue),
              child: Text(type.label),
            ),
        ],
      ),
    );
    if (value == null) {
      return const _TypeChoice(false, null);
    }
    return _TypeChoice(
      true,
      value == 'none' ? null : InboxItemTypeX.fromDatabase(value),
    );
  }

  Future<_TopicChoice> _chooseTopic(BuildContext context) async {
    final topics = allItems
        .where(
          (candidate) =>
              candidate.isTopic &&
              !candidate.isArchived &&
              candidate.id != item.id &&
              candidate.parentId == null,
        )
        .toList();
    return await showDialog<_TopicChoice>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('归入主题'),
            children: [
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(const _TopicChoice(true, null)),
                child: const Text('不归入主题'),
              ),
              if (topics.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('还没有主题。可在编辑内容时将研究项设为主题。'),
                ),
              for (final topic in topics)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(context).pop(_TopicChoice(true, topic.id)),
                  child: Text(topic.content, maxLines: 2),
                ),
            ],
          ),
        ) ??
        const _TopicChoice(false, null);
  }

  void _open(BuildContext context) {
    if (!interactive) {
      return;
    }
    if (item.isTopic) {
      showDialog<void>(
        context: context,
        builder: (context) =>
            _TopicDialog(topic: item, children: _children, allItems: allItems),
      );
    } else {
      showInboxEditSheet(context, item: item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final children = _children;
    final details = <String>[
      if (item.isAction && item.dueDate != null)
        '截止 ${AppDateUtils.formatDate(item.dueDate!)}',
      if (item.isAction && item.priority != null) '优先级 ${item.priority}',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: interactive ? () => _open(context) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  if (item.isTopic)
                    const _TypeTag(label: '研究主题')
                  else if (item.type != null)
                    _TypeTag(label: item.type!.label),
                  const Spacer(),
                  if (item.isPinned)
                    Icon(
                      Icons.push_pin,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.isAction)
                    Transform.translate(
                      offset: const Offset(-5, -7),
                      child: Checkbox(
                        visualDensity: VisualDensity.compact,
                        value: item.isCompleted,
                        onChanged: interactive
                            ? (value) => _run(
                                context,
                                ref,
                                () => ref
                                    .read(inboxRepositoryProvider)
                                    .setCompleted(item, value ?? false),
                              )
                            : null,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: item.isCompleted
                          ? theme.textTheme.bodyMedium?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (item.isTopic) ...[
                const SizedBox(height: 6),
                Text(
                  '${children.length} 个子项',
                  style: theme.textTheme.labelMedium,
                ),
                for (final child in children.take(2))
                  Text(
                    '· ${child.content}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                if (children.length > 2)
                  Text('· …', style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      details.isEmpty
                          ? _friendlyTime(item.createdAt)
                          : details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  if (interactive)
                    PopupMenuButton<_ItemAction>(
                      tooltip: '更多操作',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onSelected: (value) => _handleAction(context, ref, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _ItemAction.edit,
                          child: Text('编辑'),
                        ),
                        if (!item.isTopic)
                          const PopupMenuItem(
                            value: _ItemAction.setType,
                            child: Text('设置类型'),
                          ),
                        PopupMenuItem(
                          value: _ItemAction.moveOtherColumn,
                          child: Text(
                            item.column == InboxColumn.focus
                                ? '移到待整理'
                                : '移到关注中',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _ItemAction.moveFirst,
                          child: Text('移到最前'),
                        ),
                        const PopupMenuItem(
                          value: _ItemAction.moveLast,
                          child: Text('移到最后'),
                        ),
                        if (!item.isAction)
                          const PopupMenuItem(
                            value: _ItemAction.convertToTask,
                            child: Text('转为待办'),
                          ),
                        if (!item.isTopic)
                          const PopupMenuItem(
                            value: _ItemAction.assignTopic,
                            child: Text('归入主题'),
                          ),
                        PopupMenuItem(
                          value: _ItemAction.pin,
                          child: Text(item.isPinned ? '取消置顶' : '置顶'),
                        ),
                        PopupMenuItem(
                          value: _ItemAction.archive,
                          child: Text(item.isArchived ? '取消归档' : '归档'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: _ItemAction.delete,
                          child: Text('删除'),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _TopicDialog extends ConsumerWidget {
  const _TopicDialog({
    required this.topic,
    required this.children,
    required this.allItems,
  });

  final InboxItem topic;
  final List<InboxItem> children;
  final List<InboxItem> allItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text(topic.content),
      content: SizedBox(
        width: 620,
        height: 420,
        child: children.isEmpty
            ? const EmptyView(message: '这个主题还没有子项。')
            : ListView.separated(
                itemCount: children.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final child = children[index];
                  return ListTile(
                    leading: child.type == null
                        ? null
                        : _TypeTag(label: child.type!.label),
                    title: Text(child.content, maxLines: 3),
                    onTap: () => showInboxEditSheet(context, item: child),
                    trailing: IconButton(
                      tooltip: '移出主题',
                      onPressed: () async {
                        await ref
                            .read(inboxRepositoryProvider)
                            .assignToTopic(child, null);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.link_off),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => showInboxEditSheet(context, item: topic),
          child: const Text('编辑主题'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _TypeChoice {
  const _TypeChoice(this.didChoose, this.value);
  final bool didChoose;
  final InboxItemType? value;
}

class _TopicChoice {
  const _TopicChoice(this.didChoose, this.topicId);
  final bool didChoose;
  final String? topicId;
}

String _friendlyTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '今天 $time';
  }
  return '${local.month} 月 ${local.day} 日 $time';
}
