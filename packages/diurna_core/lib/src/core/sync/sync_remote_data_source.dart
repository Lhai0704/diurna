import 'dart:async';
import '../../contracts/errors.dart';
import 'versioned_sync_store.dart';
import 'package:supabase/supabase.dart';

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
    required this.memos,
    this.generation = 0,
  });

  final int generation;
  Map<String, List<Map<String, dynamic>>> get tables => {
    'inbox_items': inboxItems,
    'calendar_events': calendarEvents,
    'diary_entries': diaryEntries,
    'memos': memos,
  };
  final List<Map<String, dynamic>> inboxItems;
  final List<Map<String, dynamic>> diaryEntries;
  final List<Map<String, dynamic>> calendarEvents;
  final List<Map<String, dynamic>> memos;
}

abstract interface class VersionedSyncRemoteDataSource
    implements SyncRemoteDataSource {
  Future<Map<String, dynamic>> commit(SyncAttempt attempt);
  Stream<int> changes(String userId);
  Future<void> close();
}

class SupabaseSyncRemoteDataSource implements VersionedSyncRemoteDataSource {
  SupabaseSyncRemoteDataSource(this._client);
  final SupabaseClient _client;
  RealtimeChannel? _channel;
  StreamController<int>? _events;
  @override
  Future<void> upsert(String table, Map<String, dynamic> payload) async =>
      throw const DiurnaException(
        'UPGRADE_REQUIRED',
        'Use versioned synchronization',
      );
  @override
  Future<void> delete(String table, String id) async =>
      throw const DiurnaException(
        'UPGRADE_REQUIRED',
        'Use versioned synchronization',
      );
  @override
  Future<Map<String, dynamic>> commit(SyncAttempt attempt) async {
    final rpc = switch (attempt.entityType) {
      'inbox_items' => 'diurna_sync_inbox_v2',
      'calendar_events' => 'diurna_sync_calendar_v2',
      'diary_entries' => 'diurna_sync_diary_v2',
      'memos' => 'diurna_sync_memos_v2',
      _ => throw const DiurnaException('VALIDATION', 'Unsupported entity'),
    };
    final changes = attempt.changes
        .map((c) => Map<String, dynamic>.from(c)..remove('generation'))
        .toList();
    return _rpc(rpc, {'attempt_id': attempt.id, 'changes': changes});
  }

  Future<Map<String, dynamic>> _rpc(
    String name, [
    Map<String, dynamic>? params,
  ]) async {
    try {
      final value = await _client.rpc(name, params: params ?? {});
      if (value is! Map) {
        throw const DiurnaException(
          'SYNC_FAILED',
          'Invalid synchronization response',
        );
      }
      return Map<String, dynamic>.from(value);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' ||
          error.message.contains('UPGRADE_REQUIRED')) {
        throw const DiurnaException(
          'UPGRADE_REQUIRED',
          'Apply the Diurna v2 migrations before synchronizing',
        );
      }
      if (error.code == '42501' || error.code == 'PGRST301') {
        throw const DiurnaException(
          'AUTH_REQUIRED',
          'Authenticated access denied',
        );
      }
      throw const DiurnaException(
        'SYNC_FAILED',
        'Remote synchronization failed; local changes are retained',
      );
    }
  }

  @override
  Future<RemoteSnapshot> fetchSnapshot() async {
    final raw = await _rpc('diurna_snapshot_v2');
    if (raw['protocol'] != 2 || raw['complete'] != true) {
      throw const DiurnaException(
        'UPGRADE_REQUIRED',
        'Complete protocol v2 snapshot required',
      );
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null || raw['user_id'] != userId) {
      throw const DiurnaException(
        'AUTH_REQUIRED',
        'Snapshot identity mismatch',
      );
    }
    List<Map<String, dynamic>> rows(String key) {
      final value = raw[key];
      if (value is! List) {
        throw const DiurnaException('SYNC_FAILED', 'Incomplete snapshot');
      }
      final rows = value
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final ids = <String>{};
      for (final row in rows) {
        if (row['user_id'] != userId ||
            row['revision'] is! int ||
            !ids.add(row['id'] as String)) {
          throw const DiurnaException('SYNC_FAILED', 'Invalid snapshot row');
        }
      }
      return rows;
    }

    return RemoteSnapshot(
      inboxItems: rows('inbox_items'),
      calendarEvents: rows('calendar_events'),
      diaryEntries: rows('diary_entries'),
      memos: rows('memos'),
      generation: raw['generation'] as int,
    );
  }

  @override
  Stream<int> changes(String userId) {
    final events = _events = StreamController<int>();
    _channel = _client.channel('diurna-sync-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'diurna_sync_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          if (!events.isClosed) {
            events.add(payload.newRecord['generation'] as int? ?? -1);
          }
        },
      )
      ..subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed && !events.isClosed) {
          events.add(-1);
        }
      });
    return events.stream;
  }

  @override
  Future<void> close() async {
    if (_channel != null) await _client.removeChannel(_channel!);
    await _events?.close();
  }
}
