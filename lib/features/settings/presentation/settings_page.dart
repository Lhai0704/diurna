import 'package:diurna/app/visual_style.dart';
import 'package:diurna/features/settings/providers/visual_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(visualStyleProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '复古和现代使用同一套四宫格桌面；Web 风格使用分页导航。',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<AppVisualStyle>(
                    groupValue: style,
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(visualStyleProvider.notifier).setStyle(value);
                      }
                    },
                    child: Column(
                      children: [
                        for (final option in AppVisualStyle.values)
                          RadioListTile<AppVisualStyle>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(option.label),
                            subtitle: Text(option.description),
                            value: option,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: const Text('外部连接'),
              subtitle: const Text('Notion、Google Calendar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/integrations'),
            ),
          ),
        ],
      ),
    );
  }
}
