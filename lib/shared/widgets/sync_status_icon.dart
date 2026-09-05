import 'package:diurna/app/windows_retro_theme.dart';
import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'sync_conflicts_page.dart';

class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({this.retro = false, super.key});

  final bool retro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(syncServiceProvider);
    final asyncSnapshot = ref.watch(syncSnapshotProvider);
    final snapshot = asyncSnapshot.value ?? const SyncSnapshot.idle();
    final colors = Theme.of(context).colorScheme;

    Widget icon;
    if (snapshot.conflictCount > 0) {
      icon = Icon(Icons.sync_problem, color: colors.error, size: 21);
    } else if (snapshot.phase == SyncPhase.syncing) {
      icon = const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (snapshot.phase == SyncPhase.failed) {
      icon = Icon(Icons.cloud_off_outlined, color: colors.error, size: 21);
    } else if (snapshot.pendingCount > 0) {
      icon = Icon(
        Icons.cloud_upload_outlined,
        color: colors.tertiary,
        size: 21,
      );
    } else {
      icon = Icon(
        Icons.cloud_done_outlined,
        color: colors.onSurfaceVariant,
        size: 21,
      );
    }

    final tooltip = _tooltip(snapshot);
    void pressed() {
      if (snapshot.conflictCount > 0) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SyncConflictsPage()),
        );
      } else {
        service?.syncNow();
      }
    }

    if (retro) {
      return RetroToolbarButton(
        tooltip: tooltip,
        onPressed: service == null ? null : pressed,
        icon: icon,
      );
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: service == null ? null : pressed,
      icon: icon,
    );
  }

  String _tooltip(SyncSnapshot snapshot) {
    if (snapshot.conflictCount > 0) {
      return '${snapshot.conflictCount} 组同步冲突，点击查看';
    }
    if (snapshot.phase == SyncPhase.syncing) {
      return snapshot.pendingCount > 0
          ? '正在同步（${snapshot.pendingCount} 项待处理）'
          : '正在同步';
    }
    if (snapshot.phase == SyncPhase.failed) {
      return '同步失败，点击重试${snapshot.pendingCount > 0 ? '（${snapshot.pendingCount} 项待处理）' : ''}';
    }
    if (snapshot.pendingCount > 0) {
      return '${snapshot.pendingCount} 项等待同步，点击立即同步';
    }
    final lastSyncedAt = snapshot.lastSyncedAt;
    if (lastSyncedAt == null) {
      return '已同步';
    }
    return '已同步 · ${DateFormat('HH:mm').format(lastSyncedAt)}';
  }
}
