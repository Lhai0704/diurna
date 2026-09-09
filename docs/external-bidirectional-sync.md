# External bidirectional sync (Notion / Google Calendar inbound)

Repo-only until the hosted rollout in this document is explicitly approved. Protocol v2 is unchanged. Inbound writes never go through PostgREST business-table updates or `diurna_sync_*_v2`. They use `integrations.apply_external_change` (private schema, `db()` Postgres).

Outbound one-way export is still Flutter-initiated. See [external-integrations](external-integrations.md).

## Scope

- Reverse sync is **UPDATE of already-linked objects only**. No remote create into Diurna, no hard-delete/tombstone from remote.
- Flutter does not poll Notion or Google. Thin webhooks authenticate, dedup and enqueue; the inbound worker fetches and applies.
- Conflicts are explicit (`external_sync_conflicts`). `inbound_state` is separate from outbound `sync_status`.
- Users resolve an open conflict explicitly as **使用 Diurna** or **使用外部**. The resolver never silently picks a side. Flutter never reads snapshots, tokens, or `remote_version`.

## Architecture

```text
provider webhook
  → authenticate / dedup (inbound_events)
  → enqueue inbound_work (rerun_requested coalescing)
  → integrations-inbound-worker
  → provider fetch
  → integrations.apply_external_change | bootstrap_link_version | freeze_link_conflict
```

Loop prevention: same-transaction `last_synced_revision` bump, mapped-field no-op, exporter skip of freeze/conflict/`remote_deleted` inbound states.

Flutter may `SELECT` its own `integration_connections`, `external_sync_links` and `external_sync_conflict_summaries` rows (no snapshots). Conflict resolve goes through the authenticated `integrations` function (`list_conflicts`, `resolve_conflict`). It must not read:

- OAuth access/refresh tokens
- Notion verification token
- Google channel token
- ciphertext / nonce
- `INTEGRATIONS_MAINTENANCE_SECRET`

Those stay in the private `integrations` schema (not on the Data API).

## Connection inbound_status

```text
disabled → bootstrapping → active
                         ↘ degraded
              reauth / calendar gone → error
disconnect → disabled
```

| State | Meaning |
|---|---|
| `disabled` | Authoritative inbound OFF. Webhooks ignored; no work, `outbound_hold`, or `inbound_delta_hold`; cron/maintenance never bootstraps or repairs. Outbound export continues. Promote only with explicit `activate_inbound`. Also the post-disconnect state. |
| `bootstrapping` | Baseline compare in progress (after explicit activation, or stuck-work recovery of an already-bootstrapping connection) |
| `active` | Baseline done and (for Google) watch usable |
| `degraded` | Watch/push failed or transient outage; **cron repair still works**; connection is not unusable |
| `error` | `REAUTH_REQUIRED` or calendar gone |

One conflicted link does not disable the connection.

## Google

- Persist watch as `creating` → `events.watch` → store `resource_id` / `expires_at` as `active` → old watch `retiring` → `channels.stop` only after the new watch is usable.
- Overlap of old and new channels is required. Duplicate pushes are coalesced.
- Failed `channels.stop` does not fail the new watch; cleanup retries after 1 hour.
- Renew when `expires_at < now() + 36 hours`. Do not renew every worker tick. Skip if a `creating` row exists.
- Bootstrap: existing `container.calendar_id`, full `events.list`, mapped compare, equal → `inbound_state=ready` with **no revision/signal bump**, drift/timed/recurring/missing → explicit conflict. `nextSyncToken` only after the compare pass. Watch after baseline. `inbound_status=active` only after bootstrap result is complete (watch failure → `degraded`).
- Repair: incremental `events.list(syncToken)` on the same `google_incremental` work as webhooks (one sync-token stream per connection). Cadence 15 minutes when `active` or `degraded`.

## Notion

- Same paragraph-only lossless import as normal inbound. Unsupported body freezes the link (`unsupported_content`).
- Bootstrap uses that same compare. Never treat the Notion `Revision` property as authoritative.
- Repair is **not** a Calendar-style cursor. Bounded `data_sources.query` with `last_edited_time on_or_after last_inbound_at - 5 minutes`, max 3 pages per data source, then the same `notion_page` work as webhooks. Cadence 15 minutes.

