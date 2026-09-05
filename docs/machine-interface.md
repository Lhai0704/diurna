# Diurna machine interface v1

## Build and connect

The Windows CLI runs independently of Flutter. Build with the repository's Dart SDK:

```powershell
Set-Location D:\Projects\diurna\packages\diurna_cli
dart pub get
dart build cli -o build --target bin/diurna.dart
```

Executable: `packages/diurna_cli/build/bundle/bin/diurna.exe`. Preserve the accompanying `bundle/lib` directory. SQLite uses Dart build hooks, so `dart compile exe` is not the supported packaging command.

Initial login, in a user-controlled terminal:

```powershell
$env:SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co'
$env:SUPABASE_ANON_KEY = 'YOUR-PUBLISHABLE-OR-ANON-KEY'
& .\build\bundle\bin\diurna.exe auth login --email you@example.com
& .\build\bundle\bin\diurna.exe auth status --json
```

Login prompts for a non-echoed password. No password flag exists. Publishable configuration is saved for subsequent calls; session data is encrypted with Windows DPAPI. Default profile root: `%LOCALAPPDATA%\DiurnaAgent`, with project-hash and user-ID isolation. `DIURNA_HOME` overrides the root for an explicitly separate profile (tests use this).

CLI login is separate from Flutter login. Logout retains cached data and pending writes. Do not copy session files between users/computers; authenticate independently. Neither CLI nor MCP accepts a service_role/secret key.

Build MCP with `npm ci` and `npm run build` in `mcp`. The server is stdio-only; it has no HTTP endpoint. Point every host at the compiled CLI and the same profile used for `auth login`. Do not put passwords, access tokens or `service_role` keys in MCP config.

```powershell
$repo = (Get-Location).Path   # repository root
$cli  = Join-Path $repo 'packages\diurna_cli\build\bundle\bin\diurna.exe'
$mcp  = Join-Path $repo 'mcp\dist\src\index.js'

# Grok Build
grok mcp add diurna `
  -e "DIURNA_CLI=$cli" `
  -e "DIURNA_HOME=$env:LOCALAPPDATA\DiurnaAgent" `
  -- node $mcp

# Codex
codex mcp add diurna `
  --env "DIURNA_CLI=$cli" `
  --env "DIURNA_HOME=$env:LOCALAPPDATA\DiurnaAgent" `
  -- node $mcp
```

Equivalent generic stdio config:

```json
{
  "mcpServers": {
    "diurna": {
      "command": "node",
      "args": ["<repo>/mcp/dist/src/index.js"],
      "env": {
        "DIURNA_CLI": "<repo>/packages/diurna_cli/build/bundle/bin/diurna.exe",
        "DIURNA_HOME": "%LOCALAPPDATA%\\DiurnaAgent"
      }
    }
  }
}
```

`DIURNA_HOME` must match the profile that ran `auth login`. The default production profile is `%LOCALAPPDATA%\DiurnaAgent`. A separate test profile (for example `DiurnaAgentTest`) keeps disposable data away from the live account. After changing MCP config, start a new Grok or Codex conversation so the tools load.

The 20 tool definitions are in `mcp/src/tools.ts`. It exposes no SQL, generic update, hard-delete or forced-conflict tool. Copy `skills/diurna` into the host skill directory (Grok: `%USERPROFILE%\.grok\skills\diurna`); the repository file alone does not auto-install it into every host.

## Commands and output

Run `diurna --help` for the complete command list. Data commands return JSON envelopes; `--json` is accepted explicitly for Agent scripts. Diagnostic output never shares JSON stdout. For multi-line text or strict machine calls, append `--input-json` and send one object to stdin. Do not combine stdin fields with CLI field arguments.

Examples (use the actual compiled executable or a local `diurna` alias):

```text
diurna calendar list --date 2026-09-05 --json
diurna calendar create --title "研究 Diurna MCP" --date 2026-09-06 --json
diurna search "研究 Diurna MCP" --json
diurna calendar complete <id> --version <returned-version> --json
diurna memo create --title "MCP Architecture" --content "CLI → MCP → Skill" --json
diurna memo get <id> --json
diurna memo update <id> --version <returned-version> --append-content "authentication details" --json
diurna diary list --from 2026-08-30 --to 2026-09-05 --json
diurna inbox archive <id> --version <returned-version> --json
```

`append-content` is verbatim: include a newline when desired. Updates require an exact ID and opaque version from the latest read. Unspecified fields remain unchanged; `null` clears supported nullable fields. Date ranges are inclusive; dates must be valid `YYYY-MM-DD`; timestamps include an offset or `Z`. Calendar `--date` and `--from/--to` are mutually exclusive. Metadata reports Asia/Shanghai and `today`.

Lists return `items`, `total`, `nextOffset`; default limit 50, maximum 200. Global search groups results into `inbox`, `calendar`, `memos`, `diary`, with summaries, IDs, versions, dates and status. It performs ordinary case-insensitive substring search; `%` and `_` are literal. Read full records before replacing content.

Envelope keys: `schemaVersion: 1`, `ok`, `data` on success or `error: {code,message}` on failure, plus `meta` with local-commit and sync state. Exit codes: 0 success; 1 unexpected internal failure; 2 invalid args/validation; 3 auth; 4 not found; 5 conflict; 6 sync/network; 7 profile busy; 8 protocol upgrade required.

Default behavior synchronizes before reads/writes and waits for upload after a write. An upload error may return `ok:false` with `localCommitted:true`, `entityId` and `operationId`. The mutation is retained locally: do not blindly create another record. `--offline` explicitly permits cached reads or queued writes and marks staleness. `sync now` retries retained operations; it does not bypass conflicts.

Create commands accept a UUID `--request-id`; reuse it for an uncertain retry. MCP generates one when omitted and returns it when execution is uncertain. Reusing a request ID with different content fails. CLI retains this deduplication in its profile database; do not delete that cache while reconciling an uncertain write.

Deletion exists only in the CLI and requires `delete <id> --version <version> --confirm-delete <same-id>`. There is no delete-by-search command.

## Conflicts

Use `sync conflicts`, `sync conflict get <id>`, then `sync conflict resolve <id> --use local|remote`. `remote` discards the conflict group's pending local writes. `local` rebases against a freshly read remote revision, and may conflict again if another client changes it. A remotely deleted existing entity is not silently resurrected. Copy retained content into a new entity if needed.

Flutter's sync icon displays conflict count and opens a comparison view. Draft saves rejected by version checking remain in the editor. Legacy task payloads stay in backup tables and can be copied into new Inbox records.

## Test boundaries

CLI tests exercise the compiled executable against a loopback mock Auth/RPC server, including refresh and failure modes. PostgreSQL tests separately exercise real RLS, transactions and the migration functions. Neither replaces testing real Supabase Auth, WebSocket delivery or Windows/Web/iOS foreground behavior with disposable test accounts. See `docs/sync-protocol.md` before deployment.
