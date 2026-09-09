-- Review fixes: handshake arm, outbound hold, repair cursor. Additive.
begin;

alter table public.external_sync_links
  add column if not exists outbound_hold boolean not null default false;

alter table public.integration_connections
  add column if not exists inbound_delta_hold boolean not null default false,
  add column if not exists inbound_repair_state jsonb not null default '{}'::jsonb;

create table if not exists integrations.webhook_handshake_arms (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'notion' check (provider in ('notion')),
  purpose text not null check (purpose in ('initial', 'rotate')),
  nonce_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

revoke all on table integrations.webhook_handshake_arms from public, anon, authenticated;
grant select, insert, update, delete on table integrations.webhook_handshake_arms to postgres, service_role;

create or replace function integrations.consume_handshake_arm(
  p_nonce_hash text,
  p_has_active_token boolean
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare arm integrations.webhook_handshake_arms%rowtype;
begin
  if p_nonce_hash is null or p_nonce_hash = '' then
    return jsonb_build_object('result', 'rejected', 'reason', 'missing_nonce');
  end if;
  select * into arm
    from integrations.webhook_handshake_arms
   where nonce_hash = p_nonce_hash
   for update;
  if not found then
    return jsonb_build_object('result', 'rejected', 'reason', 'unknown_nonce');
  end if;
  if arm.consumed_at is not null then
    return jsonb_build_object('result', 'rejected', 'reason', 'consumed');
  end if;
  if arm.expires_at <= now() then
    return jsonb_build_object('result', 'rejected', 'reason', 'expired');
  end if;
  if p_has_active_token and arm.purpose is distinct from 'rotate' then
    return jsonb_build_object('result', 'rejected', 'reason', 'active_token');
  end if;
  update integrations.webhook_handshake_arms
     set consumed_at = now()
   where id = arm.id;
  return jsonb_build_object('result', 'ok', 'purpose', arm.purpose);
end;
$$;

revoke all on function integrations.consume_handshake_arm(text, boolean) from public, anon, authenticated;
grant execute on function integrations.consume_handshake_arm(text, boolean) to postgres, service_role;

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
declare conn_status text;
begin
  if p_provider is null or p_event_key is null or p_event_key = ''
     or p_connection_id is null or p_work_type is null or p_dedup_key is null then
    raise exception 'VALIDATION';
  end if;
  select status into conn_status
    from public.integration_connections
   where id = p_connection_id
   for update;
  if not found or conn_status is distinct from 'connected' then
    return jsonb_build_object('accepted', false, 'ignored', true, 'reason', 'disconnected');
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
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
end;
$$;

grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;

commit;