## Flutter status UI

**外部连接** shows, for a connected provider:

- 入站未启用 / 正在建立入站基线 / 入站正常 / 入站降级 / 入站错误
- last inbound time and a short result label
- safe inbound error codes (`WATCH_FAILED`, `CALENDAR_GONE`, …)
- open conflict count, remote-deleted count
- reason labels such as 不支持的 Notion 正文 / 不支持的定时事件

Google `degraded` text says push is down and **timed repair still syncs linked events**; it does not say the connection is unusable. Token-like strings are not rendered.

Open conflicts open **查看冲突**. Each row shows provider, module, reason, optional date, mapped field categories (not values), and two actions:

- **使用 Diurna**: re-fetch the live provider object. If it still differs, PATCH the existing remote (never create). Only after that write succeeds, set `last_synced_revision` to the current local revision (no local bump), `inbound_state=ready`, `resolved_local`. If live state already equals local, skip the provider write. If the remote is gone, keep the Diurna row, set `inbound_state=remote_deleted` / `outbound_hold=true`, `resolved_local`. Do not recreate a deleted remote.
- **使用外部**: re-fetch live provider state and apply it through `integrations.finish_conflict_use_remote` (not a PostgREST business update). Mapped change → local revision +1 once and `last_synced_revision` follows. Equal mapped state → no revision bump. `unsupported_content` / timed / recurring → error, conflict stays open. Remote gone → no local hard-delete; freeze as `remote_deleted` and `resolved_remote`.

If local revision changed since the conflict row was recorded, return `STALE_CONFLICT` and require a fresh decision. Echo prevention is the same as inbound: `last_synced_revision` equals local revision so outbound export skips.

## Isolated tests

`scripts/test-sync.ps1` on a loopback database named `*_test`:

1. `supabase/tests/bootstrap.sql`
2. `supabase/schema.sql`
3. `supabase/tests/protocol_v2.sql`
4. `supabase/tests/integrations.sql`
5. `supabase/tests/integrations_inbound.sql`
6. `supabase/tests/integrations_google_inbound.sql`
7. `supabase/tests/integrations_phase4.sql`
8. `supabase/tests/integrations_review_fixes.sql`
9. `supabase/tests/integrations_inbound_activation.sql`
10. `supabase/tests/integrations_inbound_date_baseline.sql`
11. `supabase/tests/integrations_conflict_resolution.sql`

Deno: `npx --yes deno@2.1.4 test supabase/functions/_shared --allow-env`.

## Hosted rollout (do not start until explicitly approved)

Live project remains `diurna` (`yuhnjgflxieiewzdodoa`). Do not point test scripts at it.

### Migration freeze

Hosted state on `diurna` (`yuhnjgflxieiewzdodoa`):

- **Applied and immutable:** `20260909120000`–`20260909180000`
- **Review-only, not hosted yet:** `20260909190000_external_conflict_resolution.sql`

Never edit an already-applied migration. Create a new additive file instead.

```text
never edit an already-applied migration
→ create a new additive migration instead
```

Filenames stay unique 14-digit versions. Do not rewrite protocol v2 tables. Do not re-run `20260711000001` / `20260711000002`.

### Exact order

```text
final local verification
→ hosted migration
→ deploy functions
→ set maintenance secret
→ create/verify Notion webhook
→ configure cron
→ verify all existing production connections remain disabled/untouched
→ explicitly activate ONE disposable/test connection
→ verify bootstrap/watch/inbound/conflicts
→ explicitly activate selected production connections gradually
```

Cron and webhooks must **not** bootstrap `inbound_status=disabled` connections. Activate one connection at a time:

```text
POST /functions/v1/integrations-inbound-worker
Header: x-diurna-maintenance: <INTEGRATIONS_MAINTENANCE_SECRET>
Body: {"action":"activate_inbound","connection_id":"<uuid>"}
```

Disable inbound without disconnecting outbound export:

```text
Body: {"action":"deactivate_inbound","connection_id":"<uuid>"}
```

SQL equivalent (service role / postgres only):

