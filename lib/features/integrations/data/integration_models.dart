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
    this.lastSeenGeneration,
    this.inboundStatus = 'disabled',
    this.lastInboundAt,
    this.lastInboundResult,
    this.inboundError,
    this.openConflictCount = 0,
    this.remoteDeletedCount = 0,
    this.conflictReasons = const [],
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
  final int? lastSeenGeneration;
  final String inboundStatus;
  final DateTime? lastInboundAt;
  final String? lastInboundResult;
  final String? inboundError;
  final int openConflictCount;
  final int remoteDeletedCount;
  final List<String> conflictReasons;

  bool get isConnected => status == 'connected';

  bool get inboundIsDegraded => inboundStatus == 'degraded';

  bool get inboundRepairAvailable =>
      inboundStatus == 'degraded' || inboundStatus == 'active';

  bool get isReauthRequired =>
      lastError == 'REAUTH_REQUIRED' ||
      inboundError == 'REAUTH_REQUIRED' ||
      lastSyncStatus == 'failed' && lastError == 'REAUTH_REQUIRED';

  bool get needsRetry =>
      lastSyncStatus == 'partial' ||
      lastSyncStatus == 'failed' ||
      lastSyncStatus == 'pending';

  bool needsExport(int generation) {
    if (!isConnected || isReauthRequired) {
      return false;
    }
    final seen = lastSeenGeneration;
    return seen == null || seen < generation;
  }

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
      container: Map<String, dynamic>.from(
        map['container'] as Map? ?? const {},
      ),
      lastSeenGeneration: _asInt(map['last_seen_generation']),
      inboundStatus: map['inbound_status'] as String? ?? 'disabled',
      lastInboundAt: map['last_inbound_at'] == null
          ? null
          : DateTime.tryParse(map['last_inbound_at'] as String),
      lastInboundResult: map['last_inbound_result'] as String?,
      inboundError: map['inbound_error'] as String?,
      openConflictCount: _asInt(map['open_conflict_count']) ?? 0,
      remoteDeletedCount: _asInt(map['remote_deleted_count']) ?? 0,
      conflictReasons: _asStringList(map['conflict_reasons']),
    );
  }

  IntegrationConnection withInboundCounts({
    int openConflictCount = 0,
    int remoteDeletedCount = 0,
    List<String> conflictReasons = const [],
  }) {
    return IntegrationConnection(
      id: id,
      provider: provider,
      status: status,
      lastSyncStatus: lastSyncStatus,
      enabledModules: enabledModules,
      displayName: displayName,
      lastSyncAt: lastSyncAt,
      lastError: lastError,
      lastSyncSummary: lastSyncSummary,
      container: container,
      lastSeenGeneration: lastSeenGeneration,
      inboundStatus: inboundStatus,
      lastInboundAt: lastInboundAt,
      lastInboundResult: lastInboundResult,
      inboundError: inboundError,
      openConflictCount: openConflictCount,
      remoteDeletedCount: remoteDeletedCount,
      conflictReasons: conflictReasons,
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      ];
    }
    return const [];
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

String inboundStatusLabel(String status) {
  return switch (status) {
    'bootstrapping' => '正在建立入站基线',
    'active' => '入站正常',
    'degraded' => '入站降级',
    'error' => '入站错误',
    _ => '入站未启用',
  };
}

String? inboundDegradedHint(String provider, String status) {
  if (status != 'degraded') {
    return null;
  }
  if (provider == 'google') {
    return '日历推送暂不可用，定时修复仍会同步已关联事件。连接未停用。';
  }
  return '入站推送异常，定时修复仍可用。连接未停用。';
}

String inboundResultLabel(String? result) {
  return switch (result) {
    'bootstrap' => '基线完成',
    'incremental' => '增量同步',
    'full_resync' => '全量重建游标',
    'repair' => '定时修复',
    'renew_watch' => '已续订推送',
    'ok' => '成功',
    'error' => '失败',
    null => '尚未入站',
    _ => safeInboundCode(result) ?? '已处理',
  };
}

