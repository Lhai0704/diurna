# External integrations (Notion / Google Calendar)

One-way **export** from Diurna plus (in the working tree, not hosted yet) reverse **inbound** for already-linked objects. Protocol v2 is unchanged: local Drift still syncs to Supabase first. External providers are a separate Edge Function path.

Inbound architecture, state model, Flutter status UI and the hosted runbook live in [external-bidirectional-sync](external-bidirectional-sync.md). Do not start that rollout until it is explicitly approved.

## What shipped (export)

- Notion: Inbox, Memo and Diary, on first sync as a `Diurna` page plus three databases.
- Google Calendar: all-day events on a `Diurna` calendar created with `calendar.app.created`.
- One active connection per user per provider.
- Connect, disconnect and **立即同步** from the Flutter **外部连接** page. After protocol v2 generation advances, or after local pending writes drain, the Flutter session waits 1 minute then one-way exports connected providers. Google access tokens are refreshed automatically; a 401 after refresh becomes `REAUTH_REQUIRED` and does not retry every minute. The 60-second cloud poll does not start an export by itself.

## Inbound (repo only until rollout)

The same **外部连接** page also shows inbound status (`disabled` / `bootstrapping` / `active` / `degraded` / `error`), last inbound activity, safe error codes, open conflict counts and remote-deleted / unsupported-content / timed-event labels. Google `degraded` means push failed; timed repair can still sync linked events. There is no conflict resolver. Flutter still never reads tokens, channel secrets or ciphertext.

Hosted inbound needs additive migrations `20260909120000`–`20260909140000`, functions `integrations-notion-webhook`, `integrations-google-webhook`, `integrations-inbound-worker`, `INTEGRATIONS_MAINTENANCE_SECRET`, a Notion webhook subscription and cron. None of that is applied/deployed yet. See the runbook in [external-bidirectional-sync](external-bidirectional-sync.md).

Flutter never reads third-party tokens. Authenticated clients may `SELECT` their own `integration_connections` and `external_sync_links` rows. Token ciphertext lives in the private `integrations` schema (not on the Data API).

## Client entry

| Client | Where |
|---|---|
| Retro / modern desktop | Diary panel title bar, settings icon → `/settings` → **外部连接** |
| Web style | Collect inbox header, same settings icon |
| After OAuth | Browser lands on `/integrations/connected`, then return to **外部连接** (`/settings/integrations`) |

`尚未同步` means connected but no export yet. `同步成功` means the last export finished.

Notion's page picker is the public-integration consent screen. Existing notes do not need to be selected; first sync creates Diurna's own page.

Disconnect removes Diurna's connection row, encrypted tokens and link map. The remote Notion page and Google calendar stay.

## Operator setup

Do not put OAuth secrets, `INTEGRATION_TOKEN_KEY` or `SUPABASE_DB_URL` in git, `.env.example` or chat.

### Database

Existing projects: apply only `supabase/migrations/20260908120000_add_external_integrations.sql` for **export**. Inbound migrations are listed in [external-bidirectional-sync](external-bidirectional-sync.md) and must not be applied until that rollout is approved. All of these files are additive and must not rewrite protocol v2 objects.

Once an inbound migration has been applied hosted, never edit it; add a new additive migration instead.

Do not re-run `20260711000001` / `20260711000002` on user data. New installs use `supabase/schema.sql`.

Keep the `integrations` schema off the Data API extra-schemas list.

### Edge Functions

Export: deploy `integrations` (`verify_jwt = true`) and `integrations-oauth-callback` (`verify_jwt = false`). Config is in `supabase/config.toml`. Inbound functions are not deployed until the bidirectional runbook says so.

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
- Isolated SQL: `supabase/tests/integrations.sql` (export) plus inbound suites via `scripts/test-sync.ps1`
- Inbound: [external-bidirectional-sync](external-bidirectional-sync.md)

CLI and MCP do not connect or export to Notion/Google. Those stay on the Flutter session plus Edge Functions.

## Out of scope for this version

Remote hard-delete/tombstone from the provider, Flutter polling of Notion/Google, a conflict resolver UI, and iOS device checks. Automated tests do not prove hosted OAuth, Realtime, Google watches or Notion subscriptions. Export while the app is closed waits until a Flutter session sees the newer generation. Hosted inbound is blocked on the explicit §17 operator rollout.
