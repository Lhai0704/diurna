# External integrations (Notion / Google Calendar)

Manual, one-way export from Diurna. Protocol v2 is unchanged: local Drift still syncs to Supabase first. External providers are a separate Edge Function path.

## What shipped

- Notion: Inbox, Memo and Diary, on first sync as a `Diurna` page plus three databases.
- Google Calendar: all-day events on a `Diurna` calendar created with `calendar.app.created`.
- One active connection per user per provider.
- Connect, disconnect and **立即同步** from the Flutter **外部连接** page. No cron, webhook, bidirectional merge or remote hard-delete.

Flutter never reads third-party tokens. Authenticated clients may `SELECT` their own `integration_connections` and `external_sync_links` rows. Token ciphertext lives in the private `integrations` schema (not on the Data API).

## Client entry

| Client | Where |
|---|---|
| Web | Collect inbox header, link icon, tooltip `外部连接` → `/settings/integrations` |
| Windows | Diary panel title bar, same icon |
| After OAuth | Browser lands on `/integrations/connected`, then return to **外部连接** |

`尚未同步` means connected but no export yet. `同步成功` means the last manual export finished.

Notion's page picker is the public-integration consent screen. Existing notes do not need to be selected; first sync creates Diurna's own page.

Disconnect removes Diurna's connection row, encrypted tokens and link map. The remote Notion page and Google calendar stay.

## Operator setup

Do not put OAuth secrets, `INTEGRATION_TOKEN_KEY` or `SUPABASE_DB_URL` in git, `.env.example` or chat.

### Database

Existing projects: apply only `supabase/migrations/20260908120000_add_external_integrations.sql`. It is additive and must not rewrite protocol v2 objects.

Do not re-run `20260711000001` / `20260711000002` on user data. New installs use `supabase/schema.sql`.

Keep the `integrations` schema off the Data API extra-schemas list.

### Edge Functions

Deploy `integrations` (`verify_jwt = true`) and `integrations-oauth-callback` (`verify_jwt = false`). Config is in `supabase/config.toml`.

OAuth redirect URI (exact):

```text
https://<project-ref>.supabase.co/functions/v1/integrations-oauth-callback
```

Register that URI on the Notion public integration and the Google **Web application** OAuth client.

Dashboard → Edge Functions → Secrets (names only):

| Name | Notes |
|---|---|
| `INTEGRATION_TOKEN_KEY` | Any non-empty UTF-8 string. Code SHA-256s it, then uses the digest as AES-GCM. Missing/empty throws `INTEGRATION_TOKEN_KEY is not configured`. |
| `NOTION_CLIENT_ID` / `NOTION_CLIENT_SECRET` | Notion public OAuth |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth |
| `APP_ORIGIN` | Flutter web origin with no trailing slash, e.g. `https://<pages-host>` |
| `SUPABASE_DB_URL` | Direct Postgres URI on port `5432`, not the pooler |

Platform already injects `SUPABASE_URL` and the anon / service-role keys.

Windows PowerShell generator for `INTEGRATION_TOKEN_KEY` (treat the Base64 as the UTF-8 secret, not as raw AES key bytes):

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes)
```

## Code map

- UI: `lib/features/integrations/`
- Authenticated actions: `supabase/functions/integrations`
- OAuth browser callback: `supabase/functions/integrations-oauth-callback`
- Token encrypt/decrypt: `supabase/functions/_shared/crypto.ts` (`importKey`)
- Isolated SQL: `supabase/tests/integrations.sql` via `scripts/test-sync.ps1`

CLI and MCP do not connect or export to Notion/Google. Those stay on the Flutter session plus Edge Functions.

## Out of scope for this version

Bidirectional sync, scheduled push, remote deletion on disconnect, and iOS device checks. Automated tests do not prove hosted OAuth or Realtime.
