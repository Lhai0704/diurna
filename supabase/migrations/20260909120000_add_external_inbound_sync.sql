-- Additive inbound sync. Does not rewrite protocol v2 or 20260908120000 objects.
begin;

alter table public.integration_connections
  add column if not exists inbound_status text not null default 'disabled',
  add column if not exists last_inbound_at timestamptz,
  add column if not exists last_inbound_result text,
  add column if not exists inbound_error text;

alter table public.integration_connections
  drop constraint if exists integration_connections_inbound_status_check;
alter table public.integration_connections
  add constraint integration_connections_inbound_status_check
  check (inbound_status in ('disabled', 'bootstrapping', 'active', 'degraded', 'error'));

alter table public.external_sync_links
  add column if not exists inbound_state text not null default 'idle',
  add column if not exists external_etag text,
  add column if not exists external_updated_at timestamptz,
  add column if not exists last_remote_event_at timestamptz;

alter table public.external_sync_links
  drop constraint if exists external_sync_links_inbound_state_check;
alter table public.external_sync_links
  add constraint external_sync_links_inbound_state_check
  check (inbound_state in ('idle', 'ready', 'conflict', 'remote_deleted', 'error'));

create table if not exists public.external_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  entity_type text not null check (
    entity_type in ('inbox_items', 'memos', 'diary_entries', 'calendar_events')
  ),
  entity_id uuid not null,
  external_id text not null,
  status text not null default 'open'
    check (status in ('open', 'resolved_local', 'resolved_remote', 'dismissed')),
  reason text not null,
  local_revision bigint not null,
  last_synced_revision bigint not null,
  local_snapshot jsonb not null,
  remote_snapshot jsonb not null,
  remote_version text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (connection_id, user_id)
    references public.integration_connections (id, user_id)
);

create unique index if not exists external_sync_conflicts_one_open
  on public.external_sync_conflicts (connection_id, entity_type, entity_id)
  where status = 'open';

create index if not exists external_sync_conflicts_user_idx
  on public.external_sync_conflicts (user_id, status);

alter table public.external_sync_conflicts enable row level security;

revoke all on table public.external_sync_conflicts from public, anon, authenticated;
grant select on table public.external_sync_conflicts to authenticated;
grant select, insert, update, delete on table public.external_sync_conflicts to service_role, postgres;

drop policy if exists external_sync_conflicts_select_own on public.external_sync_conflicts;
create policy external_sync_conflicts_select_own
  on public.external_sync_conflicts
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists integrations.provider_watches (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('google')),
  channel_id text not null,
  resource_id text,
  channel_token text not null,
  sync_token text,
  calendar_id text,
  status text not null default 'creating'
    check (status in ('creating', 'active', 'retiring', 'expired', 'error')),
  expires_at timestamptz,
  last_message_number bigint,
  last_notification_at timestamptz,
  last_incremental_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (channel_id)
);

create index if not exists provider_watches_expiry_idx
  on integrations.provider_watches (expires_at)
  where status in ('creating', 'active');
create index if not exists provider_watches_connection_idx
  on integrations.provider_watches (connection_id, status);

revoke all on table integrations.provider_watches from public, anon, authenticated;
grant select, insert, update, delete on table integrations.provider_watches to postgres, service_role;

create table if not exists integrations.inbound_events (
  provider text not null,
  event_key text not null,
  connection_id uuid,
  result text not null,
  created_at timestamptz not null default now(),
  primary key (provider, event_key)
);

create index if not exists inbound_events_created_idx
  on integrations.inbound_events (created_at);

revoke all on table integrations.inbound_events from public, anon, authenticated;
grant select, insert, update, delete on table integrations.inbound_events to postgres, service_role;

create table if not exists integrations.inbound_work (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  work_type text not null check (work_type in (
    'notion_page', 'google_incremental', 'google_full',
    'google_calendar_gone', 'bootstrap_notion', 'bootstrap_google', 'repair'
  )),
  dedup_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'error')),
  rerun_requested boolean not null default false,
  latest_event_at timestamptz not null default now(),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  locked_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists inbound_work_inflight_dedup
  on integrations.inbound_work (connection_id, work_type, dedup_key)
  where status in ('pending', 'processing');
create index if not exists inbound_work_claim_idx
  on integrations.inbound_work (available_at)
  where status = 'pending';
