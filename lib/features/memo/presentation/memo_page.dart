import 'package:diurna_core/diurna_core.dart' show DiurnaException;
import 'package:diurna/app/windows_retro_theme.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/features/memo/data/memo_model.dart';
import 'package:diurna/features/memo/providers/memo_providers.dart';
import 'package:diurna/shared/widgets/empty_view.dart';
import 'package:diurna/shared/widgets/loading_view.dart';
import 'package:diurna/shared/widgets/sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _DirtyChoice { save, discard, cancel }

Future<_DirtyChoice?> _showDirtyDialog(BuildContext context) {
  return showDialog<_DirtyChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('有未保存的修改'),
      content: const Text('保存当前修改后再继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _DirtyChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _DirtyChoice.discard),
          child: const Text('放弃'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _DirtyChoice.save),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

Future<bool> _showDeleteDialog(BuildContext context, String title) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除备忘录'),
          content: Text('确定删除“$title”吗？此操作会同步到其他设备。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}

class MemoPage extends StatelessWidget {
  const MemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 720) {
      return const Scaffold(appBar: _MemoAppBar(), body: MemoBoard());
    }
    return const _MobileMemoList();
  }
}

class _MemoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MemoAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('备忘录'), actions: const [SyncStatusIcon()]);
  }
}

class _MobileMemoList extends ConsumerWidget {
  const _MobileMemoList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memos = ref.watch(memosProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('备忘录'),
        actions: const [SyncStatusIcon()],
      ),
      body: memos.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(message: '还没有备忘录。');
          }
          return RefreshIndicator(
            onRefresh: () => triggerSync(ref),
            child: ReorderableListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(memoRepositoryProvider)
                  .reorder(items, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final memo = items[index];
                return ListTile(
                  key: ValueKey(memo.id),
                  leading: const Icon(Icons.note_outlined),
                  title: Text(
                    memo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/memos/${memo.id}'),
                );
              },
            ),
          );
        },
        error: (error, stackTrace) => EmptyView(message: error.toString()),
        loading: () => const LoadingView(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/memos/new'),
        icon: const Icon(Icons.add),
        label: const Text('新建备忘录'),
      ),
    );
  }
}

class MemoBoard extends ConsumerStatefulWidget {
  const MemoBoard({this.retro = false, super.key});

  final bool retro;

  @override
  ConsumerState<MemoBoard> createState() => _MemoBoardState();
}

