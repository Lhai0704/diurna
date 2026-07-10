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
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? note,
    DateTime? remindAt,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.saveCalendarEvent({
      'id': id ?? _uuid.v4(),
      'user_id': _userId,
      'title': title,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'location': location,
      'note': note,
      'remind_at': remindAt?.toUtc().toIso8601String(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> delete(String id) {
    return _database.deleteCalendarEvent(_userId, id);
  }
}
