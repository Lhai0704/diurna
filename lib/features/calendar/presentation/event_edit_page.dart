import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:diurna/features/calendar/providers/calendar_providers.dart';
import 'package:diurna/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showEventEditPage(
  BuildContext context, {
  CalendarEvent? event,
  DateTime? initialDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EventEditPage(event: event, initialDate: initialDate),
  );
}

class EventEditPage extends ConsumerStatefulWidget {
  const EventEditPage({this.event, this.initialDate, super.key});

  final CalendarEvent? event;
  final DateTime? initialDate;

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _dateController;
  late final TextEditingController _noteController;
  late final TextEditingController _remindAtController;
  late bool _isCompleted;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final initialDate =
        event?.scheduledDate ?? widget.initialDate ?? DateTime.now();
    _titleController = TextEditingController(text: event?.title ?? '');
    _dateController = TextEditingController(
      text: AppDateUtils.formatDate(initialDate),
    );
    _noteController = TextEditingController(text: event?.note ?? '');
    _remindAtController = TextEditingController(
      text: event?.remindAt == null
          ? ''
          : AppDateUtils.formatDateTime(event!.remindAt!),
    );
    _isCompleted = event?.isCompleted ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _noteController.dispose();
    _remindAtController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial =
        AppDateUtils.parseNullable(_dateController.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (date != null) {
      _dateController.text = AppDateUtils.formatDate(date);
    }
  }

  Future<void> _pickReminder() async {
    final initial =
        AppDateUtils.parseNullable(_remindAtController.text) ??
        AppDateUtils.parseNullable(_dateController.text) ??
        DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return;
    }
    _remindAtController.text = AppDateUtils.formatDateTime(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref
          .read(calendarRepositoryProvider)
          .save(
            id: widget.event?.id,
            title: _titleController.text.trim(),
            scheduledDate: AppDateUtils.parseNullable(_dateController.text)!,
            isCompleted: _isCompleted,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            remindAt: AppDateUtils.parseNullable(_remindAtController.text),
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _delete() async {
    final event = widget.event;
    if (event == null || _isSaving) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除待办？'),
        content: Text('“${event.title}”删除后无法恢复。'),
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
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _isSaving = true);
    await ref.read(calendarRepositoryProvider).delete(event.id);
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
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.event == null ? '新建日程待办' : '编辑日程待办',
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
                _PickerField(
                  controller: _dateController,
                  label: '日期',
                  icon: Icons.calendar_today_outlined,
                  onPick: _pickDate,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _noteController,
                  label: '备注',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _PickerField(
                  controller: _remindAtController,
                  label: '提醒时间',
                  icon: Icons.schedule_outlined,
                  required: false,
                  onPick: _pickReminder,
                ),
                if (widget.event != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('已完成'),
                    value: _isCompleted,
                    onChanged: _isSaving
                        ? null
                        : (value) =>
                              setState(() => _isCompleted = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? '处理中…' : '保存'),
                ),
                if (widget.event != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除待办'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onPick,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onPick;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      validator: (value) {
        if (!required && (value == null || value.trim().isEmpty)) {
          return null;
        }
        return AppDateUtils.parseNullable(value ?? '') == null
            ? '请选择$label'
            : null;
      },
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: '选择$label',
          onPressed: onPick,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
