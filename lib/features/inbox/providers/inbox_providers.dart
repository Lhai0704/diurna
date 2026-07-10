import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:diurna/features/inbox/data/inbox_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('请先登录。');
  }
  return InboxRepository(ref.watch(appDatabaseProvider), userId);
});

final inboxItemsProvider = StreamProvider.autoDispose<List<InboxItem>>((ref) {
  return ref.watch(inboxRepositoryProvider).watch();
});
