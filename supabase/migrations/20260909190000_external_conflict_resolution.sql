-- Explicit Keep Diurna / Use External resolution for inbound conflicts.
-- Additive. Do not edit 20260909120000–20260909180000.

begin;

revoke select on table public.external_sync_conflicts from authenticated;

drop view if exists public.external_sync_conflict_summaries;
create view public.external_sync_conflict_summaries as
select
  id,
  user_id,
  connection_id,
  provider,
  entity_type,
  entity_id,
  external_id,
  status,
  reason,
  local_revision,
  last_synced_revision,
  created_at,
  resolved_at
from public.external_sync_conflicts
where user_id = auth.uid();

revoke all on public.external_sync_conflict_summaries from public, anon, authenticated;
grant select on public.external_sync_conflict_summaries to authenticated, service_role, postgres;

create or replace function integrations._conflict_field_categories(
  p_entity_type text,
  p_local jsonb,
  p_remote_patch jsonb
) returns text[]
language plpgsql
stable
set search_path = pg_catalog, public, integrations
as $$
declare
  keys text[];
  k text;
  out_keys text[] := array[]::text[];
  local_v text;
  remote_v text;
begin
  keys := integrations._allowed_patch_keys(p_entity_type);
  if p_remote_patch is null or jsonb_typeof(p_remote_patch) <> 'object' then
    return out_keys;
  end if;
  foreach k in array keys
  loop
    if not (p_remote_patch ? k) then
      continue;
    end if;
    local_v := p_local->>k;
    remote_v := p_remote_patch->>k;
    if k in ('entry_date', 'event_date') then
      if left(coalesce(local_v, ''), 10) is not distinct from left(coalesce(remote_v, ''), 10) then
        continue;
      end if;
    elsif local_v is not distinct from remote_v then
      continue;
    end if;
    out_keys := array_append(out_keys, k);
  end loop;
  return out_keys;
end;
$$;

create or replace function integrations._conflict_entity_label(
  p_entity_type text,
  p_entity_id uuid,
  p_user_id uuid
) returns text
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  label text;
begin
  if p_entity_type = 'diary_entries' then
    select entry_date::text into label
      from public.diary_entries
     where id = p_entity_id and user_id = p_user_id;
  elsif p_entity_type = 'calendar_events' then
    select event_date::text into label
      from public.calendar_events
     where id = p_entity_id and user_id = p_user_id;
  end if;
  return label;
end;
$$;

create or replace function integrations.list_open_conflict_summaries(
  p_user_id uuid,
  p_connection_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  summaries jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at), '[]'::jsonb)
    into summaries
  from (
    select
      c.id,
      c.connection_id,
      c.provider,
      c.entity_type,
      c.entity_id,
      c.status,
      c.reason,
      c.local_revision,
      c.last_synced_revision,
      c.created_at,
      integrations._conflict_entity_label(c.entity_type, c.entity_id, c.user_id) as entity_label,
      integrations._conflict_field_categories(
        c.entity_type,
        coalesce(lr.local_row, c.local_snapshot, '{}'::jsonb),
        coalesce(c.remote_snapshot->'patch', '{}'::jsonb)
      ) as field_categories,
      (c.reason not in (
        'remote_deleted',
        'remote_deleted_with_local_edit'
      )) as can_keep_local_push,
      (c.reason not in (
        'unsupported_content',
        'unsupported_timed_event',
        'unsupported_recurrence'
      )) as can_use_remote,
      case
        when c.reason in ('remote_deleted', 'remote_deleted_with_local_edit')
          then 'remote_gone'
        when c.reason in (
          'unsupported_content',
          'unsupported_timed_event',
          'unsupported_recurrence'
        ) then c.reason
        else null
      end as blocked_reason
    from public.external_sync_conflicts c
    left join lateral (
      select case c.entity_type
        when 'diary_entries' then (
          select to_jsonb(r) from public.diary_entries r
           where r.id = c.entity_id and r.user_id = c.user_id
        )
        when 'calendar_events' then (
          select to_jsonb(r) from public.calendar_events r
           where r.id = c.entity_id and r.user_id = c.user_id
        )
        when 'memos' then (
          select to_jsonb(r) from public.memos r
           where r.id = c.entity_id and r.user_id = c.user_id
        )
        when 'inbox_items' then (
          select to_jsonb(r) from public.inbox_items r
           where r.id = c.entity_id and r.user_id = c.user_id
        )
        else '{}'::jsonb
      end as local_row
    ) lr on true
    where c.user_id = p_user_id
      and c.status = 'open'
      and (p_connection_id is null or c.connection_id = p_connection_id)
  ) s;
  return summaries;
end;
$$;

