-- Additive external integrations (Notion / Google). Do not touch protocol v2 tables.
begin;

create schema if not exists integrations;
revoke all on schema integrations from public, anon, authenticated;
grant usage on schema integrations to postgres, service_role;

create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  status text not null check (status in ('pending', 'connected', 'error', 'disconnected')),
  provider_account_id text,
  display_name text,
  granted_scopes text[] not null default '{}',
  token_expires_at timestamptz,
  enabled_modules jsonb not null default '{"inbox":true,"memos":true,"diary":true}'::jsonb,
  container jsonb not null default '{}'::jsonb,
  last_sync_at timestamptz,
  last_sync_status text not null default 'never'
    check (last_sync_status in ('never', 'pending', 'success', 'partial', 'failed')),
  last_sync_summary jsonb not null default '{}'::jsonb,
  last_error text,
  last_seen_generation bigint,
  sync_start_generation bigint,
  sync_run_id uuid,
  sync_lease_until timestamptz,
  page_cursor jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create unique index if not exists integration_connections_one_active
  on public.integration_connections (user_id, provider)
  where status in ('pending', 'connected', 'error');

create index if not exists integration_connections_user_provider_idx
  on public.integration_connections (user_id, provider);

alter table public.integration_connections enable row level security;

revoke all on table public.integration_connections from public, anon, authenticated;
grant select on table public.integration_connections to authenticated;
grant select, insert, update, delete on table public.integration_connections to service_role, postgres;

drop policy if exists integration_connections_select_own on public.integration_connections;
create policy integration_connections_select_own
  on public.integration_connections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.external_sync_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  entity_type text not null check (
    entity_type in ('inbox_items', 'memos', 'diary_entries', 'calendar_events')
  ),
  entity_id uuid not null,
  external_id text not null,
  external_container_id text,
  last_synced_revision bigint not null,
  content_hash text,
  last_synced_at timestamptz,
  sync_status text not null default 'synced'
    check (sync_status in ('synced', 'error', 'skipped')),
  last_error text,
  unique (connection_id, entity_type, entity_id),
  unique (connection_id, external_id),
  foreign key (connection_id, user_id)
    references public.integration_connections (id, user_id)
);

create index if not exists external_sync_links_user_provider_type_idx
  on public.external_sync_links (user_id, provider, entity_type);
create index if not exists external_sync_links_connection_entity_idx
  on public.external_sync_links (connection_id, entity_id);

alter table public.external_sync_links enable row level security;

revoke all on table public.external_sync_links from public, anon, authenticated;
grant select on table public.external_sync_links to authenticated;
grant select, insert, update, delete on table public.external_sync_links to service_role, postgres;

drop policy if exists external_sync_links_select_own on public.external_sync_links;
create policy external_sync_links_select_own
  on public.external_sync_links
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists integrations.credentials (
  connection_id uuid primary key
    references public.integration_connections(id) on delete cascade,
  token_bundle_cipher text not null,
  token_bundle_nonce bytea not null,
  access_expires_at timestamptz,
  token_updated_at timestamptz not null default now(),
  refresh_lock_until timestamptz
);

revoke all on table integrations.credentials from public, anon, authenticated;
grant select, insert, update, delete on table integrations.credentials to postgres, service_role;

create table if not exists integrations.oauth_states (
  state text primary key,
  user_id uuid not null,
  provider text not null check (provider in ('notion', 'google')),
  code_verifier text,
  return_to text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists oauth_states_expires_idx
  on integrations.oauth_states (expires_at);

revoke all on table integrations.oauth_states from public, anon, authenticated;
grant select, insert, update, delete on table integrations.oauth_states to postgres, service_role;

commit;
