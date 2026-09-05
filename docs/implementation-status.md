# Implementation verification — 2026-09-05

## Delivered in the working tree

Shared pure Dart repositories, application service and versioned local-first synchronization; independent Windows CLI bundle with DPAPI session and JSON commands; 20-tool TypeScript stdio MCP adapter; Realtime invalidation and conflict view; additive SQL migrations; Skill and AGENTS development guidance.

The Flutter import locations export the shared core. Its database name and platform initialization remain unchanged. Generated Drift code now lives in diurna_core.

## Verified locally

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

## Rollout and remaining acceptance

Protocol v2 incremental migrations were applied to the live Supabase project, in the order in sync-protocol.md. CLI login and snapshot sync against that project succeeded for an authenticated user: `pendingCount` was 0, no conflicts, and existing Inbox / Memo / Diary rows were readable. Codex and Grok Build stdio MCP servers were pointed at the production CLI profile (`%LOCALAPPDATA%\DiurnaAgent`). A disposable hosted test project was used first to prove CLI create/upload before touching live data.

The Windows Release client was rebuilt (`build/windows/x64/runner/Release`, AOT snapshot `data/app.so`). The existing user Startup shortcut still targets that folder, so a reboot launches this client. Old clients cannot upload after the protocol-enforcement migration.

This commit publishes the machine interface. Pushing `main` deploys the upgraded Web client via Cloudflare Pages. MCP host config, CLI sessions and `.env` stay on the local machine and are not in git.

Still not a complete production certification:

- iOS build on macOS; unavailable on this Windows host. iOS resume after background suspension was not tested.
- Foreground Realtime delivery timing on Windows/Web/iOS was not measured as a timed acceptance.
- Two-client Topic/reorder conflict tests on hosted Supabase were not repeated beyond local and isolated SQL tests.
- Device/editor conflict and retained-draft smoke tests beyond existing save/discard/cancel coverage.

Known differences from the plan: use `dart build cli` because SQLite native assets require a bundle; create-request deduplication is profile-local; unknown legacy pending baselines are conservatively retained as conflicts (including identical payloads) rather than automatically acknowledged. Retired legacy task payloads remain available in backup tables for explicit recovery. See machine-interface.md for setup and operational limits.
