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
    final rows = await client.from('integration_connections').select().inFilter(
      'status',
      ['pending', 'connected', 'error'],
    );
    final connections = (rows as List)
        .map(
          (row) => IntegrationConnection.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
    final extras = await _loadInboundExtras(
      client,
      connections.map((item) => item.id).toList(),
    );
    return [
      for (final connection in connections)
        connection.withInboundCounts(
          openConflictCount: extras[connection.id]?.openConflicts ?? 0,
          remoteDeletedCount: extras[connection.id]?.remoteDeleted ?? 0,
          conflictReasons: extras[connection.id]?.reasons ?? const [],
        ),
    ];
  }

  Future<Map<String, _InboundExtras>> _loadInboundExtras(
    SupabaseClient client,
    List<String> connectionIds,
  ) async {
    if (connectionIds.isEmpty) {
      return const {};
    }
    final extras = <String, _InboundExtras>{};
    _InboundExtras forId(String id) =>
        extras.putIfAbsent(id, _InboundExtras.new);
    try {
      final conflictRows = await client
          .from('external_sync_conflict_summaries')
          .select('connection_id, reason')
          .eq('status', 'open')
          .inFilter('connection_id', connectionIds);
      for (final row in conflictRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['connection_id'] as String?;
        final reason = map['reason'] as String?;
        if (id == null) {
          continue;
        }
        final extra = forId(id);
        extra.openConflicts += 1;
        if (reason != null &&
            reason.isNotEmpty &&
            !extra.reasons.contains(reason)) {
          extra.reasons.add(reason);
        }
      }
    } on Object {
      // Inbound tables are absent until the hosted inbound migration.
    }
    try {
      final linkRows = await client
          .from('external_sync_links')
          .select('connection_id, inbound_state')
          .inFilter('connection_id', connectionIds)
          .inFilter('inbound_state', ['conflict', 'remote_deleted']);
      for (final row in linkRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['connection_id'] as String?;
        if (id == null) {
          continue;
        }
        final extra = forId(id);
        if (map['inbound_state'] == 'remote_deleted') {
          extra.remoteDeleted += 1;
        }
      }
    } on Object {
      // inbound_state is absent on the one-way-export schema.
    }
    return extras;
  }

  Future<String> connect(String provider) async {
    final result = await _invoke({'action': 'connect', 'provider': provider});
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

  Future<SyncResult> syncUntilComplete(String provider) async {
    var result = await sync(provider);
    for (
      var attempt = 0;
      attempt < 6 && result.errorCode == 'SYNC_IN_PROGRESS';
      attempt++
    ) {
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await sync(provider);
    }
    while (result.incomplete && result.runId != null) {
      result = await sync(provider, runId: result.runId);
    }
    return result;
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

  Future<List<ExternalConflictSummary>> listConflicts({String? connectionId}) async {
    final result = await _invoke({
      'action': 'list_conflicts',
      'connection_id': ?connectionId,
    });
    final rows = result['conflicts'];
    if (rows is! List) {
      return const [];
    }
    return [
      for (final row in rows)
        if (row is Map)
          ExternalConflictSummary.fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  Future<ConflictResolveResult> resolveConflict({
    required String conflictId,
    required String choice,
    required int expectedLocalRevision,
  }) async {
    final result = await _invoke({
      'action': 'resolve_conflict',
      'conflict_id': conflictId,
      'choice': choice,
      'expected_local_revision': expectedLocalRevision,
      'expected_current_local_revision': expectedLocalRevision,
    });
    return ConflictResolveResult.fromMap(result);
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

class _InboundExtras {
  int openConflicts = 0;
  int remoteDeleted = 0;
  final List<String> reasons = [];
}
