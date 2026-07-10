import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(syncServiceProvider);
    final asyncSnapshot = ref.watch(syncSnapshotProvider);
    final snapshot = asyncSnapshot.value ?? const SyncSnapshot.idle();
    final colors = Theme.of(context).colorScheme;

    Widget icon;
    if (snapshot.phase == SyncPhase.syncing) {
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

    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: _tooltip(snapshot),
      onPressed: service?.syncNow,
      icon: icon,
    );
  }

  String _tooltip(SyncSnapshot snapshot) {
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