create index if not exists inbound_work_lock_idx
  on integrations.inbound_work (locked_until)
  where status = 'processing';

revoke all on table integrations.inbound_work from public, anon, authenticated;
grant select, insert, update, delete on table integrations.inbound_work to postgres, service_role;

create table if not exists integrations.webhook_secrets (
  provider text not null,
  kind text not null,
  cipher text not null,
  nonce bytea not null,
  revealed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, kind)
);

revoke all on table integrations.webhook_secrets from public, anon, authenticated;
grant select, insert, update, delete on table integrations.webhook_secrets to postgres, service_role;

create or replace function integrations._allowed_patch_keys(p_entity_type text)
returns text[]
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case p_entity_type
    when 'inbox_items' then array['content','item_type','inbox_column','is_completed','is_pinned','is_archived','is_topic']
    when 'memos' then array['title','content']
    when 'diary_entries' then array['title','content','entry_date','mood']
    when 'calendar_events' then array['title','event_date','note']
    else array[]::text[]
  end;
$$;

create or replace function integrations._patch_equals_row(
  p_row jsonb,
  p_patch jsonb
) returns boolean
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare k text;
begin
  if p_patch is null or p_patch = '{}'::jsonb then
    return true;
  end if;
  for k in select jsonb_object_keys(p_patch)
  loop
    if jsonb_typeof(p_patch->k) = 'null' then
      if p_row->>k is not null then
        return false;
      end if;
    elsif jsonb_typeof(p_patch->k) = 'boolean' then
      if (p_row->>k)::boolean is distinct from (p_patch->>k)::boolean then
        return false;
      end if;
    elsif (p_row->>k) is distinct from (p_patch->>k) then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create or replace function integrations._open_conflict(
  p_user_id uuid,
  p_connection_id uuid,
  p_provider text,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_reason text,
  p_local_revision bigint,
  p_last_synced_revision bigint,
  p_local_snapshot jsonb,
  p_remote_snapshot jsonb,
  p_remote_version text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  insert into public.external_sync_conflicts (
    user_id, connection_id, provider, entity_type, entity_id, external_id,
    status, reason, local_revision, last_synced_revision,
    local_snapshot, remote_snapshot, remote_version
  ) values (
    p_user_id, p_connection_id, p_provider, p_entity_type, p_entity_id, p_external_id,
    'open', p_reason, p_local_revision, p_last_synced_revision,
    coalesce(p_local_snapshot, '{}'::jsonb),
    coalesce(p_remote_snapshot, '{}'::jsonb),
    p_remote_version
  )
  on conflict (connection_id, entity_type, entity_id) where status = 'open'
  do update set
    reason = excluded.reason,
    local_revision = excluded.local_revision,
    last_synced_revision = excluded.last_synced_revision,
    local_snapshot = excluded.local_snapshot,
    remote_snapshot = excluded.remote_snapshot,
    remote_version = excluded.remote_version;
end;
$$;

create or replace function integrations.apply_external_change(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_operation text,
  p_patch jsonb,
  p_remote_snapshot jsonb,
  p_provider_etag text,
  p_provider_updated_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
  next_revision bigint;
  generation_after bigint;
  allowed text[];
  patch_key text;
  mapped_equal boolean;
  incoming_updated timestamptz;
  stored_updated timestamptz;
  result_code text;
begin
  if p_operation is null or p_operation not in ('update', 'remote_deleted') then
    raise exception 'VALIDATION';
  end if;
  if p_entity_type is null or p_entity_type not in (
    'inbox_items', 'memos', 'diary_entries', 'calendar_events'
  ) then
    raise exception 'VALIDATION';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'VALIDATION';
  end if;
  allowed := integrations._allowed_patch_keys(p_entity_type);
  for patch_key in select jsonb_object_keys(p_patch)
  loop
    if not patch_key = any(allowed) then
      raise exception 'UNKNOWN_FIELD';
    end if;
  end loop;

  perform set_config('diurna.sync_protocol', '2', true);

  select * into conn
    from public.integration_connections
   where id = p_connection_id
     for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  if conn.inbound_status not in ('active', 'bootstrapping', 'degraded') then
    return jsonb_build_object('result', 'ignored', 'reason', 'inbound_disabled');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));

  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  if link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'external_id_mismatch');
  end if;
  if link.inbound_state = 'conflict' then
    return jsonb_build_object(
      'result', 'conflict',
      'reason', 'already_conflict',
      'revision_before', null,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;

  if current_row is null then
    if exists (
      select 1 from public.diurna_sync_tombstones
       where user_id = conn.user_id
         and entity_type = p_entity_type
         and entity_id = p_entity_id
    ) then
      return jsonb_build_object('result', 'ignored', 'reason', 'tombstone');
    end if;
    return jsonb_build_object('result', 'ignored', 'reason', 'missing_entity');
  end if;

  current_revision := (current_row->>'revision')::bigint;
  incoming_updated := p_provider_updated_at;
  stored_updated := link.external_updated_at;
  mapped_equal := integrations._patch_equals_row(current_row, p_patch);

  if p_operation = 'remote_deleted' then
    if current_revision > link.last_synced_revision then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'remote_deleted_with_local_edit', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict',
             last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'remote_deleted_with_local_edit',
        'revision_before', current_revision,
        'revision_after', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    update public.external_sync_links
       set inbound_state = 'remote_deleted',
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where id = link.id;
    return jsonb_build_object(
      'result', 'remote_deleted',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if link.inbound_state = 'remote_deleted' then
    if current_revision > link.last_synced_revision then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'remote_deleted_with_local_edit', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict',
             last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'remote_deleted_with_local_edit',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    return jsonb_build_object('result', 'ignored', 'reason', 'remote_deleted');
  end if;

  if conn.provider = 'google'
     and p_provider_etag is not null
     and link.external_etag is not null
     and p_provider_etag = link.external_etag then
    return jsonb_build_object(
      'result', 'duplicate',
      'reason', 'etag',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if incoming_updated is not null and stored_updated is not null then
    if incoming_updated < stored_updated then
      return jsonb_build_object(
        'result', 'stale',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    if incoming_updated = stored_updated and mapped_equal then
      return jsonb_build_object(
        'result', 'duplicate',
        'reason', 'same_updated_equal_mapped',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
  end if;

  if current_revision < link.last_synced_revision then
    return jsonb_build_object(
      'result', 'error',
      'reason', 'revision_invariant',
      'revision_before', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      'diverged_revision', current_revision, link.last_synced_revision,
      current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
    );
    update public.external_sync_links
       set inbound_state = 'conflict',
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where id = link.id;
    return jsonb_build_object(
      'result', 'conflict',
      'reason', 'diverged_revision',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if mapped_equal then
    update public.external_sync_links
       set inbound_state = 'ready',
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at),
           last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object(
      'result', 'duplicate',
      'reason', 'mapped_equal',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if p_entity_type = 'inbox_items' then
    if (
      coalesce((p_patch->>'is_topic')::boolean, (current_row->>'is_topic')::boolean) = false
      or coalesce((p_patch->>'is_archived')::boolean, (current_row->>'is_archived')::boolean) = true
    ) and exists (
      select 1 from public.inbox_items child
       where child.user_id = conn.user_id
         and child.parent_id = p_entity_id
    ) then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'inbox_relationship', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict', last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'inbox_relationship',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
  end if;

  next_revision := current_revision + 1;

  if p_entity_type = 'memos' then
    update public.memos set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  elsif p_entity_type = 'diary_entries' then
    update public.diary_entries set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      entry_date = case when p_patch ? 'entry_date' then (p_patch->>'entry_date')::date else entry_date end,
      mood = case when p_patch ? 'mood' then p_patch->>'mood' else mood end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  elsif p_entity_type = 'calendar_events' then
    update public.calendar_events set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      event_date = case when p_patch ? 'event_date' then (p_patch->>'event_date')::date else event_date end,
      note = case when p_patch ? 'note' then p_patch->>'note' else note end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  else
    update public.inbox_items set
      content = case when p_patch ? 'content' then p_patch->>'content' else content end,
      item_type = case when p_patch ? 'item_type' then p_patch->>'item_type' else item_type end,
      inbox_column = case when p_patch ? 'inbox_column' then p_patch->>'inbox_column' else inbox_column end,
      is_completed = case when p_patch ? 'is_completed' then (p_patch->>'is_completed')::boolean else is_completed end,
      is_pinned = case when p_patch ? 'is_pinned' then (p_patch->>'is_pinned')::boolean else is_pinned end,
      is_archived = case when p_patch ? 'is_archived' then (p_patch->>'is_archived')::boolean else is_archived end,
      is_topic = case when p_patch ? 'is_topic' then (p_patch->>'is_topic')::boolean else is_topic end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  end if;

  update public.external_sync_links
     set last_synced_revision = next_revision,
         inbound_state = 'ready',
         sync_status = case when sync_status = 'skipped' then sync_status else 'synced' end,
         last_error = null,
         last_synced_at = now(),
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where id = link.id;

  select generation into generation_after
    from public.diurna_sync_signals
   where user_id = conn.user_id;

  return jsonb_build_object(
    'result', 'applied',
    'revision_before', current_revision,
    'revision_after', next_revision,
    'last_synced_revision', next_revision,
    'generation_after', coalesce(generation_after, 0)
  );
end;
$$;

create or replace function integrations.bootstrap_link_version(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_provider_etag text,
  p_provider_updated_at timestamptz,
  p_drift boolean,
  p_reason text,
  p_local_snapshot jsonb,
  p_remote_snapshot jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
begin
  select * into conn from public.integration_connections where id = p_connection_id for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));
  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found or link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;
  current_revision := coalesce((current_row->>'revision')::bigint, link.last_synced_revision);

  if p_drift or current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      coalesce(p_reason, 'bootstrap_remote_drift'),
      current_revision, link.last_synced_revision,
      coalesce(p_local_snapshot, current_row, '{}'::jsonb),
      coalesce(p_remote_snapshot, '{}'::jsonb),
      p_provider_etag
    );
    update public.external_sync_links
       set inbound_state = 'conflict',
           external_etag = p_provider_etag,
           external_updated_at = p_provider_updated_at,
           last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object('result', 'conflict', 'reason', coalesce(p_reason, 'bootstrap_remote_drift'));
  end if;

  update public.external_sync_links
     set inbound_state = 'ready',
         external_etag = p_provider_etag,
         external_updated_at = p_provider_updated_at,
         last_remote_event_at = now()
   where id = link.id;
  return jsonb_build_object('result', 'ready', 'revision_before', current_revision);
end;
$$;

create or replace function integrations.enqueue_inbound_work(
  p_connection_id uuid,
  p_provider text,
  p_work_type text,
  p_dedup_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  work integrations.inbound_work%rowtype;
begin
  select * into work
    from integrations.inbound_work
   where connection_id = p_connection_id
     and work_type = p_work_type
     and dedup_key = p_dedup_key
     and status in ('pending', 'processing')
     for update;

  if found and work.status = 'pending' then
    update integrations.inbound_work
       set latest_event_at = now(),
           payload = coalesce(p_payload, payload),
           updated_at = now()
     where id = work.id;
    return jsonb_build_object('enqueued', true, 'coalesced', true, 'status', 'pending', 'id', work.id);
  end if;

  if found and work.status = 'processing' then
    update integrations.inbound_work
       set rerun_requested = true,
           latest_event_at = now(),
           payload = coalesce(p_payload, payload),
           updated_at = now()
     where id = work.id;
    return jsonb_build_object(
      'enqueued', true, 'rerun_requested', true, 'status', 'processing', 'id', work.id
    );
  end if;

  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, payload, status
  ) values (
    p_connection_id, p_provider, p_work_type, p_dedup_key, coalesce(p_payload, '{}'::jsonb), 'pending'
  )
  returning * into work;

  return jsonb_build_object('enqueued', true, 'created', true, 'status', 'pending', 'id', work.id);
end;
$$;

create or replace function integrations.reclaim_stale_inbound_work()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare errored integer := 0;
declare retried integer := 0;
begin
  update integrations.inbound_work
     set status = 'error',
         locked_until = null,
         last_error = 'stale_lock',
         updated_at = now()
   where status = 'processing'
     and locked_until < now()
     and attempts >= 8;
  get diagnostics errored = row_count;

  update integrations.inbound_work
     set status = 'pending',
         locked_until = null,
         last_error = 'stale_lock',
         available_at = now() + least(
           interval '30 minutes',
           (15 * power(2, greatest(attempts, 0))) * interval '1 second'
         ),
         updated_at = now()
   where status = 'processing'
     and locked_until < now()
     and attempts < 8;
  get diagnostics retried = row_count;
  return errored + retried;
end;
$$;

create or replace function integrations.claim_inbound_work()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  perform integrations.reclaim_stale_inbound_work();
  with next as (
    select id
      from integrations.inbound_work
     where status = 'pending'
       and available_at <= now()
     order by created_at
     for update skip locked
     limit 1
  )
  update integrations.inbound_work w
     set status = 'processing',
         locked_until = now() + interval '3 minutes',
         attempts = attempts + 1,
         updated_at = now()
    from next
   where w.id = next.id
   returning w.* into work;
  if not found then
    return null;
  end if;
  return to_jsonb(work);
end;
$$;

create or replace function integrations.complete_inbound_work(p_id uuid, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  select * into work from integrations.inbound_work where id = p_id for update;
  if not found then
    return jsonb_build_object('result', 'ignored', 'reason', 'missing');
  end if;
  if work.status is distinct from 'processing' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_processing', 'status', work.status);
  end if;
  if p_error is not null and work.rerun_requested is not true then
    if work.attempts >= 8 then
      update integrations.inbound_work
         set status = 'error',
             locked_until = null,
             last_error = p_error,
             updated_at = now()
       where id = p_id;
      return jsonb_build_object('status', 'error', 'id', p_id);
    end if;
    update integrations.inbound_work
       set status = 'pending',
           locked_until = null,
           last_error = p_error,
           available_at = now() + least(
             interval '30 minutes',
             (15 * power(2, attempts)) * interval '1 second'
           ),
           updated_at = now()
     where id = p_id;
    return jsonb_build_object('status', 'pending', 'retry', true, 'id', p_id);
  end if;
  if work.rerun_requested then
    update integrations.inbound_work
       set status = 'pending',
           rerun_requested = false,
           locked_until = null,
           available_at = now(),
           last_error = null,
           updated_at = now()
     where id = p_id;
    return jsonb_build_object('status', 'pending', 'rerun', true, 'id', p_id);
  end if;
  update integrations.inbound_work
     set status = 'done',
         locked_until = null,
         last_error = null,
         updated_at = now()
   where id = p_id;
  return jsonb_build_object('status', 'done', 'id', p_id);
end;
$$;

create or replace function integrations.record_inbound_event(
  p_provider text,
  p_event_key text,
  p_connection_id uuid,
  p_result text
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  insert into integrations.inbound_events (provider, event_key, connection_id, result)
  values (p_provider, p_event_key, p_connection_id, p_result)
  on conflict (provider, event_key) do nothing;
  return found;
end;
$$;

revoke all on function integrations._allowed_patch_keys(text) from public, anon, authenticated;
revoke all on function integrations._patch_equals_row(jsonb, jsonb) from public, anon, authenticated;
revoke all on function integrations._open_conflict(uuid, uuid, text, text, uuid, text, text, bigint, bigint, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function integrations.apply_external_change(uuid, text, uuid, text, text, jsonb, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function integrations.bootstrap_link_version(uuid, text, uuid, text, text, timestamptz, boolean, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function integrations.enqueue_inbound_work(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function integrations.reclaim_stale_inbound_work() from public, anon, authenticated;
revoke all on function integrations.claim_inbound_work() from public, anon, authenticated;
revoke all on function integrations.complete_inbound_work(uuid, text) from public, anon, authenticated;
revoke all on function integrations.record_inbound_event(text, text, uuid, text) from public, anon, authenticated;

grant execute on function integrations._allowed_patch_keys(text) to postgres, service_role;
grant execute on function integrations._patch_equals_row(jsonb, jsonb) to postgres, service_role;
grant execute on function integrations._open_conflict(uuid, uuid, text, text, uuid, text, text, bigint, bigint, jsonb, jsonb, text) to postgres, service_role;
grant execute on function integrations.apply_external_change(uuid, text, uuid, text, text, jsonb, jsonb, text, timestamptz) to postgres, service_role;
grant execute on function integrations.bootstrap_link_version(uuid, text, uuid, text, text, timestamptz, boolean, text, jsonb, jsonb) to postgres, service_role;
grant execute on function integrations.enqueue_inbound_work(uuid, text, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.reclaim_stale_inbound_work() to postgres, service_role;
grant execute on function integrations.claim_inbound_work() to postgres, service_role;
grant execute on function integrations.complete_inbound_work(uuid, text) to postgres, service_role;
grant execute on function integrations.record_inbound_event(text, text, uuid, text) to postgres, service_role;

commit;