class _MemoBoardState extends ConsumerState<MemoBoard> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  String? _selectedId;
  String? _loadedVersion;
  bool _draft = false;
  bool _dirty = false;
  bool _syncingText = false;
  bool _allowPop = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController()..addListener(_markDirty);
    _contentController = TextEditingController()..addListener(_markDirty);
  }

  void _markDirty() {
    if (!_syncingText && !_dirty) {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _loadMemo(Memo memo) {
    _syncingText = true;
    _titleController.text = memo.title;
    _contentController.text = memo.content;
    _syncingText = false;
    _selectedId = memo.id;
    _loadedVersion = memo.version ?? memo.updatedAt.toIso8601String();
    _draft = false;
    _dirty = false;
    _titleError = null;
  }

  void _clearEditor() {
    _syncingText = true;
    _titleController.clear();
    _contentController.clear();
    _syncingText = false;
    _selectedId = null;
    _loadedVersion = null;
    _titleError = null;
  }

  Memo? _findMemo(List<Memo> items, String? id) {
    if (id == null) {
      return null;
    }
    for (final memo in items) {
      if (memo.id == id) {
        return memo;
      }
    }
    return null;
  }

  void _reconcile(List<Memo> items) {
    if (_draft) {
      return;
    }
    final selected = _findMemo(items, _selectedId);
    if (selected == null) {
      if (!_dirty && items.isNotEmpty) {
        _loadMemo(items.first);
      } else if (!_dirty && items.isEmpty && _selectedId != null) {
        _clearEditor();
      }
      return;
    }
    final version = selected.version ?? selected.updatedAt.toIso8601String();
    if (!_dirty && version != _loadedVersion) {
      _loadMemo(selected);
    }
  }

  Future<bool> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请输入标题');
      return false;
    }
    late final String id;
    try {
      id = await ref
          .read(memoRepositoryProvider)
          .save(
            id: _draft ? null : _selectedId,
            expectedVersion: _draft ? null : _loadedVersion,
            title: title,
            content: _contentController.text,
          );
    } on DiurnaException catch (error) {
      if (mounted) {
        setState(
          () => _titleError = error.code == 'CONFLICT'
              ? '内容已在其他位置修改。草稿已保留，请重新读取后合并。'
              : error.message,
        );
      }
      return false;
    }
    if (!mounted) {
      return true;
    }
    _syncingText = true;
    _titleController.text = title;
    _syncingText = false;
    setState(() {
      _selectedId = id;
      _draft = false;
      _dirty = false;
      _titleError = null;
      _loadedVersion = null;
    });
    return true;
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) {
      return true;
    }
    final choice = await _showDirtyDialog(context);
    if (!mounted || choice == null || choice == _DirtyChoice.cancel) {
      return false;
    }
    if (choice == _DirtyChoice.save) {
      return _save();
    }
    setState(() => _dirty = false);
    return true;
  }

  Future<void> _startNew() async {
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    setState(() {
      _clearEditor();
      _draft = true;
    });
  }

  Future<void> _handleBack() async {
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        setState(() => _allowPop = false);
      }
    }
  }

  Future<void> _selectMemo(Memo memo) async {
    if (memo.id == _selectedId && !_draft) {
      return;
    }
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    setState(() => _loadMemo(memo));
  }

  Future<void> _delete(List<Memo> items) async {
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    if (_draft) {
      setState(() {
        _draft = false;
        _clearEditor();
        if (items.isNotEmpty) {
          _loadMemo(items.first);
        }
      });
      return;
    }

    final selected = _findMemo(items, _selectedId);
    final selectedId = _selectedId;
    final selectedTitle = selected?.title ?? _titleController.text.trim();
    if (selectedId == null ||
        !await _showDeleteDialog(context, selectedTitle) ||
        !mounted) {
      return;
    }
    final oldIndex = items.indexWhere((memo) => memo.id == selectedId);
    await ref.read(memoRepositoryProvider).delete(selectedId);
    if (!mounted) {
      return;
    }
    final remaining = items.where((memo) => memo.id != selectedId).toList();
    setState(() {
      _clearEditor();
      if (remaining.isNotEmpty) {
        _loadMemo(remaining[oldIndex.clamp(0, remaining.length - 1)]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final memos = ref.watch(memosProvider);
    final header = widget.retro
        ? RetroSectionHeader(
            title: '备忘录',
            trailing: RetroToolbarButton(
              tooltip: '新建备忘录',
              onPressed: _startNew,
              icon: const Icon(Icons.add),
            ),
          )
        : SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('备忘录列表', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _startNew,
                    icon: const Icon(Icons.add),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
          );

    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: memos.when(
              data: (items) {
                _reconcile(items);
                return _buildBoard(items);
              },
              error: (error, stackTrace) =>
                  EmptyView(message: error.toString()),
              loading: () => const LoadingView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(List<Memo> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = (constraints.maxWidth * 0.34).clamp(140.0, 200.0);
        final content = Row(
          children: [
            SizedBox(width: listWidth, child: _buildList(items)),
            VerticalDivider(
              width: 1,
              color: widget.retro
                  ? WindowsRetroColors.shadow
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: _buildEditor(items)),
          ],
        );
        if (!widget.retro) {
          return content;
        }
        return RetroBevel(
          kind: RetroBevelKind.sunken,
          depth: 2,
          color: WindowsRetroColors.content,
          child: content,
        );
      },
    );
  }

  Widget _buildList(List<Memo> items) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无备忘录'));
    }
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) =>
          ref.read(memoRepositoryProvider).reorder(items, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final memo = items[index];
        final selected = memo.id == _selectedId && !_draft;
        if (!widget.retro) {
          return ListTile(
            key: ValueKey(memo.id),
            selected: selected,
            dense: true,
            title: Text(
              memo.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _selectMemo(memo),
          );
        }
        return Material(
          key: ValueKey(memo.id),
          color: selected
              ? WindowsRetroColors.activeBlue
              : WindowsRetroColors.content,
          child: InkWell(
            onTap: () => _selectMemo(memo),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: WindowsRetroColors.grid),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                memo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? WindowsRetroColors.selectedText
                      : WindowsRetroColors.text,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditor(List<Memo> items) {
    if (_selectedId == null && !_draft) {
      return const Center(child: Text('选择或新建一个备忘录'));
    }
    final titleField = TextField(
      controller: _titleController,
      maxLines: 1,
      decoration: InputDecoration(hintText: '标题', errorText: _titleError),
      onChanged: (_) {
        if (_titleError != null) {
          setState(() => _titleError = null);
        }
      },
    );
    final contentField = TextField(
      controller: _contentController,
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        hintText: '记录内容……',
        alignLabelWithHint: true,
      ),
    );
    final deleteButton = widget.retro
        ? RetroPushButton(
            onPressed: () => _delete(items),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline),
                const SizedBox(width: 4),
                Text(_draft ? '放弃' : '删除'),
              ],
            ),
          )
        : OutlinedButton.icon(
            onPressed: () => _delete(items),
            icon: const Icon(Icons.delete_outline),
            label: Text(_draft ? '放弃' : '删除'),
          );
    final saveButton = widget.retro
        ? RetroPushButton(
            onPressed: _save,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.save_outlined),
                SizedBox(width: 4),
                Text('保存'),
              ],
            ),
          )
        : FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleField,
          const SizedBox(height: 8),
          Expanded(child: contentField),
          const SizedBox(height: 8),
          Row(
            children: [
              deleteButton,
              const Spacer(),
              if (_dirty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '未保存',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              saveButton,
            ],
          ),
        ],
      ),
    );
  }
}