create or replace function integrations.load_conflict_for_resolve(
  p_user_id uuid,
  p_conflict_id uuid,
  p_expected_local_revision bigint
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  conflict public.external_sync_conflicts%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
begin
  select * into conflict
    from public.external_sync_conflicts
   where id = p_conflict_id
     and user_id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  select * into conn
    from public.integration_connections
   where id = conflict.connection_id
     for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'not_connected');
  end if;
  if conn.inbound_status not in ('active', 'degraded', 'bootstrapping') then
    return jsonb_build_object('result', 'inbound_disabled');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));

  if conflict.status is distinct from 'open' then
    return jsonb_build_object(
      'result', 'already_resolved',
      'status', conflict.status,
      'reason', conflict.reason
    );
  end if;

  select * into link
    from public.external_sync_links
   where connection_id = conflict.connection_id
     and entity_type = conflict.entity_type
     and entity_id = conflict.entity_id
   for update;
  if not found then
    return jsonb_build_object('result', 'no_link');
  end if;

  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    conflict.entity_type
  ) into current_row using conflict.entity_id, conn.user_id;
  if current_row is null then
    return jsonb_build_object('result', 'missing_entity');
  end if;
  current_revision := (current_row->>'revision')::bigint;
  if current_revision is distinct from p_expected_local_revision
     or current_revision is distinct from conflict.local_revision then
    return jsonb_build_object(
      'result', 'stale',
      'current_revision', current_revision,
      'conflict_local_revision', conflict.local_revision,
      'expected_local_revision', p_expected_local_revision
    );
  end if;

  return jsonb_build_object(
    'result', 'ready',
    'conflict', jsonb_build_object(
      'id', conflict.id,
      'connection_id', conflict.connection_id,
      'provider', conflict.provider,
      'entity_type', conflict.entity_type,
      'entity_id', conflict.entity_id,
      'external_id', conflict.external_id,
      'reason', conflict.reason,
      'local_revision', conflict.local_revision,
      'last_synced_revision', conflict.last_synced_revision,
      'remote_version', conflict.remote_version
    ),
    'link', jsonb_build_object(
      'id', link.id,
      'inbound_state', link.inbound_state,
      'outbound_hold', link.outbound_hold,
      'last_synced_revision', link.last_synced_revision,
      'external_id', link.external_id,
      'external_etag', link.external_etag,
      'external_updated_at', link.external_updated_at
    ),
    'current_row', current_row,
    'container', conn.container
  );
end;
$$;

