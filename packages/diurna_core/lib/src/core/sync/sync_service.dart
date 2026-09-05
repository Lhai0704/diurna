import '../../contracts/errors.dart';
import 'package:drift/drift.dart';
import 'versioned_sync_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:diurna_core/src/core/database/app_database.dart';
import 'package:diurna_core/src/core/sync/sync_remote_data_source.dart';

enum SyncPhase { idle, syncing, failed }

class SyncSnapshot {
  const SyncSnapshot({
    required this.phase,
    required this.pendingCount,
    this.lastError,
    this.lastSyncedAt,
    this.conflictCount = 0,
    this.errorCode,
  });

  const SyncSnapshot.idle()
    : phase = SyncPhase.idle,
      pendingCount = 0,
      lastError = null,
      lastSyncedAt = null,
      conflictCount = 0,
      errorCode = null;

  final int conflictCount;
  final String? errorCode;
  final SyncPhase phase;
  final int pendingCount;
  final String? lastError;
  final DateTime? lastSyncedAt;
}

class SyncService {
  SyncService({
    required AppDatabase database,
    required SyncRemoteDataSource remote,
    required String userId,
  }) : this._(database, remote, userId);

  SyncService._(this._database, this._remote, this._userId);

  final AppDatabase _database;
  final SyncRemoteDataSource _remote;
  final String _userId;
  final StreamController<SyncSnapshot> _snapshots =
      StreamController<SyncSnapshot>.broadcast();

  StreamSubscription<int>? _pendingSubscription;
  Timer? _retryTimer;
  Timer? _remoteDebounce;
  Timer? _pollTimer;
  StreamSubscription<int>? _remoteSubscription;
  int _conflictCount = 0;
  String? _errorCode;
  bool _foreground = true;
  int _forceRequests = 0;
  int _seenGeneration = 0;
  int _requestedGeneration = 0;
  bool _remoteDirty = false;
  Future<void>? _activeSync;
  bool _disposed = false;
  int _pendingCount = 0;
  String? _lastError;
  DateTime? _lastSyncedAt;
  SyncPhase _phase = SyncPhase.idle;

  SyncSnapshot get snapshot => SyncSnapshot(
    phase: _phase,
    conflictCount: _conflictCount,
    errorCode: _errorCode,
    pendingCount: _pendingCount,
    lastError: _lastError,
    lastSyncedAt: _lastSyncedAt,
  );

  Stream<SyncSnapshot> get snapshots async* {
    yield snapshot;
    yield* _snapshots.stream;
  }

