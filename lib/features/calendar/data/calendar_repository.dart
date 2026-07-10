import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:uuid/uuid.dart';

class CalendarRepository {
  CalendarRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<CalendarEvent>> watch({bool todayOnly = false}) {
    return _database
        .watchCalendarEvents(_userId, todayOnly: todayOnly)
        .map(
          (rows) => rows
              .map(
                (row) =>
                    CalendarEvent.fromMap(localCalendarEventToRemoteMap(row)),
              )
              .toList(),
        );
  }

  Future<void> save({
    String? id,
    required String title,
    required DateTime scheduledDate,
    bool isCompleted = false,
    String? note,
    DateTime? remindAt,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.saveCalendarEvent({
      'id': id ?? _uuid.v4(),
      'user_id': _userId,
      'title': title,
      'event_date': _formatDate(scheduledDate),
      'is_completed': isCompleted,
      'note': note,
      'remind_at': remindAt?.toUtc().toIso8601String(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> setCompleted(CalendarEvent event, bool completed) {
    return save(
      id: event.id,
      title: event.title,
      scheduledDate: event.scheduledDate,
      isCompleted: completed,
      note: event.note,
      remindAt: event.remindAt,
    );
  }

  Future<void> delete(String id) {
    return _database.deleteCalendarEvent(_userId, id);
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