```sql
select integrations.activate_inbound('<uuid>');
select integrations.deactivate_inbound('<uuid>');
```

SQL `deactivate_inbound` is DB-state only: it returns the connection to `disabled`, clears holds, and marks pending/processing inbound work done. It does **not** acquire the per-connection inbound lock, so it cannot wait for an in-flight `events.watch`, Notion PATCH, or other provider write, and it does not call Google `channels.stop`. Prefer the worker `deactivate_inbound` action, which takes the same lock as inbound work, then stops Google watches. Once that action returns, no previously running inbound operation for that connection can still create a watch or write to the provider.

### 1. Final local verification

From the repo: Flutter analyze/test, Deno check/test, isolated SQL (`scripts/test-sync.ps1`). Do not push `main` merely to validate (Pages deploys the Web client).

**Rollback:** none; local only.

### 2. Hosted migration

Apply **in this order**, additive, on a backup-verified project:

1. `20260909120000_add_external_inbound_sync.sql`
2. `20260909130000_accept_inbound_event.sql`
3. `20260909140000_inbound_maintenance.sql`
4. `20260909150000_inbound_review_fixes.sql`
5. `20260909160000_inbound_work_heartbeat.sql`
6. `20260909170000_inbound_activation_gate.sql`
7. `20260909180000_fix_inbound_date_baseline.sql` (not hosted yet)

`20260908120000_add_external_integrations.sql` is already on the live project.

Keep the `integrations` schema off the Data API extra-schemas list.

**Rollback:** restore the database backup taken immediately before this step. Do not drop protocol v2 objects. New inbound tables/functions can be left unused if functions are not deployed yet (inbound_status stays `disabled`).

### 3. Deploy Edge Functions

Deploy (JWT flags in `supabase/config.toml`):

| Function | verify_jwt | Role |
|---|---|---|
| `integrations` | true | existing export/OAuth/disconnect |
| `integrations-oauth-callback` | false | existing OAuth callback |
| `integrations-notion-webhook` | false | thin Notion webhook |
| `integrations-google-webhook` | false | thin Google webhook |
| `integrations-inbound-worker` | false | maintenance + fetch/apply |

Redeploying `integrations` is required so disconnect stops Google watches and sets `inbound_status=disabled`.

**Rollback:** redeploy the previous function bundle. Webhooks will 404 if the new functions are deleted; that is safe (no apply). Worker cron should be removed first if already enabled (step 6).

### 4. Secrets (names only; never put values in git, `.env` or chat)

Already required for export:

| Name | Notes |
|---|---|
| `INTEGRATION_TOKEN_KEY` | UTF-8 string; SHA-256 then AES-GCM |
| `NOTION_CLIENT_ID` / `NOTION_CLIENT_SECRET` | Notion OAuth |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `APP_ORIGIN` | Flutter web origin, no trailing slash |
| `SUPABASE_DB_URL` | Direct Postgres `5432`, not the pooler |

New for inbound:

| Name | Notes |
|---|---|
| `INTEGRATIONS_MAINTENANCE_SECRET` | Worker `x-diurna-maintenance` header. Non-empty. |
| `NOTION_WEBHOOK_SECRET` | Optional fallback if the handshake token is not in `integrations.webhook_secrets` |

Platform already injects `SUPABASE_URL` and anon / service-role keys.

**Rollback:** rotate/delete `INTEGRATIONS_MAINTENANCE_SECRET` to disable the worker. Do not log or paste values.

### 5. Notion webhook subscription

The public webhook URL has **no** secret in it:

```text
https://<project-ref>.supabase.co/functions/v1/integrations-notion-webhook
```

Arm a one-time setup nonce (maintenance auth). Logs never include the nonce or verification token:

```text
POST /functions/v1/integrations-inbound-worker
Header: x-diurna-maintenance: <INTEGRATIONS_MAINTENANCE_SECRET>
Body: {"action":"arm_notion_handshake","purpose":"initial"}
```

Register the webhook as `.../integrations-notion-webhook?setup=<setup_nonce>` only for that arm window. An unsolicited handshake without a valid unused nonce is rejected and cannot overwrite an active token. Rotation uses `"purpose":"rotate"`.

