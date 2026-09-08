import 'dart:async';

import 'package:diurna/features/integrations/data/integration_models.dart';

typedef LoadConnections = Future<List<IntegrationConnection>> Function();
typedef ExportProvider = Future<SyncResult> Function(String provider);
typedef CreateTimer =
    Timer Function(Duration duration, void Function() callback);

/// Debounces a one-way Notion/Google export until protocol v2 generation
/// has been stable for [delay]. Does not follow every cloud syncNow call.
class ExternalExportScheduler {
  ExternalExportScheduler({
    required this.loadConnections,
    required this.export,
    this.onExported,
    this.delay = const Duration(minutes: 1),
    CreateTimer? createTimer,
  }) : _createTimer = createTimer ?? Timer.new;

  static const Duration defaultDelay = Duration(minutes: 1);

  final LoadConnections loadConnections;
  final ExportProvider export;
  final void Function()? onExported;
  final Duration delay;
  final CreateTimer _createTimer;

  Timer? _timer;
  int _armedGeneration = 0;
  int _observedGeneration = -1;
  int? _lastPending;
  bool _exportAll = false;
  bool _running = false;
  bool _dirty = false;
  bool _disposed = false;

  void consider({
    required int generation,
    required int pendingCount,
    required bool idle,
    required List<IntegrationConnection> connections,
  }) {
    if (_disposed) {
      return;
    }
    final pendingDrained = idle && (_lastPending ?? 0) > 0 && pendingCount == 0;
    _lastPending = pendingCount;
    if (!idle) {
      return;
    }
    final generationAdvanced =
        _observedGeneration >= 0 && generation > _observedGeneration;
    if (generation > _observedGeneration) {
      _observedGeneration = generation;
    } else if (_observedGeneration < 0) {
      _observedGeneration = generation;
    }
    if (pendingDrained || generationAdvanced) {
      _exportAll = true;
    }

    final due = connections.where((item) {
      if (!item.isConnected || item.isReauthRequired) {
        return false;
      }
      if (_exportAll) {
        return true;
      }
      return item.needsExport(generation) || item.needsRetry;
    });
    if (due.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _dirty = false;
      _exportAll = false;
      _armedGeneration = generation;
      return;
    }
    if (_running) {
      if (generation > _armedGeneration ||
          pendingDrained ||
          generationAdvanced) {
        _dirty = true;
        _armedGeneration = generation > _armedGeneration
            ? generation
            : _armedGeneration;
      }
      return;
    }
    if (_timer != null &&
        _timer!.isActive &&
        _armedGeneration == generation &&
        !pendingDrained &&
        !generationAdvanced) {
      return;
    }
    _armedGeneration = generation;
    _timer?.cancel();
    _timer = _createTimer(delay, _fire);
  }

  void _fire() {
    _timer = null;
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_disposed || _running) {
      return;
    }
    _running = true;
    var exported = false;
    var retry = false;
    final exportAll = _exportAll;
    _exportAll = false;
    try {
      final generation = _armedGeneration;
      final connections = await loadConnections();
      if (_disposed) {
        return;
      }
      for (final connection in connections) {
        if (!connection.isConnected || connection.isReauthRequired) {
          continue;
        }
        if (!exportAll &&
            !connection.needsExport(generation) &&
            !connection.needsRetry) {
          continue;
        }
        try {
          final result = await export(connection.provider);
          if (_disposed) {
            return;
          }
          exported = true;
          if (result.isReauthRequired) {
            continue;
          }
          if (result.errorCode == 'SYNC_IN_PROGRESS' ||
              !result.ok ||
              result.status == 'partial') {
            retry = true;
          }
        } on Object {
          retry = true;
        }
      }
    } finally {
      if (exported) {
        onExported?.call();
      }
      _running = false;
      if (!_disposed && (_dirty || retry)) {
        _dirty = false;
        _timer?.cancel();
        _timer = _createTimer(delay, _fire);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
