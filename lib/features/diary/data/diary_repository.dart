import 'package:diurna/features/diary/data/diary_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DiaryRepository {
  DiaryRepository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  String get _userId => _client.auth.currentUser!.id;

  Future<List<DiaryEntry>> list() async {
    final rows = await _client
        .from('diary_entries')
        .select()
        .order('entry_date', ascending: false)
        .order('created_at', ascending: false);

    return rows.map((row) => DiaryEntry.fromMap(row)).toList();
  }

  Future<void> save({
    String? id,
    required DateTime entryDate,
    required String title,
    required String content,
    String? mood,
    required List<String> tags,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('diary_entries').upsert({
      'id': id ?? _uuid.v4(),
      'user_id': _userId,
      'entry_date': entryDate.toIso8601String().split('T').first,
      'title': title,
      'content': content,
      'mood': mood,
      'tags': tags,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> delete(String id) async {
    await _client.from('diary_entries').delete().eq('id', id);
  }
}
