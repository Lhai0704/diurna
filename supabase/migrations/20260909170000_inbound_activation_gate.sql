-- Explicit inbound activation. disabled stays off until activate_inbound.
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
declare conn public.integration_connections%rowtype;
begin
  if p_provider is null or p_event_key is null or p_event_key = ''
     or p_connection_id is null or p_work_type is null or p_dedup_key is null then
    raise exception 'VALIDATION';
  end if;
  select * into conn
    from public.integration_connections
   where id = p_connection_id
   for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('accepted', false, 'ignored', true, 'reason', 'disconnected');
  end if;
  if conn.inbound_status is distinct from 'active'
     and conn.inbound_status is distinct from 'degraded'
     and conn.inbound_status is distinct from 'bootstrapping' then
    return jsonb_build_object('accepted', false, 'ignored', true, 'reason', 'inbound_disabled');
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
  if conn.inbound_status in ('active', 'degraded') then
    if p_work_type = 'notion_page' then
      update public.external_sync_links
         set outbound_hold = true,
             last_remote_event_at = now()
       where connection_id = p_connection_id
         and external_id = p_dedup_key;
    elsif p_work_type = 'google_incremental' then
      update public.integration_connections
         set inbound_delta_hold = true,
             updated_at = now()
       where id = p_connection_id;
    end if;
  end if;
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
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

create or replace function integrations.due_inbound_bootstraps()
returns table(id uuid, provider text)
language sql
security definer
set search_path = pg_catalog, public, integrations
as $$
  select c.id, c.provider
    from public.integration_connections c
   where c.status = 'connected'
     and c.inbound_status = 'bootstrapping'
     and not exists (
       select 1 from integrations.inbound_work w
        where w.connection_id = c.id
          and w.work_type in ('bootstrap_google', 'bootstrap_notion')
          and w.status in ('pending', 'processing')
     );
$$;

create or replace function integrations.activate_inbound(p_connection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare conn public.integration_connections%rowtype;
declare work jsonb;
declare work_type text;
begin
  if p_connection_id is null then
    raise exception 'VALIDATION';
  end if;
  select * into conn
    from public.integration_connections
   where id = p_connection_id
   for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('ok', false, 'result', 'ignored', 'reason', 'not_connected');
  end if;
  if conn.inbound_status = 'error' then
    return jsonb_build_object(
      'ok', false, 'result', 'error', 'reason', coalesce(conn.inbound_error, 'error')
    );
  end if;
  if conn.inbound_status in ('active', 'degraded') then
    return jsonb_build_object(
      'ok', true, 'result', 'already_active', 'inbound_status', conn.inbound_status
    );
  end if;
  if conn.inbound_status = 'disabled' then
    update public.integration_connections
       set inbound_status = 'bootstrapping',
           inbound_error = null,
           updated_at = now()
     where id = p_connection_id;
  end if;
  work_type := case conn.provider
    when 'google' then 'bootstrap_google'
    else 'bootstrap_notion'
  end;
  work := integrations.enqueue_inbound_work(
    p_connection_id, conn.provider, work_type, p_connection_id::text, '{}'::jsonb
  );
  return jsonb_build_object(
    'ok', true,
    'result', 'ok',
    'inbound_status', 'bootstrapping'
  ) || work;
end;
$$;

create or replace function integrations.deactivate_inbound(p_connection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare conn public.integration_connections%rowtype;
declare cancelled integer := 0;
begin
  if p_connection_id is null then
    raise exception 'VALIDATION';
  end if;
  select * into conn
    from public.integration_connections
   where id = p_connection_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'result', 'ignored', 'reason', 'missing');
  end if;
  update public.integration_connections
     set inbound_status = 'disabled',
         inbound_delta_hold = false,
         inbound_repair_state = '{}'::jsonb,
         inbound_error = null,
         updated_at = now()
   where id = p_connection_id;
  update public.external_sync_links
     set outbound_hold = false
   where connection_id = p_connection_id;
  update integrations.inbound_work
     set status = 'done',
         locked_until = null,
         last_error = 'inbound_disabled',
         updated_at = now()
   where connection_id = p_connection_id
     and status in ('pending', 'processing');
  get diagnostics cancelled = row_count;
  return jsonb_build_object(
    'ok', true,
    'result', 'ok',
    'inbound_status', 'disabled',
    'cancelled_work', cancelled
  );
end;
$$;

revoke all on function integrations.due_inbound_bootstraps() from public, anon, authenticated;
revoke all on function integrations.activate_inbound(uuid) from public, anon, authenticated;
revoke all on function integrations.deactivate_inbound(uuid) from public, anon, authenticated;
grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.due_inbound_bootstraps() to postgres, service_role;
grant execute on function integrations.activate_inbound(uuid) to postgres, service_role;
grant execute on function integrations.deactivate_inbound(uuid) to postgres, service_role;

commit;
