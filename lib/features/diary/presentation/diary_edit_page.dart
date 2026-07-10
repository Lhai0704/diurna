import 'package:diurna/core/utils/app_date_utils.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:diurna/features/diary/providers/diary_providers.dart';
import 'package:diurna/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showDiaryEditPage(BuildContext context, {DiaryEntry? entry}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DiaryEditPage(entry: entry),
  );
}

class DiaryEditPage extends ConsumerStatefulWidget {
  const DiaryEditPage({this.entry, super.key});

  final DiaryEntry? entry;

  @override
  ConsumerState<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends ConsumerState<DiaryEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dateController;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _moodController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _dateController = TextEditingController(
      text: AppDateUtils.formatDate(entry?.entryDate ?? DateTime.now()),
    );
    _titleController = TextEditingController(text: entry?.title ?? '');
    _contentController = TextEditingController(text: entry?.content ?? '');
    _moodController = TextEditingController(text: entry?.mood ?? '');
    _tagsController = TextEditingController(text: entry?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    _dateController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _moodController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: AppDateUtils.parseNullable(_dateController.text) ?? DateTime.now(),
    );
    if (picked != null) {
      _dateController.text = AppDateUtils.formatDate(picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    await ref.read(diaryRepositoryProvider).save(
          id: widget.entry?.id,
          entryDate: AppDateUtils.parseNullable(_dateController.text)!,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          mood: _moodController.text.trim().isEmpty
              ? null
              : _moodController.text.trim(),
          tags: tags,
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
                  widget.entry == null ? '新建日记' : '编辑日记',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  validator: (value) =>
                      AppDateUtils.parseNullable(value ?? '') == null ? '请选择日期' : null,
                  decoration: InputDecoration(
                    labelText: '日期',
                    suffixIcon: IconButton(
                      tooltip: '选择日期',
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _titleController,
                  label: '标题',
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入标题' : null,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _contentController,
                  label: '正文',
                  maxLines: 8,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入正文' : null,
                ),
                const SizedBox(height: 12),
                AppTextField(controller: _moodController, label: '心情'),
                const SizedBox(height: 12),
                AppTextField(controller: _tagsController, label: '标签，逗号分隔'),
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
