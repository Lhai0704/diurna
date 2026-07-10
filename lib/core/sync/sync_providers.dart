import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/core/sync/sync_remote_data_source.dart';
import 'package:diurna/core/sync/sync_service.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncServiceProvider = Provider<SyncService?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return null;
  }

  final service = SyncService(
    database: ref.watch(appDatabaseProvider),
    remote: SupabaseSyncRemoteDataSource(ref.watch(supabaseClientProvider)),
    userId: userId,
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

final syncSnapshotProvider = StreamProvider<SyncSnapshot>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service?.snapshots ?? Stream.value(const SyncSnapshot.idle());
});

Future<void> triggerSync(WidgetRef ref) async {
  final service = ref.read(syncServiceProvider);
  if (service != null) {
    await service.syncNow();
  }
}
