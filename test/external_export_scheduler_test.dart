import 'dart:async';

import 'package:diurna/features/integrations/data/external_export_scheduler.dart';
import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    callback();
  }
}

void main() {
  IntegrationConnection connection({
    required String provider,
    int? lastSeenGeneration,
    String status = 'connected',
  }) {
    return IntegrationConnection(
      id: provider,
      provider: provider,
      status: status,
      lastSyncStatus: lastSeenGeneration == null ? 'never' : 'success',
      enabledModules: const {},
      lastSeenGeneration: lastSeenGeneration,
    );
  }

  ({
    ExternalExportScheduler scheduler,
    List<_FakeTimer> timers,
    List<String> exported,
  })
  createScheduler(LoadConnections loadConnections) {
    final timers = <_FakeTimer>[];
    final exported = <String>[];
    final scheduler = ExternalExportScheduler(
      loadConnections: loadConnections,
      export: (provider) async {
        exported.add(provider);
        return const SyncResult(ok: true, status: 'success', incomplete: false);
      },
      createTimer: (duration, callback) {
        final timer = _FakeTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
    return (scheduler: scheduler, timers: timers, exported: exported);
  }

  test('waits one minute after generation advances before exporting', () async {
    final notion = connection(provider: 'notion', lastSeenGeneration: 1);
    final harness = createScheduler(() async => [notion]);

    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    expect(harness.exported, isEmpty);
    expect(harness.timers, hasLength(1));
    expect(
      harness.timers.single.duration,
      ExternalExportScheduler.defaultDelay,
    );

    harness.timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, ['notion']);
    harness.scheduler.dispose();
  });

  test('resets the debounce when generation advances again', () async {
    final notion = connection(provider: 'notion', lastSeenGeneration: 1);
    final harness = createScheduler(() async => [notion]);

    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    harness.scheduler.consider(
      generation: 3,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    expect(harness.timers, hasLength(2));
    expect(harness.timers.first.isActive, isFalse);

    harness.timers.first.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, isEmpty);

    harness.timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, ['notion']);
    harness.scheduler.dispose();
  });

  test('does not reset the timer when the same generation is re-emitted', () {
    final notion = connection(provider: 'notion', lastSeenGeneration: 1);
    final harness = createScheduler(() async => [notion]);

    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    expect(harness.timers, hasLength(1));
    expect(harness.timers.single.isActive, isTrue);
    harness.scheduler.dispose();
  });

  test('skips providers already caught up with cloud generation', () async {
    final notion = connection(provider: 'notion', lastSeenGeneration: 4);
    final google = connection(provider: 'google', lastSeenGeneration: 2);
    final harness = createScheduler(() async => [notion, google]);

    harness.scheduler.consider(
      generation: 4,
      pendingCount: 0,
      idle: true,
      connections: [notion, google],
    );
    harness.timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, ['google']);
    harness.scheduler.dispose();
  });

  test('cancels a pending export when every provider catches up', () async {
    var notion = connection(provider: 'notion', lastSeenGeneration: 1);
    final harness = createScheduler(() async => [notion]);

    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    notion = connection(provider: 'notion', lastSeenGeneration: 2);
    harness.scheduler.consider(
      generation: 2,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    expect(harness.timers.single.isActive, isFalse);

    harness.timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, isEmpty);
    harness.scheduler.dispose();
  });

  test('pending drain exports caught-up Notion after a local save', () async {
    final notion = connection(provider: 'notion', lastSeenGeneration: 4);
    final harness = createScheduler(() async => [notion]);

    harness.scheduler.consider(
      generation: 4,
      pendingCount: 1,
      idle: false,
      connections: [notion],
    );
    expect(harness.timers, isEmpty);

    harness.scheduler.consider(
      generation: 4,
      pendingCount: 0,
      idle: true,
      connections: [notion],
    );
    expect(harness.timers, hasLength(1));
    harness.timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(harness.exported, ['notion']);
    harness.scheduler.dispose();
  });

  test('does not auto-retry a provider that requires reauth', () {
    final google = IntegrationConnection(
      id: 'google',
      provider: 'google',
      status: 'connected',
      lastSyncStatus: 'failed',
      enabledModules: const {},
      lastError: 'REAUTH_REQUIRED',
      lastSeenGeneration: 1,
    );
    final harness = createScheduler(() async => [google]);

    harness.scheduler.consider(
      generation: 4,
      pendingCount: 0,
      idle: true,
      connections: [google],
    );
    expect(harness.timers, isEmpty);
    harness.scheduler.dispose();
  });
}
