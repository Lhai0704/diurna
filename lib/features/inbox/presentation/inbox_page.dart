import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/inbox/presentation/inbox_board.dart';
import 'package:diurna/shared/widgets/sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InboxPage extends ConsumerWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: InboxBoard(
          expanded: true,
          headerAction: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SyncStatusIcon(),
              IconButton(
                tooltip: '退出登录',
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showExpandedInbox(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: InboxBoard(
        expanded: true,
        headerAction: IconButton(
          tooltip: '关闭展开模式',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_fullscreen),
        ),
      ),
    ),
  );
}
