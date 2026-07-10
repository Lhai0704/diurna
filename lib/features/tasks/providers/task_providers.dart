import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/core/database/database_providers.dart';
import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:diurna/features/tasks/data/task_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('请先登录。');
  }
  return TaskRepository(ref.watch(appDatabaseProvider), userId);
});

final tasksProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watch();
});
