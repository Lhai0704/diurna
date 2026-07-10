import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/inbox/data/inbox_item.dart';
import 'package:diurna/features/inbox/data/inbox_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepository(ref.watch(supabaseClientProvider));
});

final inboxItemsProvider = FutureProvider.autoDispose<List<InboxItem>>((ref) {
  return ref.watch(inboxRepositoryProvider).list();
});
