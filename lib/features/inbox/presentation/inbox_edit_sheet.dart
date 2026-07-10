import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:diurna/features/inbox/providers/inbox_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

Future<void> showQuickCapture(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _QuickCaptureDialog(),
  );
}

Future<void> showInboxEditSheet(
  BuildContext context, {
  required InboxItem item,
  bool convertToAction = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) =>
        InboxEditSheet(item: item, convertToAction: convertToAction),
  );
}

class _QuickCaptureDialog extends ConsumerStatefulWidget {
  const _QuickCaptureDialog();

  @override
  ConsumerState<_QuickCaptureDialog> createState() =>
      _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends ConsumerState<_QuickCaptureDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    await ref.read(inboxRepositoryProvider).createQuick(content);
    ref.invalidate(inboxItemsProvider);
    _controller.clear();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop();
        },
      },
      child: AlertDialog(
        title: const Text('快速记录'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            minLines: 3,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '记录刚刚想到的内容……',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

class InboxEditSheet extends ConsumerStatefulWidget {
  const InboxEditSheet({
    required this.item,
    this.convertToAction = false,
    super.key,
  });

  final InboxItem item;
  final bool convertToAction;

  @override
  ConsumerState<InboxEditSheet> createState() => _InboxEditSheetState();
}

class _InboxEditSheetState extends ConsumerState<InboxEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contentController;
  late final TextEditingController _dueDateController;
  late InboxItemType? _type;
  late int _priority;
  late bool _completed;
  late bool _isTopic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _contentController = TextEditingController(text: item.content);
    _dueDateController = TextEditingController(
      text: item.dueDate == null ? '' : AppDateUtils.formatDate(item.dueDate!),
    );
    _type = widget.convertToAction ? InboxItemType.action : item.type;
    _priority = item.priority ?? 2;
    _completed = item.isCompleted;
    _isTopic = widget.convertToAction ? false : item.isTopic;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate:
          AppDateUtils.parseNullable(_dueDateController.text) ?? DateTime.now(),
    );
    if (picked != null) {
      _dueDateController.text = AppDateUtils.formatDate(picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) {
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(inboxRepositoryProvider)
        .save(
          item: widget.item,
          content: _contentController.text.trim(),
          type: _type,
          isTopic: _isTopic,
          dueDate: AppDateUtils.parseNullable(_dueDateController.text),
          priority: _priority,
          isCompleted: _completed,
        );
    ref.invalidate(inboxItemsProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _type == InboxItemType.action && !_isTopic;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('编辑收集内容', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入内容' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type?.databaseValue ?? 'none',
                decoration: const InputDecoration(labelText: '类型（可选）'),
                items: [
                  const DropdownMenuItem(value: 'none', child: Text('无类型')),
                  for (final type in InboxItemType.values)
                    DropdownMenuItem(
                      value: type.databaseValue,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _type = value == 'none'
                      ? null
                      : InboxItemTypeX.fromDatabase(value);
                  if (_type != InboxItemType.research) {
                    _isTopic = false;
                  }
                }),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设为研究主题'),
                subtitle: const Text('主题可包含一层相关内容'),
                value: _isTopic,
                onChanged: (value) => setState(() {
                  _isTopic = value ?? false;
                  if (_isTopic) {
                    _type = InboxItemType.research;
                  }
                }),
              ),
              if (action) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dueDateController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: '截止日期（可选）',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dueDateController.text.isNotEmpty)
                          IconButton(
                            tooltip: '清除日期',
                            onPressed: () => setState(_dueDateController.clear),
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          tooltip: '选择日期',
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: '优先级'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 高')),
                    DropdownMenuItem(value: 2, child: Text('2 中')),
                    DropdownMenuItem(value: 3, child: Text('3 低')),
                  ],
                  onChanged: (value) => setState(() => _priority = value ?? 2),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('已完成'),
                  value: _completed,
                  onChanged: (value) =>
                      setState(() => _completed = value ?? false),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
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
