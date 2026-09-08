# Implementation verification

## Settings and visual styles — 2026-09-08

Authenticated clients open **设置** from the diary-panel gear on the four-panel desktop, or from the inbox header in Web style. The page holds theme choice and **外部连接**.

Themes:

- **复古**: existing Win32-like four-panel desktop.
- **现代风格**: the same four-panel layout with slate headers, rounded hairline panels and a cool workspace.
- **Web 风格**: Material navigation (the former Flutter-native pages). A stored `material` preference is read as Web style.

Windows defaults to 复古; Web and iOS default to Web 风格. The choice is local (`shared_preferences`), not synced. Wide Web can use the four-panel desktop when 复古 or 现代风格 is selected.

Still not certified: live visual QA on iOS, and Web theme switching on a phone-sized viewport.

## External integrations — 2026-09-08

Manual one-way Notion and Google Calendar export is in the working tree: Flutter **外部连接** UI, Edge Functions `integrations` and `integrations-oauth-callback`, additive SQL `20260908120000_add_external_integrations.sql`, and isolated SQL tests. Protocol v2 objects were not rewritten. Flutter does not read provider tokens.

Live project `diurna` (`yuhnjgflxieiewzdodoa`): historical migrations were recorded as applied without re-executing `20260711` SQL; only the integrations migration was applied. Both functions are deployed (`integrations` JWT on, OAuth callback JWT off). Operator secrets were set in the Dashboard (values not in git).

Windows Release client: the authenticated user connected Notion and Google Calendar, ran **立即同步** on both, and confirmed the remote `Diurna` Notion page/databases and Google `Diurna` calendar. This commit deploys the Web client via Cloudflare Pages (**设置** → **外部连接**).

Still not certified:

- iOS build and iOS OAuth/sync were not run (Windows host).
- Hosted Realtime timing was not re-measured.
- CLI/MCP have no provider OAuth commands (intentional).
- No cron, bidirectional merge or remote hard-delete.

See [external-integrations](external-integrations.md).

## Machine interface — 2026-09-05

### Delivered in the working tree

Shared pure Dart repositories, application service and versioned local-first synchronization; independent Windows CLI bundle with DPAPI session and JSON commands; 20-tool TypeScript stdio MCP adapter; Realtime invalidation and conflict view; additive SQL migrations; Skill and AGENTS development guidance.

The Flutter import locations export the shared core. Its database name and platform initialization remain unchanged. Generated Drift code now lives in diurna_core.

### Verified locally

| Check | Result |
|---|---|
| Core `dart analyze` / `dart test` | Clean / 32 passed |
| CLI `dart analyze` / `dart test` | Clean / 5 passed |
| CLI `dart build cli -o build --target bin/diurna.dart` | Bundle generated |
| MCP `npm run typecheck` / `npm test` | Clean / 3 passed, including actual stdio → compiled CLI |
| Flutter `flutter analyze --no-pub` / `flutter test --no-pub` | Clean / 24 passed |
| Windows Release build | Passed |
| Web Release build with existing .env | Passed; existing Cupertino font warning emitted |
| Skill quick_validate.py | Passed |
| Isolated PostgreSQL fresh schema and protocol tests | Passed |

SQL tests cover two-user RLS, replay receipts, revision conflicts, old-client rejection, tombstones, signals, a 1,001-record snapshot and group atomic rejection. All test rows are rolled back. Core tests cover migration preservation, concurrent clients, mutation during ACK, realtime dedupe and failure backoff. The intentional two-database concurrency test emits Drift's multiple-instance warning; the databases use separate in-memory executors.

CLI runtime tests use a loopback mock Auth/RPC server and temporary encrypted profiles. They cover refresh, online create/update/search, upload failure retaining the local entity, offline cache and process lock. These are not hosted Supabase authentication tests.

### Rollout and remaining acceptance

Protocol v2 incremental migrations were applied to the live Supabase project, in the order in sync-protocol.md. CLI login and snapshot sync against that project succeeded for an authenticated user: `pendingCount` was 0, no conflicts, and existing Inbox / Memo / Diary rows were readable. Codex and Grok Build stdio MCP servers were pointed at the production CLI profile (`%LOCALAPPDATA%\DiurnaAgent`). A disposable hosted test project was used first to prove CLI create/upload before touching live data.

The Windows Release client was rebuilt (`build/windows/x64/runner/Release`, AOT snapshot `data/app.so`). The existing user Startup shortcut still targets that folder, so a reboot launches this client. Old clients cannot upload after the protocol-enforcement migration.

This commit publishes the machine interface. Pushing `main` deploys the upgraded Web client via Cloudflare Pages. MCP host config, CLI sessions and `.env` stay on the local machine and are not in git.

Still not a complete production certification:

- iOS build on macOS; unavailable on this Windows host. iOS resume after background suspension was not tested.
- Foreground Realtime delivery timing on Windows/Web/iOS was not measured as a timed acceptance.
- Two-client Topic/reorder conflict tests on hosted Supabase were not repeated beyond local and isolated SQL tests.
- Device/editor conflict and retained-draft smoke tests beyond existing save/discard/cancel coverage.

Known differences from the plan: use `dart build cli` because SQLite native assets require a bundle; create-request deduplication is profile-local; unknown legacy pending baselines are conservatively retained as conflicts (including identical payloads) rather than automatically acknowledged. Retired legacy task payloads remain available in backup tables for explicit recovery. See machine-interface.md for setup and operational limits.
