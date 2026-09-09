-- Fresh equal bootstrap can dismiss stale bootstrap_remote_drift only.
-- Does not rewrite protocol v2 or earlier inbound objects.
begin;

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

  update public.external_sync_conflicts
     set status = 'dismissed',
         resolved_at = clock_timestamp()
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     and status = 'open'
     and reason = 'bootstrap_remote_drift';

  update public.external_sync_links
     set inbound_state = 'ready',
         outbound_hold = false,
         external_etag = p_provider_etag,
         external_updated_at = p_provider_updated_at,
         last_remote_event_at = now()
   where id = link.id;
  return jsonb_build_object('result', 'ready', 'revision_before', current_revision);
end;
$$;

commit;
