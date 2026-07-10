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
  late final TextEditingController _startsAtController;
  late final TextEditingController _endsAtController;
  late final TextEditingController _locationController;
  late final TextEditingController _noteController;
  late final TextEditingController _remindAtController;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    final event = widget.event;
    _titleController = TextEditingController(text: event?.title ?? '');
    _startsAtController = TextEditingController(
      text: AppDateUtils.formatDateTime(event?.startsAt ?? now),
    );
    _endsAtController = TextEditingController(
      text: AppDateUtils.formatDateTime(
        event?.endsAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    _locationController = TextEditingController(text: event?.location ?? '');
    _noteController = TextEditingController(text: event?.note ?? '');
    _remindAtController = TextEditingController(
      text: event?.remindAt == null
          ? ''
          : AppDateUtils.formatDateTime(event!.remindAt!),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _startsAtController.dispose();
    _endsAtController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    _remindAtController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final initial =
        AppDateUtils.parseNullable(controller.text) ?? DateTime.now();
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
    controller.text = AppDateUtils.formatDateTime(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final startsAt = AppDateUtils.parseNullable(_startsAtController.text)!;
    final endsAt = AppDateUtils.parseNullable(_endsAtController.text)!;
    if (!endsAt.isAfter(startsAt)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间。')));
      return;
    }

    await ref
        .read(calendarRepositoryProvider)
        .save(
          id: widget.event?.id,
          title: _titleController.text.trim(),
          startsAt: startsAt,
          endsAt: endsAt,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          remindAt: AppDateUtils.parseNullable(_remindAtController.text),
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
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.event == null ? '新建日程' : '编辑日程',
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
                _DateTimeField(
                  controller: _startsAtController,
                  label: '开始时间',
                  onPick: () => _pickDateTime(_startsAtController),
                ),
                const SizedBox(height: 12),
                _DateTimeField(
                  controller: _endsAtController,
                  label: '结束时间',
                  onPick: () => _pickDateTime(_endsAtController),
                ),
                const SizedBox(height: 12),
                AppTextField(controller: _locationController, label: '地点'),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _noteController,
                  label: '备注',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _DateTimeField(
                  controller: _remindAtController,
                  label: '提醒时间',
                  required: false,
                  onPick: () => _pickDateTime(_remindAtController),
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
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.controller,
    required this.label,
    required this.onPick,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
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
          tooltip: '选择时间',
          onPressed: onPick,
          icon: const Icon(Icons.schedule_outlined),
        ),
      ),
    );
  }
}