  void start() {
    if (_pendingSubscription != null) return;
    final remote = _remote;
    if (remote is VersionedSyncRemoteDataSource) {
      _remoteSubscription = remote.changes(_userId).listen(requestRemoteSync);
      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_foreground) requestRemoteSync(-1);
      });
    }
    _pendingSubscription = _database.watchPendingCount(_userId).listen((count) {
      _pendingCount = count;
      _emit();
      if (count > 0 && _phase == SyncPhase.idle) {
        unawaited(syncNow());
      }
    });
    unawaited(syncNow());
  }

  void requestRemoteSync(int generation) {
    if (_disposed || (generation >= 0 && generation <= _seenGeneration)) return;
    if (generation < 0) _forceRequests++;
    _requestedGeneration = max(_requestedGeneration, generation);
    _remoteDirty = true;
    if (_activeSync != null || _phase == SyncPhase.failed) return;
    _remoteDebounce?.cancel();
    _remoteDebounce = Timer(const Duration(milliseconds: 500), syncNow);
  }

  void setForeground(bool active) {
    _foreground = active;
    if (active) requestRemoteSync(-1);
  }

  Future<List<Map<String, dynamic>>> conflicts() =>
      VersionedSyncStore(_database, _userId).listConflicts();
  Future<void> resolveConflict(String id, {required bool useLocal}) async {
    await syncNow();
    final snapshot = await _remote.fetchSnapshot();
    if (_disposed) return;
    await VersionedSyncStore(
      _database,
      _userId,
    ).resolve(id, useLocal, snapshot.tables);
    await syncNow();
  }

  Future<void> syncNow() {
    if (_disposed) {
      return Future.value();
    }
    final active = _activeSync;
    if (active != null) {
      return active;
    }
    final future = _performSync();
    _activeSync = future;
    return future.whenComplete(() {
      _activeSync = null;
      if (!_disposed && _remoteDirty && _phase != SyncPhase.failed) {
        scheduleMicrotask(syncNow);
      }
    });
  }

  Future<void> _performSync() async {
    _retryTimer?.cancel();
    _phase = SyncPhase.syncing;
    _lastError = null;
    _errorCode = null;
    final forceAtStart = _forceRequests;
    _emit();

    try {
      _remoteDirty = false;
      final remote = _remote;
      if (remote is VersionedSyncRemoteDataSource) {
        final store = VersionedSyncStore(_database, _userId);
        for (final attempt in await store.attempts()) {
          if (_disposed) return;
          Map<String, dynamic> result;
          try {
            result = await remote.commit(attempt);
          } catch (error) {
            for (final change in attempt.changes) {
              final operations = await _database.pendingOperations(_userId);
              for (final op in operations.where(
                (o) =>
                    o.entityId == change['id'] &&
                    o.generation == change['generation'],
              )) {
                await _database.incrementPendingAttempt(op, error);
              }
            }
            rethrow;
          }
          if (_disposed) return;
          if (result['ok'] == true) {
            await store.acknowledge(
              attempt,
              (result['revisions'] as List).cast<Map<String, dynamic>>(),
            );
          } else if (result['code'] == 'CONFLICT') {
            await store.conflict(attempt, result['remote'] ?? []);
          } else {
            throw StateError(
              result['code']?.toString() ?? 'Invalid synchronization response',
            );
          }
        }
      } else {
        final operations = await _database.pendingOperations(_userId);
        for (final operation in operations) {
          try {
            if (operation.operation == 'delete') {
              await _remote.delete(operation.entityType, operation.entityId);
            } else {
              final payload = Map<String, dynamic>.from(
                jsonDecode(operation.payloadJson!) as Map,
              );
              await _remote.upsert(operation.entityType, payload);
            }
            await (_database.delete(_database.pendingSyncOperations)..where(
                  (t) =>
                      t.key.equals(operation.key) &
                      t.generation.equals(operation.generation),
                ))
                .go();
          } catch (error) {
            await _database.incrementPendingAttempt(operation, error);
            rethrow;
          }
        }
      }
      final remoteSnapshot = await _remote.fetchSnapshot();
      if (_disposed) return;
      await _database.transaction(() async {
        await _database.applyRemoteSnapshot(
          _userId,
          inboxItems: remoteSnapshot.inboxItems,
          diaryEntries: remoteSnapshot.diaryEntries,
          calendarEvents: remoteSnapshot.calendarEvents,
          memos: remoteSnapshot.memos,
        );
        await VersionedSyncStore(
          _database,
          _userId,
        ).applyMetadata(remoteSnapshot.tables);
      });
      _seenGeneration = remoteSnapshot.generation;
      _remoteDirty =
          _requestedGeneration > _seenGeneration ||
          _forceRequests > forceAtStart;
      final store = VersionedSyncStore(_database, _userId);
      _conflictCount = (await store.listConflicts()).length;
      if (_remote is VersionedSyncRemoteDataSource) {
        _remoteDirty = _remoteDirty || (await store.attempts()).isNotEmpty;
      }
      _pendingCount = await _database.pendingCount(_userId);
      _lastSyncedAt = DateTime.now();
      _phase = SyncPhase.idle;
      _emit();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _pendingCount = await _database.pendingCount(_userId);
      _errorCode = error is DiurnaException ? error.code : 'SYNC_FAILED';
      _lastError = error.toString();
      _phase = SyncPhase.failed;
      _emit();
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    unawaited(_scheduleRetryFromDatabase());
  }

  Future<void> _scheduleRetryFromDatabase() async {
    final operations = await _database.pendingOperations(_userId);
    final attempts = operations.isEmpty
        ? 1
        : operations.map((operation) => operation.attemptCount).reduce(max);
    final seconds = min(60, pow(2, attempts.clamp(1, 6)).toInt());
    if (!_disposed) {
      _retryTimer = Timer(Duration(seconds: seconds), syncNow);
    }
  }

  void _emit() {
    if (!_disposed) {
      _snapshots.add(snapshot);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _remoteDebounce?.cancel();
    _pollTimer?.cancel();
    await _remoteSubscription?.cancel();
    final remote = _remote;
    if (remote is VersionedSyncRemoteDataSource) await remote.close();
    await _activeSync;
    await _pendingSubscription?.cancel();
    await _snapshots.close();
  }
}
