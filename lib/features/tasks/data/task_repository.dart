import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/tasks/data/task_model.dart';
import 'package:uuid/uuid.dart';

class TaskRepository {
  TaskRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<Task>> watch() {
    return _database
        .watchTasks(_userId)
        .map(
          (rows) => rows
              .where((row) => row.itemType == 'action' && !row.isArchived)
              .map((row) => Task.fromMap(localTaskToRemoteMap(row)))
              .toList(),
        );
  }

  Future<void> save({
    String? id,
    required String title,
    String? note,
    DateTime? dueDate,
    required int priority,
    bool isCompleted = false,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.saveTask({
      'id': id ?? _uuid.v4(),
      'user_id': _userId,
      'title': title,
      'note': note,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'priority': priority,
      'is_completed': isCompleted,
      'item_type': 'action',
      'inbox_column': 'pending',
      'sort_order': 0.0,
      'is_archived': false,
      'is_pinned': false,
      'is_topic': false,
      'parent_id': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> setCompleted(Task task, bool completed) {
    return _database.updateTasks(_userId, [
      TaskMutation(task.id, {'is_completed': completed}),
    ]);
  }

  Future<void> delete(String id) {
    return _database.deleteTask(_userId, id);
  }
}
