class IntegrationConnection {
  const IntegrationConnection({
    required this.id,
    required this.provider,
    required this.status,
    required this.lastSyncStatus,
    required this.enabledModules,
    this.displayName,
    this.lastSyncAt,
    this.lastError,
    this.lastSyncSummary = const {},
    this.container = const {},
  });

  final String id;
  final String provider;
  final String status;
  final String lastSyncStatus;
  final Map<String, dynamic> enabledModules;
  final String? displayName;
  final DateTime? lastSyncAt;
  final String? lastError;
  final Map<String, dynamic> lastSyncSummary;
  final Map<String, dynamic> container;

  bool get isConnected => status == 'connected';

  factory IntegrationConnection.fromMap(Map<String, dynamic> map) {
    return IntegrationConnection(
      id: map['id'] as String,
      provider: map['provider'] as String,
      status: map['status'] as String,
      lastSyncStatus: map['last_sync_status'] as String? ?? 'never',
      enabledModules: Map<String, dynamic>.from(
        map['enabled_modules'] as Map? ?? const {},
      ),
      displayName: map['display_name'] as String?,
      lastSyncAt: map['last_sync_at'] == null
          ? null
          : DateTime.tryParse(map['last_sync_at'] as String),
      lastError: map['last_error'] as String?,
      lastSyncSummary: Map<String, dynamic>.from(
        map['last_sync_summary'] as Map? ?? const {},
      ),
      container: Map<String, dynamic>.from(map['container'] as Map? ?? const {}),
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.ok,
    required this.status,
    required this.incomplete,
    this.runId,
    this.modules = const {},
    this.failures = const [],
    this.errorCode,
    this.errorMessage,
  });

  final bool ok;
  final String status;
  final bool incomplete;
  final String? runId;
  final Map<String, dynamic> modules;
  final List<dynamic> failures;
  final String? errorCode;
  final String? errorMessage;

  factory SyncResult.fromMap(Map<String, dynamic> map) {
    final error = map['error'];
    return SyncResult(
      ok: map['ok'] == true,
      status: map['status'] as String? ?? 'failed',
      incomplete: map['incomplete'] == true,
      runId: map['run_id'] as String?,
      modules: Map<String, dynamic>.from(map['modules'] as Map? ?? const {}),
      failures: List<dynamic>.from(map['failures'] as List? ?? const []),
      errorCode: error is Map ? error['code'] as String? : null,
      errorMessage: error is Map ? error['message'] as String? : null,
    );
  }
}
