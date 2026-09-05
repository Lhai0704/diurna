import '../../../contracts/errors.dart';
import 'package:diurna_core/src/core/database/app_database.dart';
import 'package:diurna_core/src/features/diary/data/diary_model.dart';
import 'package:uuid/uuid.dart';

class DiaryRepository {
  DiaryRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<DiaryEntry>> watch() {
    return _database
        .watchDiaryEntries(_userId)
        .map(
          (rows) => rows
              .map((row) => DiaryEntry.fromMap(localDiaryEntryToRemoteMap(row)))
              .toList(),
        );
  }

  Future<List<DiaryEntry>> list() async => (await _database.listDiaryEntries(
    _userId,
  )).map((r) => DiaryEntry.fromMap(localDiaryEntryToRemoteMap(r))).toList();
  Future<DiaryEntry> get(String id) async =>
      DiaryEntry.fromMap(await _database.entity(_userId, 'diary_entries', id));

  Future<String> save({
    String? id,
    String? expectedVersion,
    required DateTime entryDate,
    required String title,
    required String content,
    String? mood,
    required List<String> tags,
  }) => _database.transaction(() async {
    title = requiredText(title, 'title');
    requiredText(content, 'content');
    if (id != null) {
      await _database.checkVersion(
        _userId,
        'diary_entries',
        id,
        expectedVersion,
      );
    }
    final entityId = id ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.saveDiaryEntry({
      'id': entityId,
      'user_id': _userId,
      'entry_date': entryDate.toIso8601String().split('T').first,
      'title': title,
      'content': content,
      'mood': mood,
      'tags': tags,
      'created_at': now,
      'updated_at': now,
    });
    return entityId;
  });

  Future<void> delete(String id) => _database.transaction(() async {
    await _database.entity(_userId, 'diary_entries', id);
    return _database.deleteDiaryEntry(_userId, id);
  });
}
