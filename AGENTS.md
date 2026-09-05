# Developing Diurna

Diurna uses Flutter, Riverpod, Drift and Supabase. Keep Windows, Web and iOS behavior compatible. Preserve Memo manual save and save/discard/cancel navigation; do not redesign product UI as part of infrastructure work.

## Code boundaries

- `packages/diurna_core`: pure Dart database, repositories, contracts, application service and synchronization. No Flutter imports.
- `lib`: Flutter platform database creation, Riverpod wiring and UI. Existing data import paths export the shared core.
- `packages/diurna_cli`: Windows profile/authentication, compiled JSON CLI. Uses its own database, never the Flutter database file.
- `mcp`: official TypeScript MCP SDK v1 stdio adapter. Calls the compiled CLI with strict inputs and no shell. No business logic or database access here.
- `skills/diurna/SKILL.md`: agent guidance for user-data operations, not development instructions.

UI and machine writes go through the same Repository/DiurnaService rules. Preserve transactions that change local rows and enqueue pending operations together. No arbitrary SQL, table or JSON patch tools. Internal typed storage/sync SQL is not a public Agent interface.

## Synchronization and identity

Local-first means Drift → pending queue → SyncService → Supabase; network failure must not discard local writes. Protocol v2 freezes uploads by attempt ID, checks expected revision, acknowledges only the uploaded generation and retains conflicts. Inbox relationship changes and reorder writes are atomic groups.

Realtime is an invalidation signal, not a database payload merge. Subscribe to the authenticated user's `diurna_sync_signals`; debounce and reuse SyncService. Never create a write-on-pull loop. Preserve resume and reconnect recovery.

Use authenticated Supabase sessions and `auth.uid() = user_id` RLS. Never configure service_role/secret keys for CLI/MCP. Never log tokens or store passwords in scripts. CLI session is DPAPI-encrypted in the current Windows user's profile; respect account/project isolation and the profile lock.

## Migrations

Drift is schema v5. Keep database names, paths and user IDs stable. Increment schema version for storage changes; add tests with historical SQL fixtures. Preserve legacy rows and pending payloads. Never reintroduce destructive test-only table rebuilds.

For Supabase changes, add a migration and update `supabase/schema.sql` for clean installs. Do not re-run the 20260711 destructive migrations on existing user data. Follow `docs/sync-protocol.md` rollout order. Activating the v2 guard deliberately blocks old-client uploads; their local queue must survive until upgrade.

Generate Drift code only from the core package:

```powershell
Set-Location packages/diurna_core
dart pub get
dart run build_runner build
dart analyze
dart test
```

Do not hand-edit `app_database.g.dart`. The old Flutter location is an export, not a second implementation.

## Verification

From the CLI package: `dart pub get`, `dart analyze`, `dart build cli -o build --target bin/diurna.dart`, then `dart test`. The runtime tests require the compiled bundle and Windows. Ship the entire bundle (including `lib`), not only the EXE. `dart compile exe` cannot bundle SQLite build hooks.

From `mcp`: `npm ci`, `npm run typecheck`, `npm test`, `npm run build`. Stdio tests invoke the compiled CLI with an isolated temporary profile.

From the root: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build windows --release`, `flutter build web --release --dart-define-from-file=.env`. On macOS also run `flutter build ios --release --no-codesign`.

SQL tests use an explicitly isolated PostgreSQL database and authenticated roles. Never point test scripts at production. See `scripts/test-sync.ps1`.

Automated tests and builds do not establish iOS device behavior or production Realtime delivery. Record unperformed platform checks in the handoff. Pushing `main` triggers Cloudflare Pages deployment; do not push or deploy merely to validate a change.
