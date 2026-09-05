import '../../../contracts/errors.dart';
import 'package:diurna_core/src/core/database/app_database.dart';
import 'package:diurna_core/src/features/calendar/data/calendar_event_model.dart';
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

  Future<List<CalendarEvent>> list() async =>
      (await _database.listCalendarEvents(_userId))
          .map((r) => CalendarEvent.fromMap(localCalendarEventToRemoteMap(r)))
          .toList();
  Future<CalendarEvent> get(String id) async => CalendarEvent.fromMap(
    await _database.entity(_userId, 'calendar_events', id),
  );

  Future<String> save({
    String? id,
    String? expectedVersion,
    required String title,
    required DateTime scheduledDate,
    bool isCompleted = false,
    String? note,
    DateTime? remindAt,
  }) => _database.transaction(() async {
    title = requiredText(title, 'title');
    if (id != null) {
      await _database.checkVersion(
        _userId,
        'calendar_events',
        id,
        expectedVersion,
      );
    }
    final entityId = id ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.saveCalendarEvent({
      'id': entityId,
      'user_id': _userId,
      'title': title,
      'event_date': _formatDate(scheduledDate),
      'is_completed': isCompleted,
      'note': note,
      'remind_at': remindAt?.toUtc().toIso8601String(),
      'created_at': now,
      'updated_at': now,
    });
    return entityId;
  });

  Future<void> setCompleted(CalendarEvent event, bool completed) =>
      _database.transaction(() async {
        event = await get(event.id);
        await save(
          id: event.id,
          title: event.title,
          scheduledDate: event.scheduledDate,
          isCompleted: completed,
          note: event.note,
          remindAt: event.remindAt,
        );
      });

  Future<void> delete(String id) => _database.transaction(() async {
    await _database.entity(_userId, 'calendar_events', id);
    return _database.deleteCalendarEvent(_userId, id);
  });

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
