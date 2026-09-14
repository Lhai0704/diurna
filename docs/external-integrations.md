# External integrations (Notion / Google Calendar)

Diurna **export** plus reverse **inbound** create/update inside Diurna-managed provider containers. Protocol v2 is unchanged: local Drift still syncs to Supabase first. External providers are a separate Edge Function path.

Inbound architecture, state model, Flutter status UI and the hosted runbook live in [external-bidirectional-sync](external-bidirectional-sync.md). Further hosted changes still need explicit approval.

## What shipped (export)

- Notion: Inbox, Memo and Diary, on first sync as a `Diurna` page plus three databases.
- Google Calendar: all-day events on a `Diurna` calendar created with `calendar.app.created`.
- One active connection per user per provider.
- Connect, disconnect and **立即同步** from the Flutter **外部连接** page. After protocol v2 generation advances, or after local pending writes drain, the Flutter session waits 1 minute then one-way exports connected providers. Google access tokens are refreshed automatically; a 401 after refresh becomes `REAUTH_REQUIRED` and does not retry every minute. The 60-second cloud poll does not start an export by itself.

## Inbound (hosted)

The same **外部连接** page also shows inbound status (`disabled` / `bootstrapping` / `active` / `degraded` / `error`), last inbound activity, safe error codes, open conflict counts and remote-deleted / unsupported-content / timed-event labels. Google `degraded` means push failed; timed repair can still sync linked events. Open conflicts have **查看冲突** with explicit 使用 Diurna / 使用外部. Flutter still never reads tokens, channel secrets, ciphertext or conflict snapshots.

Hosted inbound uses additive migrations `20260909120000`–`20260909190000` (applied and immutable), functions `integrations-notion-webhook`, `integrations-google-webhook`, `integrations-inbound-worker`, `INTEGRATIONS_MAINTENANCE_SECRET`, a Notion webhook subscription and cron. See the runbook in [external-bidirectional-sync](external-bidirectional-sync.md).

Flutter never reads third-party tokens. Authenticated clients may `SELECT` their own `integration_connections`, `external_sync_links` and `external_sync_conflict_summaries` rows. Token ciphertext lives in the private `integrations` schema (not on the Data API).

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

Existing projects: apply only `supabase/migrations/20260908120000_add_external_integrations.sql` for **export**. Inbound migrations `20260909120000`–`20260909190000` are listed in [external-bidirectional-sync](external-bidirectional-sync.md); on the live project they are already applied and must not be re-run or edited. All of these files are additive and must not rewrite protocol v2 objects.

Once an inbound migration has been applied hosted, never edit it; add a new additive migration instead.

Do not re-run `20260711000001` / `20260711000002` on user data. New installs use `supabase/schema.sql`.

Keep the `integrations` schema off the Data API extra-schemas list.

### Edge Functions

Export: deploy `integrations` (`verify_jwt = true`) and `integrations-oauth-callback` (`verify_jwt = false`). Config is in `supabase/config.toml`. Inbound functions `integrations-notion-webhook`, `integrations-google-webhook` and `integrations-inbound-worker` are hosted (`verify_jwt = false`). After a Notion import/export mapping change, redeploy both `integrations` and `integrations-inbound-worker`.

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

## Remote-created objects

The repository now supports Google single-day all-day remote creation in the managed Diurna calendar and Notion Inbox/Memo/Diary page creation in the three managed data sources. Memo/Diary bodies must be losslessly representable as plain paragraphs; unsupported or incomplete pages defer safely and can retry after editing. Valid owned Diurna metadata restores missing links; otherwise an atomic transaction allocates a new local UUID and link. Remote deletes never hard-delete the local entity or create protocol tombstones.

This feature is hosted: additive migration `20260910000000_external_remote_create.sql`, `integrations` / `integrations-inbound-worker` / `integrations-notion-webhook`, and Notion `page.created` handling in the webhook function. No new secret is required. See [remote-create rollout](external-bidirectional-sync.md#remote-create-rollout).

## Out of scope for this version

Remote hard-delete/tombstone from the provider, Flutter polling of Notion/Google, unsupported timed/recurring imports, and iOS device checks. Automated tests do not prove hosted OAuth, Realtime, Google watches or Notion subscriptions. Export while the app is closed waits until a Flutter session sees the newer generation.
