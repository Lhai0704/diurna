import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/memo/data/memo_model.dart';
import 'package:diurna/features/memo/data/memo_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final memoRepositoryProvider = Provider<MemoRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('请先登录。');
  }
  return MemoRepository(ref.watch(appDatabaseProvider), userId);
});

final memosProvider = StreamProvider.autoDispose<List<Memo>>((ref) {
  return ref.watch(memoRepositoryProvider).watch();
});