class MemoDetailPage extends ConsumerStatefulWidget {
  const MemoDetailPage({this.memoId, super.key});

  final String? memoId;

  @override
  ConsumerState<MemoDetailPage> createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends ConsumerState<MemoDetailPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  String? _loadedVersion;
  String? _titleError;
  bool _dirty = false;
  bool _syncingText = false;
  bool _allowPop = false;

  bool get _isNew => widget.memoId == null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController()..addListener(_markDirty);
    _contentController = TextEditingController()..addListener(_markDirty);
  }

  void _markDirty() {
    if (!_syncingText && !_dirty) {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _load(Memo memo) {
    final version = memo.version ?? memo.updatedAt.toIso8601String();
    if (_dirty || version == _loadedVersion) {
      return;
    }
    _syncingText = true;
    _titleController.text = memo.title;
    _contentController.text = memo.content;
    _syncingText = false;
    _loadedVersion = version;
  }

  Memo? _find(List<Memo> items) {
    for (final memo in items) {
      if (memo.id == widget.memoId) {
        return memo;
      }
    }
    return null;
  }

  Future<bool> _save({bool updateLocation = true}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请输入标题');
      return false;
    }
    late final String id;
    try {
      id = await ref
          .read(memoRepositoryProvider)
          .save(
            id: widget.memoId,
            expectedVersion: _loadedVersion,
            title: title,
            content: _contentController.text,
          );
    } on DiurnaException catch (error) {
      if (mounted) {
        setState(
          () => _titleError = error.code == 'CONFLICT'
              ? '内容已在其他位置修改。草稿已保留，请重新读取后合并。'
              : error.message,
        );
      }
      return false;
    }
    if (!mounted) {
      return true;
    }
    setState(() {
      _dirty = false;
      _titleError = null;
      _loadedVersion = null;
    });
    if (_isNew && updateLocation && mounted) {
      context.go('/memos/$id');
    }
    return true;
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) {
      return true;
    }
    final choice = await _showDirtyDialog(context);
    if (!mounted || choice == null || choice == _DirtyChoice.cancel) {
      return false;
    }
    if (choice == _DirtyChoice.save) {
      return _save(updateLocation: false);
    }
    setState(() => _dirty = false);
    return true;
  }

  Future<void> _handleBack() async {
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _delete(Memo memo) async {
    if (!await _confirmLeave() || !mounted) {
      return;
    }
    if (!await _showDeleteDialog(context, memo.title) || !mounted) {
      return;
    }
    await ref.read(memoRepositoryProvider).delete(memo.id);
    if (mounted) {
      context.go('/memos');
    }
  }

  @override
  Widget build(BuildContext context) {
    final memos = ref.watch(memosProvider);
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _handleBack),
          title: Text(_isNew ? '新建备忘录' : '编辑备忘录'),
          actions: const [SyncStatusIcon()],
        ),
        body: memos.when(
          data: (items) {
            final memo = _isNew ? null : _find(items);
            if (!_isNew && memo == null) {
              return const EmptyView(message: '这个备忘录不存在或已被删除。');
            }
            if (memo != null) {
              _load(memo);
            }
            return _buildForm(memo);
          },
          error: (error, stackTrace) => EmptyView(message: error.toString()),
          loading: () => const LoadingView(),
        ),
      ),
    );
  }

  Widget _buildForm(Memo? memo) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '标题',
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _contentController,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '正文',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (memo != null)
                  OutlinedButton.icon(
                    onPressed: () => _delete(memo),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                const Spacer(),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '未保存',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
