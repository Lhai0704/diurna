import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class TaskRepository {
  TaskRepository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  String get _userId => _client.auth.currentUser!.id;

  Future<List<Task>> list() async {
    final rows = await _client
        .from('tasks')
        .select()
        .order('is_completed')
        .order('due_date', nullsFirst: false)
        .order('created_at', ascending: false);

    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<void> save({
    String? id,
    required String title,
    String? note,
    DateTime? dueDate,
    required int priority,
    bool isCompleted = false,
  }) async {
    final now = DateTime.now().toUtc();
    await _client.from('tasks').upsert({
      'id': id ?? _uuid.v4(),
      'user_id': _userId,
      'title': title,
      'note': note,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'is_completed': isCompleted,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<void> setCompleted(Task task, bool completed) async {
    await _client.from('tasks').update({
      'is_completed': completed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', task.id);
  }

  Future<void> delete(String id) async {
    await _client.from('tasks').delete().eq('id', id);
  }
}
