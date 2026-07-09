import 'package:diurna/features/calendar/data/calendar_event_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CalendarRepository {
  CalendarRepository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  String get _userId => _client.auth.currentUser!.id;

  Future<List<CalendarEvent>> list({bool todayOnly = false}) async {
    var query = _client.from('calendar_events').select();

    if (todayOnly) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('starts_at', start.toUtc().toIso8601String())
          .lt('starts_at', end.toUtc().toIso8601String());
    }

    final rows = await query.order('starts_at');
    return rows.map((row) => CalendarEvent.fromMap(row)).toList();
  }

  Future<void> save({
    String? id,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? note,
    DateTime? remindAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('calendar_events').upsert({
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

  Future<void> delete(String id) async {
    await _client.from('calendar_events').delete().eq('id', id);
  }
}
