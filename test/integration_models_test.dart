import 'package:diurna/features/integrations/data/integration_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromMap defaults inbound fields when the hosted schema is older', () {
    final connection = IntegrationConnection.fromMap({
      'id': 'c1',
      'provider': 'google',
      'status': 'connected',
      'last_sync_status': 'success',
    });
    expect(connection.inboundStatus, 'disabled');
    expect(connection.lastInboundAt, isNull);
    expect(connection.inboundError, isNull);
    expect(connection.openConflictCount, 0);
    expect(connection.remoteDeletedCount, 0);
  });

  test('fromMap parses inbound observability columns', () {
    final connection = IntegrationConnection.fromMap({
      'id': 'c1',
      'provider': 'notion',
      'status': 'connected',
      'last_sync_status': 'success',
      'inbound_status': 'active',
      'last_inbound_at': '2026-09-09T12:00:00.000Z',
      'last_inbound_result': 'incremental',
      'inbound_error': null,
      'open_conflict_count': 2,
      'remote_deleted_count': 1,
      'conflict_reasons': ['unsupported_content', 'bootstrap_remote_drift'],
    });
    expect(connection.inboundStatus, 'active');
    expect(connection.lastInboundAt, DateTime.utc(2026, 9, 9, 12));
    expect(connection.lastInboundResult, 'incremental');
    expect(connection.openConflictCount, 2);
    expect(connection.remoteDeletedCount, 1);
    expect(connection.conflictReasons, [
      'unsupported_content',
      'bootstrap_remote_drift',
    ]);
    expect(inboundStatusLabel(connection.inboundStatus), '入站正常');
    expect(inboundResultLabel(connection.lastInboundResult), '增量同步');
  });

  test('inbound error treats REAUTH_REQUIRED as reconnect', () {
    final connection = IntegrationConnection.fromMap({
      'id': 'c1',
      'provider': 'google',
      'status': 'connected',
      'last_sync_status': 'success',
      'inbound_status': 'error',
      'inbound_error': 'REAUTH_REQUIRED',
    });
    expect(connection.isReauthRequired, isTrue);
    expect(connection.inboundIsDegraded, isFalse);
  });

  test('Google degraded does not mean the connection is unusable', () {
    final connection = IntegrationConnection(
      id: 'c1',
      provider: 'google',
      status: 'connected',
      lastSyncStatus: 'success',
      enabledModules: const {},
      inboundStatus: 'degraded',
      inboundError: 'WATCH_FAILED',
    );
    expect(connection.isConnected, isTrue);
    expect(connection.inboundIsDegraded, isTrue);
    expect(connection.inboundRepairAvailable, isTrue);
    expect(connection.isReauthRequired, isFalse);
    expect(
      inboundDegradedHint(connection.provider, connection.inboundStatus),
      contains('定时修复仍会同步已关联事件'),
    );
    expect(safeInboundCode('WATCH_FAILED'), 'WATCH_FAILED');
  });

  test('conflict summary parses without snapshot fields', () {
    final summary = ExternalConflictSummary.fromMap({
      'id': 'c1',
      'connection_id': 'n1',
      'provider': 'notion',
      'entity_type': 'diary_entries',
      'entity_id': 'e1',
      'reason': 'bootstrap_remote_drift',
      'local_revision': 1,
      'last_synced_revision': 1,
      'can_keep_local_push': true,
      'can_use_remote': true,
      'entity_label': '2026-07-31',
      'field_categories': ['title', 'content'],
    });
    expect(summary.entityLabel, '2026-07-31');
    expect(summary.fieldCategories, ['title', 'content']);
    expect(conflictEntityTypeLabel(summary.entityType), '日记');
    expect(conflictFieldLabel('entry_date'), '日期');
    expect(conflictResolveErrorLabel('STALE_CONFLICT'), contains('刷新'));
    expect(conflictResolveErrorLabel('PROVIDER_WRITE_FAILED'), contains('仍保留'));
    expect(conflictResolveErrorLabel('PROVIDER_VERIFY_FAILED'), contains('重试'));
    expect(conflictResolveErrorLabel('PROVIDER_VERSION_CONFLICT'), contains('刷新'));
  });

  test('safeInboundCode hides tokens and ciphertext', () {
    expect(safeInboundCode('tok-secret'), isNull);
    expect(safeInboundCode('Bearer abc'), isNull);
    expect(safeInboundCode('INTEGRATIONS_MAINTENANCE_SECRET'), isNull);
    expect(safeInboundCode('cipher-text'), isNull);
    expect(safeInboundCode('CALENDAR_GONE'), 'CALENDAR_GONE');
    expect(inboundReasonLabel('unsupported_timed_event'), '不支持的定时事件');
    expect(inboundReasonLabel('unsupported_content'), '不支持的 Notion 正文');
    expect(inboundReasonLabel('remote_deleted'), '远端已删除');
  });
}
