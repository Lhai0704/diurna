import 'dart:async';

import 'package:diurna/core/sync/sync_providers.dart';
import 'package:diurna/core/sync/sync_service.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/integrations/data/external_export_scheduler.dart';
import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/data/integration_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final integrationConnectionsProvider =
    FutureProvider<List<IntegrationConnection>>((ref) async {
      ref.watch(authStateProvider);
      return ref.watch(integrationRepositoryProvider).listConnections();
    });

final externalConflictsProvider =
    FutureProvider.family<List<ExternalConflictSummary>, String?>((
      ref,
      connectionId,
    ) async {
      ref.watch(authStateProvider);
      return ref
          .watch(integrationRepositoryProvider)
          .listConflicts(connectionId: connectionId);
    });

class IntegrationActionState {
  const IntegrationActionState({
    this.busyProviders = const {},
    this.errors = const {},
  });

  final Set<String> busyProviders;
  final Map<String, String> errors;

  bool isBusy(String provider) => busyProviders.contains(provider);

  String? errorOf(String provider) => errors[provider];

  IntegrationActionState start(String provider) {
    return IntegrationActionState(
      busyProviders: {...busyProviders, provider},
      errors: {...errors}..remove(provider),
    );
  }

  IntegrationActionState finish(String provider) {
    return IntegrationActionState(
      busyProviders: {...busyProviders}..remove(provider),
      errors: {...errors}..remove(provider),
    );
  }

  IntegrationActionState fail(String provider, Object error) {
    return IntegrationActionState(
      busyProviders: {...busyProviders}..remove(provider),
      errors: {...errors, provider: error.toString()},
    );
  }
}

class IntegrationController extends Notifier<IntegrationActionState> {
  @override
  IntegrationActionState build() => const IntegrationActionState();

  IntegrationRepository get _repo => ref.read(integrationRepositoryProvider);

  Future<void> _run(String provider, Future<void> Function() action) async {
    state = state.start(provider);
    try {
      await action();
      if (!ref.mounted) {
        return;
      }
      state = state.finish(provider);
    } on Object catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.fail(provider, error);
    }
  }

  Future<void> connect(String provider) async {
    await _run(provider, () async {
      final url = await _repo.connect(provider);
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      unawaited(_pollUntilConnected(provider));
    });
  }

  Future<void> _pollUntilConnected(String provider) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!ref.mounted) {
        return;
      }
      ref.invalidate(integrationConnectionsProvider);
      final items = await ref.read(integrationConnectionsProvider.future);
      if (items.any((item) => item.provider == provider && item.isConnected)) {
        return;
      }
    }
  }

  Future<SyncResult?> sync(String provider) async {
    SyncResult? result;
    await _run(provider, () async {
      result = await _repo.syncUntilComplete(provider);
      ref.invalidate(integrationConnectionsProvider);
    });
    return result;
  }

  Future<void> disconnect(String provider) async {
    await _run(provider, () async {
      await _repo.disconnect(provider);
      ref.invalidate(integrationConnectionsProvider);
    });
  }

  Future<void> updateModules(
    String provider,
    Map<String, dynamic> enabledModules,
  ) async {
    await _repo.updateSettings(
      provider: provider,
      enabledModules: enabledModules,
    );
    ref.invalidate(integrationConnectionsProvider);
  }

  Future<void> resolveConflict(
    ExternalConflictSummary conflict,
    String choice,
  ) async {
    final key = 'conflict:${conflict.id}';
    await _run(key, () async {
      final result = await _repo.resolveConflict(
        conflictId: conflict.id,
        choice: choice,
        expectedLocalRevision: conflict.localRevision,
      );
      if (!result.ok) {
        throw conflictResolveErrorLabel(result.errorCode);
      }
      ref.invalidate(integrationConnectionsProvider);
      ref.invalidate(externalConflictsProvider(conflict.connectionId));
      ref.invalidate(externalConflictsProvider(null));
    });
  }
}

final integrationControllerProvider =
    NotifierProvider<IntegrationController, IntegrationActionState>(
      IntegrationController.new,
    );

final externalExportSchedulerProvider = Provider<ExternalExportScheduler?>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return null;
  }
  final scheduler = ExternalExportScheduler(
    delay: ExternalExportScheduler.defaultDelay,
    loadConnections: () {
      if (!ref.mounted) {
        return Future.value(const <IntegrationConnection>[]);
      }
      return ref.read(integrationRepositoryProvider).listConnections();
    },
    export: (provider) {
      if (!ref.mounted) {
        return Future.value(
          const SyncResult(ok: false, status: 'failed', incomplete: false),
        );
      }
      return ref
          .read(integrationRepositoryProvider)
          .syncUntilComplete(provider);
    },
    onExported: () {
      if (ref.mounted) {
        ref.invalidate(integrationConnectionsProvider);
      }
    },
  );
  ref.onDispose(scheduler.dispose);

  void consider() {
    final snapshot = ref.read(syncSnapshotProvider).asData?.value;
    final connections = ref.read(integrationConnectionsProvider).asData?.value;
    if (snapshot == null || connections == null) {
      return;
    }
    scheduler.consider(
      generation: snapshot.generation,
      pendingCount: snapshot.pendingCount,
      idle: snapshot.phase == SyncPhase.idle,
      connections: connections,
    );
  }

  ref.listen(syncSnapshotProvider, (_, _) => consider());
  ref.listen(integrationConnectionsProvider, (_, _) => consider());
  consider();
  return scheduler;
});
