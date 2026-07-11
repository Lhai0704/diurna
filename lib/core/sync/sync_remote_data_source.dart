import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SyncRemoteDataSource {
  Future<void> upsert(String table, Map<String, dynamic> payload);

  Future<void> delete(String table, String id);

  Future<RemoteSnapshot> fetchSnapshot();
}

class RemoteSnapshot {
  const RemoteSnapshot({
    required this.inboxItems,
    required this.diaryEntries,
    required this.calendarEvents,
  });

  final List<Map<String, dynamic>> inboxItems;
  final List<Map<String, dynamic>> diaryEntries;
  final List<Map<String, dynamic>> calendarEvents;
}

class SupabaseSyncRemoteDataSource implements SyncRemoteDataSource {
  SupabaseSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, Map<String, dynamic> payload) async {
    await _client.from(table).upsert(payload);
  }

  @override
  Future<void> delete(String table, String id) async {
    await _client.from(table).delete().eq('id', id);
  }

  @override
  Future<RemoteSnapshot> fetchSnapshot() async {
    final results = await Future.wait([
      _client.from('inbox_items').select(),
      _client.from('diary_entries').select(),
      _client.from('calendar_events').select(),
    ]);
    return RemoteSnapshot(
      inboxItems: _rows(results[0]),
      diaryEntries: _rows(results[1]),
      calendarEvents: _rows(results[2]),
    );
  }

  List<Map<String, dynamic>> _rows(List<Map<String, dynamic>> rows) {
    return rows.map(Map<String, dynamic>.from).toList();
  }
}
