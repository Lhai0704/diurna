import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../../contracts/errors.dart';

class SyncAttempt {
  SyncAttempt(this.id, this.entityType, this.changes);
  final String id, entityType;
  final List<Map<String, dynamic>> changes;
}

class VersionedSyncStore {
  VersionedSyncStore(this.db, this.userId);
  final AppDatabase db;
  final String userId;

  Future<List<SyncAttempt>> attempts() => db.transaction(() async {
    final frozen = await db
        .customSelect(
          'SELECT * FROM sync_attempts WHERE user_id=?',
          variables: [Variable(userId)],
        )
        .get();
    final result = frozen
        .map(
          (r) => SyncAttempt(
            r.read<String>('id'),
            r.read<String>('entity_type'),
            (jsonDecode(r.read<String>('payload')) as List)
                .cast<Map<String, dynamic>>(),
          ),
        )
        .toList();
    final protected = <String>{
      for (final a in result)
        for (final c in a.changes) '${a.entityType}:${c['id']}',
    };
    final conflicts = await listConflicts();
    for (final conflict in conflicts) {
      for (final c in conflict['changes'] as List) {
        protected.add('${conflict['entityType']}:${c['id']}');
      }
    }
    final pending = await db.pendingOperations(userId);
    final blockedGroups = {
      for (final op in pending)
        if (protected.contains('${op.entityType}:${op.entityId}'))
          '${op.entityType}:${op.groupId}',
    };
    final groups = <String, List<PendingSyncOperation>>{};
    for (final op in pending) {
      if (blockedGroups.contains('${op.entityType}:${op.groupId}')) continue;
      groups.putIfAbsent('${op.entityType}:${op.groupId}', () => []).add(op);
    }
    for (final group in groups.values) {
      final changes = <Map<String, dynamic>>[];
      for (final op in group) {
        final meta = await db
            .customSelect(
              'SELECT revision FROM sync_metadata WHERE user_id=? AND entity_type=? AND entity_id=?',
              variables: [
                Variable(userId),
                Variable(op.entityType),
                Variable(op.entityId),
              ],
            )
            .getSingleOrNull();
        changes.add({
          'id': op.entityId,
          'operation': op.operation,
          'payload': op.payloadJson == null
              ? null
              : jsonDecode(op.payloadJson!),
          'expected_revision':
              meta?.read<int>('revision') ??
              (op.generation == 'legacy' ? -1 : 0),
          'generation': op.generation,
        });
      }
      final attempt = SyncAttempt(
        const Uuid().v4(),
        group.first.entityType,
        changes,
      );
      await db.customStatement('INSERT INTO sync_attempts VALUES (?,?,?,?)', [
        attempt.id,
        userId,
        attempt.entityType,
        jsonEncode(changes),
      ]);
      result.add(attempt);
    }
    return result;
  });

  Future<void> acknowledge(
    SyncAttempt attempt,
    List<Map<String, dynamic>> revisions,
  ) => db.transaction(() async {
    for (final change in attempt.changes) {
      final revision =
          revisions.singleWhere((r) => r['id'] == change['id'])['revision']
              as int;
      await db.customStatement(
        'INSERT INTO sync_metadata VALUES (?,?,?,?,?) ON CONFLICT(user_id,entity_type,entity_id) DO UPDATE SET revision=excluded.revision,remote_json=excluded.remote_json',
        [
          userId,
          attempt.entityType,
          change['id'],
          revision,
          jsonEncode(change['payload']),
        ],
      );
      await (db.delete(db.pendingSyncOperations)..where(
            (t) =>
                t.key.equals('$userId:${attempt.entityType}:${change['id']}') &
                t.generation.equals(change['generation'] as String),
          ))
          .go();
    }
    await db.customStatement(
      'DELETE FROM sync_attempts WHERE id=? AND user_id=?',
      [attempt.id, userId],
    );
  });

  Future<void> conflict(SyncAttempt attempt, Object remote) =>
      db.transaction(() async {
        await db.customStatement(
          'INSERT OR REPLACE INTO sync_conflicts VALUES (?,?,?,?,?)',
          [
            attempt.id,
            userId,
            attempt.entityType,
            jsonEncode(attempt.changes),
            jsonEncode(remote),
          ],
        );
        await db.customStatement(
          'DELETE FROM sync_attempts WHERE id=? AND user_id=?',
          [attempt.id, userId],
        );
      });

