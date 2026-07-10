import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:diurna/features/diary/data/diary_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final diaryRepositoryProvider = Provider<DiaryRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('请先登录。');
  }
  return DiaryRepository(ref.watch(appDatabaseProvider), userId);
});

final diaryEntriesProvider = StreamProvider.autoDispose<List<DiaryEntry>>((
  ref,
) {
  return ref.watch(diaryRepositoryProvider).watch();
});
