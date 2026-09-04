import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/features/memo/data/memo_model.dart';
import 'package:uuid/uuid.dart';

class MemoRepository {
  MemoRepository(this._database, this._userId);

  final AppDatabase _database;
  final String _userId;
  static const _uuid = Uuid();

  Stream<List<Memo>> watch() {
    return _database
        .watchMemos(_userId)
        .map(
          (rows) => rows
              .map((row) => Memo.fromMap(localMemoToRemoteMap(row)))
              .toList(),
        );
  }

  Future<List<Memo>> list() async {
    final rows = await _database.listMemos(_userId);
    return rows.map((row) => Memo.fromMap(localMemoToRemoteMap(row))).toList();
  }

  Future<String> save({
    String? id,
    required String title,
    required String content,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '标题不能为空');
    }

    final items = await list();
    Memo? existing;
    if (id != null) {
      for (final item in items) {
        if (item.id == id) {
          existing = item;
          break;
        }
      }
    }
    final memoId = existing?.id ?? id ?? _uuid.v4();
    final firstPosition = items.isEmpty ? 0.0 : items.first.position;
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.saveMemo({
      'id': memoId,
      'user_id': _userId,
      'title': normalizedTitle,
      'content': content,
      'position': existing?.position ?? firstPosition - 1,
      'created_at': existing?.createdAt.toUtc().toIso8601String() ?? now,
      'updated_at': now,
    });
    return memoId;
  }

  Future<void> reorder(List<Memo> items, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= items.length) {
      return;
    }
    final reordered = List<Memo>.of(items);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex.clamp(0, reordered.length), item);
    await _database.updateMemos(_userId, [
      for (var index = 0; index < reordered.length; index++)
        MemoMutation(reordered[index].id, {'position': index.toDouble()}),
    ]);
  }

  Future<void> delete(String id) {
    return _database.deleteMemo(_userId, id);
  }
}
