import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/diary/data/diary_model.dart';
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

  Future<void> save({
    String? id,
    required DateTime entryDate,
    required String title,
    required String content,
    String? mood,
    required List<String> tags,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.saveDiaryEntry({
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

  Future<void> delete(String id) {
    return _database.deleteDiaryEntry(_userId, id);
  }
}
