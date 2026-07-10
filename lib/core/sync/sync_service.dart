import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:diurna/core/database/app_database.dart';
import 'package:diurna/core/sync/sync_remote_data_source.dart';

enum SyncPhase { idle, syncing, failed }

class SyncSnapshot {
  const SyncSnapshot({
    required this.phase,
    required this.pendingCount,
    this.lastError,
    this.lastSyncedAt,
  });

  const SyncSnapshot.idle()
    : phase = SyncPhase.idle,
      pendingCount = 0,
      lastError = null,
      lastSyncedAt = null;

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
  Future<void>? _activeSync;
  bool _disposed = false;
  int _pendingCount = 0;
  String? _lastError;
  DateTime? _lastSyncedAt;
  SyncPhase _phase = SyncPhase.idle;

  SyncSnapshot get snapshot => SyncSnapshot(
    phase: _phase,
    pendingCount: _pendingCount,
    lastError: _lastError,
    lastSyncedAt: _lastSyncedAt,
  );

  Stream<SyncSnapshot> get snapshots async* {
    yield snapshot;
    yield* _snapshots.stream;
  }

  void start() {
    _pendingSubscription = _database.watchPendingCount(_userId).listen((count) {
      _pendingCount = count;
      _emit();
      if (count > 0 && _phase != SyncPhase.syncing) {
        unawaited(syncNow());
      }
    });
    unawaited(syncNow());
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
      if (!_disposed && _pendingCount > 0 && _phase != SyncPhase.failed) {
        scheduleMicrotask(syncNow);
      }
    });
  }

  Future<void> _performSync() async {
    _retryTimer?.cancel();
    _phase = SyncPhase.syncing;
    _lastError = null;
    _emit();

    try {
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
          await _database.removePendingOperation(operation.key);
        } catch (error) {
          await _database.incrementPendingAttempt(operation, error);
          rethrow;
        }
      }

      final remoteSnapshot = await _remote.fetchSnapshot();
      await _database.applyRemoteSnapshot(
        _userId,
        tasks: remoteSnapshot.tasks,
        diaryEntries: remoteSnapshot.diaryEntries,
        calendarEvents: remoteSnapshot.calendarEvents,
      );
      _pendingCount = await _database.pendingCount(_userId);
      _lastSyncedAt = DateTime.now();
      _phase = SyncPhase.idle;
      _emit();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _pendingCount = await _database.pendingCount(_userId);
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
    await _pendingSubscription?.cancel();
    await _snapshots.close();
  }
}