create or replace function integrations.finish_conflict_keep_local(
  p_user_id uuid,
  p_conflict_id uuid,
  p_expected_local_revision bigint,
  p_provider_etag text,
  p_provider_updated_at timestamptz,
  p_accept_remote_gone boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  loaded jsonb;
  conflict public.external_sync_conflicts%rowtype;
  current_revision bigint;
  inbound_next text;
  hold_next boolean;
begin
  loaded := integrations.load_conflict_for_resolve(
    p_user_id, p_conflict_id, p_expected_local_revision
  );
  if loaded->>'result' is distinct from 'ready' then
    return loaded;
  end if;

  select * into conflict
    from public.external_sync_conflicts
   where id = p_conflict_id
   for update;
  current_revision := (loaded->'current_row'->>'revision')::bigint;

  if p_accept_remote_gone then
    inbound_next := 'remote_deleted';
    hold_next := true;
  else
    inbound_next := 'ready';
    hold_next := false;
  end if;

  update public.external_sync_links
     set last_synced_revision = current_revision,
         inbound_state = inbound_next,
         outbound_hold = hold_next,
         sync_status = case when sync_status = 'skipped' then sync_status else 'synced' end,
         last_error = null,
         last_synced_at = now(),
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where connection_id = conflict.connection_id
     and entity_type = conflict.entity_type
     and entity_id = conflict.entity_id;

  update public.external_sync_conflicts
     set status = 'resolved_local',
         resolved_at = clock_timestamp()
   where id = conflict.id
     and status = 'open';

  return jsonb_build_object(
    'result', 'resolved_local',
    'revision', current_revision,
    'last_synced_revision', current_revision,
    'inbound_state', inbound_next
  );
end;
$$;

create or replace function integrations.finish_conflict_use_remote(
  p_user_id uuid,
  p_conflict_id uuid,
  p_expected_local_revision bigint,
  p_operation text,
  p_patch jsonb,
  p_remote_snapshot jsonb,
  p_provider_etag text,
  p_provider_updated_at timestamptz,
  p_mapped_equal boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  loaded jsonb;
  conflict public.external_sync_conflicts%rowtype;
  conn public.integration_connections%rowtype;
  current_row jsonb;
  current_revision bigint;
  next_revision bigint;
  generation_after bigint;
  allowed text[];
  patch_key text;
begin
  if p_operation is null or p_operation not in ('update', 'remote_deleted') then
    raise exception 'VALIDATION';
  end if;
  loaded := integrations.load_conflict_for_resolve(
    p_user_id, p_conflict_id, p_expected_local_revision
  );
  if loaded->>'result' is distinct from 'ready' then
    return loaded;
  end if;

  select * into conflict
    from public.external_sync_conflicts
   where id = p_conflict_id
   for update;
  select * into conn
    from public.integration_connections
   where id = conflict.connection_id
   for update;
  current_row := loaded->'current_row';
  current_revision := (current_row->>'revision')::bigint;

  perform set_config('diurna.sync_protocol', '2', true);

  if p_operation = 'remote_deleted' then
    update public.external_sync_links
       set inbound_state = 'remote_deleted',
           outbound_hold = true,
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where connection_id = conflict.connection_id
       and entity_type = conflict.entity_type
       and entity_id = conflict.entity_id;
    update public.external_sync_conflicts
       set status = 'resolved_remote',
           resolved_at = clock_timestamp()
     where id = conflict.id
       and status = 'open';
    return jsonb_build_object(
      'result', 'resolved_remote',
      'revision', current_revision,
      'last_synced_revision', current_revision,
      'inbound_state', 'remote_deleted'
    );
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'VALIDATION';
  end if;
  allowed := integrations._allowed_patch_keys(conflict.entity_type);
  for patch_key in select jsonb_object_keys(p_patch)
  loop
    if not patch_key = any(allowed) then
      raise exception 'UNKNOWN_FIELD';
    end if;
  end loop;

  if conflict.entity_type = 'inbox_items' then
    if (
      coalesce((p_patch->>'is_topic')::boolean, (current_row->>'is_topic')::boolean) = false
      or coalesce((p_patch->>'is_archived')::boolean, (current_row->>'is_archived')::boolean) = true
    ) and exists (
      select 1 from public.inbox_items child
       where child.user_id = conn.user_id
         and child.parent_id = conflict.entity_id
    ) then
      return jsonb_build_object('result', 'inbox_relationship');
    end if;
  end if;

  if p_mapped_equal then
    update public.external_sync_links
       set last_synced_revision = current_revision,
           inbound_state = 'ready',
           outbound_hold = false,
           last_error = null,
           last_synced_at = now(),
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where connection_id = conflict.connection_id
       and entity_type = conflict.entity_type
       and entity_id = conflict.entity_id;
    update public.external_sync_conflicts
       set status = 'resolved_remote',
           resolved_at = clock_timestamp()
     where id = conflict.id
       and status = 'open';
    return jsonb_build_object(
      'result', 'resolved_remote',
      'revision', current_revision,
      'last_synced_revision', current_revision,
      'inbound_state', 'ready'
    );
  end if;

  next_revision := current_revision + 1;
  if conflict.entity_type = 'memos' then
    update public.memos set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = conflict.entity_id and user_id = conn.user_id;
  elsif conflict.entity_type = 'diary_entries' then
    update public.diary_entries set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      entry_date = case when p_patch ? 'entry_date' then (p_patch->>'entry_date')::date else entry_date end,
      mood = case when p_patch ? 'mood' then p_patch->>'mood' else mood end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = conflict.entity_id and user_id = conn.user_id;
  elsif conflict.entity_type = 'calendar_events' then
    update public.calendar_events set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      event_date = case when p_patch ? 'event_date' then (p_patch->>'event_date')::date else event_date end,
      note = case when p_patch ? 'note' then p_patch->>'note' else note end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = conflict.entity_id and user_id = conn.user_id;
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
     where id = conflict.entity_id and user_id = conn.user_id;
  end if;

  update public.external_sync_links
     set last_synced_revision = next_revision,
         inbound_state = 'ready',
         outbound_hold = false,
         sync_status = case when sync_status = 'skipped' then sync_status else 'synced' end,
         last_error = null,
         last_synced_at = now(),
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where connection_id = conflict.connection_id
     and entity_type = conflict.entity_type
     and entity_id = conflict.entity_id;

  update public.external_sync_conflicts
     set status = 'resolved_remote',
         remote_snapshot = coalesce(p_remote_snapshot, remote_snapshot),
         resolved_at = clock_timestamp()
   where id = conflict.id
     and status = 'open';

  select generation into generation_after
    from public.diurna_sync_signals
   where user_id = conn.user_id;

  return jsonb_build_object(
    'result', 'resolved_remote',
    'revision_before', current_revision,
    'revision_after', next_revision,
    'last_synced_revision', next_revision,
    'inbound_state', 'ready',
    'generation_after', coalesce(generation_after, 0)
  );
end;
$$;

revoke all on function integrations.list_open_conflict_summaries(uuid, uuid) from public, anon, authenticated;
revoke all on function integrations.load_conflict_for_resolve(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function integrations.finish_conflict_keep_local(uuid, uuid, bigint, text, timestamptz, boolean) from public, anon, authenticated;
revoke all on function integrations.finish_conflict_use_remote(uuid, uuid, bigint, text, jsonb, jsonb, text, timestamptz, boolean) from public, anon, authenticated;
grant execute on function integrations.list_open_conflict_summaries(uuid, uuid) to postgres, service_role;
grant execute on function integrations.load_conflict_for_resolve(uuid, uuid, bigint) to postgres, service_role;
grant execute on function integrations.finish_conflict_keep_local(uuid, uuid, bigint, text, timestamptz, boolean) to postgres, service_role;
grant execute on function integrations.finish_conflict_use_remote(uuid, uuid, bigint, text, jsonb, jsonb, text, timestamptz, boolean) to postgres, service_role;

commit;