Reveal **once** if the Notion dashboard needs the verification token:

```text
POST /functions/v1/integrations-inbound-worker
Header: x-diurna-maintenance: <INTEGRATIONS_MAINTENANCE_SECRET>
Body: {"action":"reveal_notion_verification_token"}
```

The token is returned once (`revealed_at` set). Do not log it. Flutter never sees it.

**Rollback:** delete the Notion subscription. Encrypted handshake ciphertext can remain; it is unused without the subscription.

### 6. Cron

Schedule **every 1 minute**:

```text
POST https://<project-ref>.supabase.co/functions/v1/integrations-inbound-worker
Header: x-diurna-maintenance: <INTEGRATIONS_MAINTENANCE_SECRET>
Body: {}
```

The worker runs maintenance (purge 48h events, re-enqueue **already-bootstrapping** connections that lost bootstrap work, Google renew for `active`/`degraded`, 15-minute repair for `active`/`degraded`) then claims work. Enabling cron does **not** bootstrap `inbound_status=disabled` connections. Repair is a safety net, not the primary sync path. Do not run two independent Calendar sync-token streams.

**Rollback:** disable/delete the scheduled job. Pending `inbound_work` remains until the worker runs again.

### 7. Disposable / test connection bootstrap

Use a disposable Notion workspace and Google account, not production user data.

1. Connect from **外部连接** (existing OAuth).
2. Run **立即同步** so export links exist.
3. Confirm every existing production connection is still `inbound_status=disabled` with no inbound work.
4. Explicitly activate **only** this disposable connection (`activate_inbound` above). Cron must not have bootstrapped it.
5. Confirm **外部连接** shows 正在建立入站基线 then 入站正常 (or 入站降级 if Google watch failed but repair works).
6. Confirm equal linked rows did **not** bump `revision` or `diurna_sync_signals.generation`.

**Rollback:** `deactivate_inbound` on that test connection (keeps outbound export) or **断开** (also drops export). Disconnect stops watches, ignores inbound, deletes links/credentials. Remote Notion pages and Google calendars stay.

### 8. Verify Google watch

After successful Google bootstrap, `integrations.provider_watches` has an `active` row. A calendar change on a **linked** all-day event should enqueue `google_incremental` and apply or conflict explicitly. Timed/recurring events freeze the link. Do not create watches by hand.

**Rollback:** disconnect the test Google connection (stops channels). If a watch is orphaned, `channels.stop` with stored `channel_id` / `resource_id` from the private table (operator only; not Flutter).

### 9. Verify Notion inbound

Edit a linked paragraph-only page. Webhook → `notion_page` work → apply or `unsupported_content` freeze. Heading/bold/link bodies must not silently overwrite Diurna.

**Rollback:** disconnect the test Notion connection; delete the webhook subscription if abandoning inbound.

### 10. Inspect conflicts / no mass revision bump

- Open `external_sync_conflicts` for the test user: only explicit reasons.
- Baseline-equal links: `inbound_state=ready`, same `revision` as before bootstrap, `diurna_sync_signals.generation` unchanged by baseline-only work.
- **外部连接** shows 未处理冲突：N and reason labels. No resolver yet.

**Rollback:** none required if no production connection was bootstrapped. Leave test conflicts on the disposable user or disconnect.

### 11. Production bootstrap (last)

Only after the disposable path is green. Existing production connections stay `inbound_status=disabled` until each is **explicitly** activated. Do not activate all production connections in one step. Expect some `bootstrap_remote_drift` / `unsupported_content` / timed-event conflicts. That is success, not a reason to disable the whole connection.

**Rollback:** worker `deactivate_inbound` on that production connection (waits for in-flight inbound work, then stops Google watches). SQL-only `deactivate_inbound` is an emergency DB-state flip and cannot stop an already in-flight provider request. **断开** also drops export. Stopping cron prevents new apply. Do not rewrite Diurna rows to “undo” inbound; protocol v2 revisions must stay.

## After hosted apply

New inbound schema changes are a **new** additive migration. `20260909120000`–`20260909170000` are hosted and immutable. `20260909180000` is review-only until hosted; after that apply it is also immutable.
