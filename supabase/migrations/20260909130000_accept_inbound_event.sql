-- Atomic inbound event + work enqueue, plus inbound freeze/restore helpers.
begin;

create or replace function integrations.accept_inbound_event(
  p_provider text,
  p_event_key text,
  p_connection_id uuid,
  p_work_type text,
  p_dedup_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work jsonb;
begin
  if p_provider is null or p_event_key is null or p_event_key = ''
     or p_connection_id is null or p_work_type is null or p_dedup_key is null then
    raise exception 'VALIDATION';
  end if;
  insert into integrations.inbound_events (provider, event_key, connection_id, result)
  values (p_provider, p_event_key, p_connection_id, 'accepted')
  on conflict (provider, event_key) do nothing;
  if not found then
    return jsonb_build_object('accepted', false, 'duplicate', true);
  end if;
  work := integrations.enqueue_inbound_work(
    p_connection_id, p_provider, p_work_type, p_dedup_key, coalesce(p_payload, '{}'::jsonb)
  );
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
end;
$$;

create or replace function integrations.freeze_link_conflict(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_reason text,
  p_remote_snapshot jsonb default '{}'::jsonb,
  p_provider_etag text default null,
  p_provider_updated_at timestamptz default null
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
  perform integrations._open_conflict(
    conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
    coalesce(p_reason, 'unsupported_content'),
    current_revision, link.last_synced_revision,
    coalesce(current_row, '{}'::jsonb),
    coalesce(p_remote_snapshot, '{}'::jsonb),
    p_provider_etag
  );
  update public.external_sync_links
     set inbound_state = 'conflict',
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where id = link.id;
  return jsonb_build_object(
    'result', 'conflict',
    'reason', coalesce(p_reason, 'unsupported_content'),
    'revision_before', current_revision,
    'last_synced_revision', link.last_synced_revision
  );
end;
$$;

create or replace function integrations.restore_remote_deleted_link(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text
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
  if link.inbound_state is distinct from 'remote_deleted' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_remote_deleted');
  end if;
  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;
  current_revision := coalesce((current_row->>'revision')::bigint, link.last_synced_revision);
  if current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      'remote_deleted_with_local_edit',
      current_revision, link.last_synced_revision,
      coalesce(current_row, '{}'::jsonb), '{}'::jsonb, null
    );
    update public.external_sync_links
       set inbound_state = 'conflict', last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object('result', 'conflict', 'reason', 'remote_deleted_with_local_edit');
  end if;
  update public.external_sync_links
     set inbound_state = 'ready', last_remote_event_at = now()
   where id = link.id;
  return jsonb_build_object('result', 'ready', 'revision_before', current_revision);
end;
$$;

create or replace function integrations.claim_inbound_work_of(p_work_types text[])
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
       and work_type = any(p_work_types)
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

revoke all on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function integrations.freeze_link_conflict(uuid, text, uuid, text, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function integrations.restore_remote_deleted_link(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function integrations.claim_inbound_work_of(text[]) from public, anon, authenticated;
grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.freeze_link_conflict(uuid, text, uuid, text, text, jsonb, text, timestamptz) to postgres, service_role;
grant execute on function integrations.restore_remote_deleted_link(uuid, text, uuid, text) to postgres, service_role;
grant execute on function integrations.claim_inbound_work_of(text[]) to postgres, service_role;

commit;