  Future<List<Map<String, dynamic>>> listConflicts() async {
    final result =
        (await db
                .customSelect(
                  'SELECT * FROM sync_conflicts WHERE user_id=?',
                  variables: [Variable(userId)],
                )
                .get())
            .map(
              (r) => {
                'id': r.read<String>('id'),
                'entityType': r.read<String>('entity_type'),
                'changes': jsonDecode(r.read<String>('payload')),
                'remote': jsonDecode(r.read<String>('remote_json')),
              },
            )
            .toList();
    final pending = await db.pendingOperations(userId);
    for (final conflict in result) {
      final original = (conflict['changes'] as List)
          .cast<Map<String, dynamic>>();
      final ids = original.map((c) => c['id']).toSet();
      final groups = pending
          .where(
            (p) =>
                p.entityType == conflict['entityType'] &&
                ids.contains(p.entityId),
          )
          .map((p) => p.groupId)
          .toSet();
      final current = pending.where(
        (p) =>
            p.entityType == conflict['entityType'] &&
            groups.contains(p.groupId),
      );
      if (current.isNotEmpty) {
        conflict['changes'] = [
          for (final p in current)
            {
              'id': p.entityId,
              'operation': p.operation,
              'payload': p.payloadJson == null
                  ? null
                  : jsonDecode(p.payloadJson!),
              'generation': p.generation,
              'expected_revision':
                  original
                      .where((c) => c['id'] == p.entityId)
                      .firstOrNull?['expected_revision'] ??
                  -1,
            },
        ];
      }
    }
    return result;
  }

  Future<void> applyMetadata(
    Map<String, List<Map<String, dynamic>>> tables,
  ) async {
    final pending = await db.pendingOperations(userId);
    final keys = {for (final p in pending) '${p.entityType}:${p.entityId}'};
    for (final table in tables.entries) {
      for (final row in table.value) {
        if (keys.contains('${table.key}:${row['id']}')) continue;
        await db.customStatement(
          'INSERT INTO sync_metadata VALUES (?,?,?,?,?) ON CONFLICT(user_id,entity_type,entity_id) DO UPDATE SET revision=excluded.revision,remote_json=excluded.remote_json',
          [userId, table.key, row['id'], row['revision'] ?? 0, jsonEncode(row)],
        );
      }
    }
  }

  /// Caller supplies a freshly fetched complete snapshot; no automatic overwrite.
  Future<void> resolve(
    String id,
    bool useLocal,
    Map<String, List<Map<String, dynamic>>> tables,
  ) => db.transaction(() async {
    final all = await listConflicts();
    final matches = all.where((c) => c['id'] == id);
    if (matches.isEmpty) {
      throw const DiurnaException('NOT_FOUND', 'Conflict not found');
    }
    final conflict = matches.single;
    final type = conflict['entityType'] as String;
    if (!tables.containsKey(type)) {
      if (useLocal) {
        throw const DiurnaException(
          'UPGRADE_REQUIRED',
          'Legacy data is retained in the backup tables; copy required content into a new Inbox item',
        );
      }
      await db.customStatement(
        'DELETE FROM sync_conflicts WHERE id=? AND user_id=?',
        [id, userId],
      );
      return;
    }
    for (final c in conflict['changes'] as List) {
      final rows = tables[type]!.where((r) => r['id'] == c['id']);
      final remote = rows.isEmpty ? null : rows.single;
      if (useLocal && remote == null && c['expected_revision'] != 0) {
        throw const DiurnaException(
          'CONFLICT',
          'Remote entity deleted; create a new entity explicitly',
        );
      }
      if (useLocal) {
        await db.customStatement(
          'INSERT INTO sync_metadata VALUES (?,?,?,?,?) ON CONFLICT(user_id,entity_type,entity_id) DO UPDATE SET revision=excluded.revision,remote_json=excluded.remote_json',
          [userId, type, c['id'], remote?['revision'] ?? 0, jsonEncode(remote)],
        );
      } else {
        await (db.delete(
          db.pendingSyncOperations,
        )..where((t) => t.key.equals('$userId:$type:${c['id']}'))).go();
      }
    }
    await db.customStatement(
      'DELETE FROM sync_conflicts WHERE id=? AND user_id=?',
      [id, userId],
    );
  });
}
