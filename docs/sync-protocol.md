# Sync protocol v2 and rollout

## Invariants

Flutter and CLI each own their local Drift database. Repositories atomically update local records and pending operations. Machine APIs and widgets share those repositories; the MCP adapter only runs the CLI.

The queue key still identifies user/module/entity. A mutation has a new local generation and a group ID. Changes to Topic relationships and ordering share a group. Sync freezes a group's payload and attempt ID before network I/O. Responses acknowledge only the uploaded generation, preserving later local edits. Receipt retries reuse the exact frozen payload.

Four fixed authenticated RPCs (`diurna_sync_inbox_v2`, `diurna_sync_calendar_v2`, `diurna_sync_diary_v2`, `diurna_sync_memos_v2`) perform atomic revision checks and writes. They are SECURITY INVOKER, retain RLS, use fixed tables/fields, and expose no arbitrary SQL. They are internal transport methods, not MCP tools. Tombstones prevent recreation of a deleted ID; receipts handle an uncertain network response.

`diurna_snapshot_v2` is one SQL statement with a consistent MVCC view. It returns a complete four-module snapshot, protocol, identity, generation and tombstones. Any malformed/incomplete/error response prevents snapshot application. Snapshot writes do not enqueue local operations. Pending/conflicting records remain protected from remote replacement.

Realtime subscribes only to the current user's RLS-protected signal row. A trigger changes its generation for INSERT/UPDATE/DELETE in the four business tables. The client debounces for 500 ms, deduplicates generations, and joins active synchronization. Resume, reconnect and a foreground 60-second fallback repair missed notifications. iOS background suspension cannot guarantee immediate delivery.

## Migration order

Back up server data and local database files, and verify restoration before production rollout. Test the scripts on a disposable Supabase project or isolated PostgreSQL instance first.

1. Apply `20260905000001_add_versioned_sync.sql` (additive revisions, metadata, snapshot and write RPCs).
2. Apply `20260905000002_enable_remote_sync_signals.sql` (signals, RLS and publication).
3. Prepare upgraded Windows, Web and iOS clients.
4. Apply `20260905000003_enforce_sync_protocol_v2.sql` and roll out upgraded clients together. The protocol guard rejects old unconditional writes; old clients retain their local queue until upgrade.

There is no safe guarantee of conflict protection while old clients are still allowed unconditional writes. Treat the pre-enforcement period as deployment preparation, not the completed rollout. A new clean installation uses `schema.sql`, which includes protocol v2 and later additive objects. Do not run the `20260711000001` / `20260711000002` destructive historical migrations on existing user data.

`20260908120000_add_external_integrations.sql` is additive (connection metadata, private `integrations` schema). It does not alter v2 RPCs, revisions or signals. External Notion/Google export is not part of the Drift pending queue; see [external-integrations](external-integrations.md).

Inbound (existing-item reverse UPDATE only) is also additive and does not rewrite v2 objects:

1. `20260909120000_add_external_inbound_sync.sql`
2. `20260909130000_accept_inbound_event.sql`
3. `20260909140000_inbound_maintenance.sql`
4. `20260909150000_inbound_review_fixes.sql`

These three are **not** on the hosted project yet. Inbound applies go through `integrations.apply_external_change`, never `diurna_sync_*_v2` or PostgREST business-table updates. Baseline-equal bootstrap must not bump `revision` or `diurna_sync_signals`. After the first hosted apply, those migration files are immutable; further changes need a new additive migration. Operator order and rollback: [external-bidirectional-sync](external-bidirectional-sync.md).

Drift v4→v5 adds queue generation/group fields and sync metadata. Pending v4 operations with unknown baseline use expected revision -1 and become retained conflicts rather than silently taking the latest remote version. Legacy v1/v2 tasks are mapped to Inbox without deleting the original `local_tasks` table. Old calendar date-range rows and queue payloads are retained in `legacy_calendar_events` / `legacy_pending_sync_operations`; extra old fields are also included in the migrated note. Unsupported retired tasks operations are retained as legacy conflicts.

Keep metadata/tombstones/receipts during rollback. Prefer a corrected client release to removing the protocol guard. Do not erase a failed attempt's receipt or discard queues to make synchronization appear successful.

## Verification

`supabase/tests/protocol_v2.sql` runs in a rolled-back transaction using two authenticated identities. It checks RLS, exact retry receipts, stale revision conflicts, protocol rejection, deletion protection and signal generation. `scripts/test-sync.ps1` then runs export and inbound suites (`integrations.sql`, `integrations_inbound.sql`, `integrations_google_inbound.sql`, `integrations_phase4.sql`) on the same isolated database.

Use `scripts/test-sync.ps1` only with the explicitly named loopback test database. The repository's local test cluster, when used, lives under ignored `.diurna/test-postgres`; it is not the user's production database.

Before real rollout, verify disposable real Supabase accounts: CLI login/refresh/logout, two-user isolation, initial snapshot above 1,000 records, Topic/reorder atomicity and WebSocket signal delivery. Confirm Windows/Web foreground refresh, iOS foreground/resume, and editor draft protection. Local mocks and PostgreSQL-role tests cannot establish those hosted/platform checks.

## Known operational limits

- Snapshot transport is full-state, not incremental. Oversized responses/timeouts fail safely and retain data; profile growth may justify incremental sync later.
- Session persistence and the CLI bundle currently target Windows. Flutter's existing platforms remain independent.
- CLI request-ID deduplication is profile-local; do not switch/delete profiles to retry uncertain creates.
- Conflict resolution is explicit; no background overwrite policy is enabled.
