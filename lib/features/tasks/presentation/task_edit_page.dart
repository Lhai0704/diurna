import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:diurna/features/tasks/providers/task_providers.dart';
import 'package:diurna/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showTaskEditPage(BuildContext context, {Task? task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TaskEditPage(task: task),
  );
}

class TaskEditPage extends ConsumerStatefulWidget {
  const TaskEditPage({this.task, super.key});

  final Task? task;

  @override
  ConsumerState<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends ConsumerState<TaskEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _dueDateController;
  late int _priority;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _noteController = TextEditingController(text: task?.note ?? '');
    _dueDateController = TextEditingController(
      text: task?.dueDate == null ? '' : AppDateUtils.formatDate(task!.dueDate!),
    );
    _priority = task?.priority ?? 2;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: widget.task?.dueDate ?? DateTime.now(),
    );
    if (picked != null) {
      _dueDateController.text = AppDateUtils.formatDate(picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref.read(taskRepositoryProvider).save(
          id: widget.task?.id,
          title: _titleController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          dueDate: AppDateUtils.parseNullable(_dueDateController.text),
          priority: _priority,
          isCompleted: widget.task?.isCompleted ?? false,
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.task == null ? '新建待办' : '编辑待办',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _titleController,
                label: '标题',
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入标题' : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _noteController,
                label: '备注',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dueDateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '截止日期',
                  suffixIcon: IconButton(
                    tooltip: '选择日期',
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.calendar_today_outlined),
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
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
