import 'dart:convert';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncConflictsPage extends ConsumerStatefulWidget {
  const SyncConflictsPage({super.key});
  @override
  ConsumerState<SyncConflictsPage> createState() => _SyncConflictsPageState();
}

class _SyncConflictsPageState extends ConsumerState<SyncConflictsPage> {
  bool _busy = false;
  String? _error;

  Future<void> _resolve(String id, bool local) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local ? '提交保留的本地修改？' : '采用远端内容？'),
        content: Text(
          local ? '将按最新远端版本重新提交；再次变化会重新产生冲突。' : '此操作会放弃这一组待同步的本地修改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncServiceProvider)?.resolveConflict(id, useLocal: local);
    } catch (error) {
      if (mounted) setState(() => _error = '无法处理冲突：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncSnapshotProvider);
    final service = ref.watch(syncServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('同步冲突')),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_error!),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: service?.conflicts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('无法读取冲突。请重试。'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) return const Center(child: Text('没有待处理冲突'));
                return ListView(
                  children: [
                    for (final row in rows)
                      Card(
                        margin: const EdgeInsets.all(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['entityType']} · ${row['id']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              const Text('保留的本地操作'),
                              SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(row['changes']),
                              ),
                              const SizedBox(height: 8),
                              const Text('检测到的远端内容'),
                              SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(row['remote']),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _resolve(
                                            row['id'] as String,
                                            false,
                                          ),
                                    child: const Text('采用远端内容'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _resolve(
                                            row['id'] as String,
                                            true,
                                          ),
                                    child: const Text('提交本地修改'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