String inboundReasonLabel(String reason) {
  return switch (reason) {
    'unsupported_content' => '不支持的 Notion 正文',
    'unsupported_timed_event' => '不支持的定时事件',
    'unsupported_recurrence' => '不支持的重复事件',
    'bootstrap_remote_drift' => '远端与本地不一致',
    'remote_deleted_with_local_edit' => '远端已删除且本地有未同步修改',
    'remote_deleted' => '远端已删除',
    'inbox_relationship' => '收集箱关系冲突',
    _ => reason,
  };
}

/// Display-only codes. Anything that looks like a secret is omitted.
String? safeInboundCode(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final lower = value.toLowerCase();
  if (lower.contains('token') ||
      lower.contains('bearer') ||
      lower.contains('secret') ||
      lower.contains('cipher') ||
      lower.contains('password')) {
    return null;
  }
  if (!RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value)) {
    return null;
  }
  return value;
}

class ExternalConflictSummary {
  const ExternalConflictSummary({
    required this.id,
    required this.connectionId,
    required this.provider,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.localRevision,
    required this.lastSyncedRevision,
    required this.canKeepLocalPush,
    required this.canUseRemote,
    this.entityLabel,
    this.fieldCategories = const [],
    this.blockedReason,
    this.createdAt,
  });

  final String id;
  final String connectionId;
  final String provider;
  final String entityType;
  final String entityId;
  final String reason;
  final int localRevision;
  final int lastSyncedRevision;
  final bool canKeepLocalPush;
  final bool canUseRemote;
  final String? entityLabel;
  final List<String> fieldCategories;
  final String? blockedReason;
  final DateTime? createdAt;

  factory ExternalConflictSummary.fromMap(Map<String, dynamic> map) {
    return ExternalConflictSummary(
      id: map['id'] as String,
      connectionId: map['connection_id'] as String,
      provider: map['provider'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      reason: map['reason'] as String,
      localRevision: IntegrationConnection._asInt(map['local_revision']) ?? 0,
      lastSyncedRevision:
          IntegrationConnection._asInt(map['last_synced_revision']) ?? 0,
      canKeepLocalPush: map['can_keep_local_push'] != false,
      canUseRemote: map['can_use_remote'] != false,
      entityLabel: map['entity_label'] as String?,
      fieldCategories: IntegrationConnection._asStringList(
        map['field_categories'],
      ),
      blockedReason: map['blocked_reason'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
    );
  }
}

String conflictEntityTypeLabel(String entityType) {
  return switch (entityType) {
    'inbox_items' => '收集箱',
    'memos' => '备忘',
    'diary_entries' => '日记',
    'calendar_events' => '日历',
    _ => entityType,
  };
}

String conflictFieldLabel(String field) {
  return switch (field) {
    'title' => '标题',
    'content' => '正文',
    'entry_date' => '日期',
    'event_date' => '日期',
    'mood' => '心情',
    'note' => '备注',
    'is_pinned' => '置顶',
    'is_completed' => '完成',
    'item_type' => '类型',
    'inbox_column' => '列',
    _ => field,
  };
}

class ConflictResolveResult {
  const ConflictResolveResult({
    required this.ok,
    this.result,
    this.errorCode,
  });

  final bool ok;
  final String? result;
  final String? errorCode;

  factory ConflictResolveResult.fromMap(Map<String, dynamic> map) {
    final error = map['error'];
    return ConflictResolveResult(
      ok: map['ok'] == true,
      result: map['result'] as String?,
      errorCode: error is Map ? error['code'] as String? : null,
    );
  }
}

String conflictResolveErrorLabel(String? code) {
  return switch (code) {
    'STALE_CONFLICT' => '本地已变化，请刷新后重新选择',
    'UNSUPPORTED_REMOTE' => '外部内容不受支持，不能导入',
    'PROVIDER_UNAVAILABLE' => '暂时无法读取外部数据',
    'REAUTH_REQUIRED' => '授权已过期，请重新连接',
    'INBOUND_DISABLED' => '入站未启用',
    'INBOX_RELATIONSHIP' => '收集箱关系冲突，无法采用外部版本',
    'NOT_FOUND' => '冲突已不存在',
    _ => '处理失败，请稍后重试',
  };
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

  bool get isReauthRequired => errorCode == 'REAUTH_REQUIRED';

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
