import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:diurna/features/tasks/data/task_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(supabaseClientProvider));
});

final tasksProvider = FutureProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).list();
});
