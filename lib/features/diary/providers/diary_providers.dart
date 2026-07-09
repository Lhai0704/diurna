import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:diurna/features/diary/data/diary_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final diaryRepositoryProvider = Provider<DiaryRepository>((ref) {
  return DiaryRepository(ref.watch(supabaseClientProvider));
});

final diaryEntriesProvider = FutureProvider.autoDispose<List<DiaryEntry>>((ref) {
  return ref.watch(diaryRepositoryProvider).list();
});
