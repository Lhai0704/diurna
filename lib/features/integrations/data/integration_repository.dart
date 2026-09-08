import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final integrationRepositoryProvider = Provider<IntegrationRepository>((ref) {
  try {
    return IntegrationRepository(ref.watch(supabaseClientProvider));
  } on Object {
    return IntegrationRepository.unavailable();
  }
});

class IntegrationRepository {
  IntegrationRepository(this._client) : _available = true;

  IntegrationRepository.unavailable() : _client = null, _available = false;

  final SupabaseClient? _client;
  final bool _available;

  bool get isAvailable => _available;

  Future<List<IntegrationConnection>> listConnections() async {
    final client = _client;
    if (client == null) {
      return const [];
    }
    final rows = await client
        .from('integration_connections')
        .select()
        .inFilter('status', ['pending', 'connected', 'error']);
    return (rows as List)
        .map((row) => IntegrationConnection.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> connect(String provider) async {
    final result = await _invoke({
      'action': 'connect',
      'provider': provider,
    });
    return result['authorization_url'] as String;
  }

  Future<SyncResult> sync(String provider, {String? runId}) async {
    final result = await _invoke({
      'action': 'sync',
      'provider': provider,
      'run_id': ?runId,
    });
    return SyncResult.fromMap(result);
  }

  Future<void> disconnect(String provider) async {
    await _invoke({'action': 'disconnect', 'provider': provider});
  }

  Future<void> updateSettings({
    required String provider,
    required Map<String, dynamic> enabledModules,
  }) async {
    await _invoke({
      'action': 'update_settings',
      'provider': provider,
      'enabled_modules': enabledModules,
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase 尚未配置。');
    }
    final response = await client.functions.invoke('integrations', body: body);
    final data = response.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('无效的同步响应');
  }
}
