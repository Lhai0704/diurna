import 'dart:async';

import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:diurna/features/integrations/data/integration_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final integrationConnectionsProvider =
    FutureProvider<List<IntegrationConnection>>((ref) async {
      ref.watch(authStateProvider);
      return ref.watch(integrationRepositoryProvider).listConnections();
    });

class IntegrationController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  IntegrationRepository get _repo => ref.read(integrationRepositoryProvider);

  Future<void> connect(String provider) async {
    state = const AsyncLoading();
    try {
      final url = await _repo.connect(provider);
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      state = const AsyncData(null);
      unawaited(_pollUntilConnected(provider));
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
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
    state = const AsyncLoading();
    try {
      var result = await _repo.sync(provider);
      while (result.incomplete && result.runId != null) {
        result = await _repo.sync(provider, runId: result.runId);
      }
      ref.invalidate(integrationConnectionsProvider);
      state = const AsyncData(null);
      return result;
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
      return null;
    }
  }

  Future<void> disconnect(String provider) async {
    state = const AsyncLoading();
    try {
      await _repo.disconnect(provider);
      ref.invalidate(integrationConnectionsProvider);
      state = const AsyncData(null);
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    }
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
}

final integrationControllerProvider =
    NotifierProvider<IntegrationController, AsyncValue<void>>(
      IntegrationController.new,
    );
