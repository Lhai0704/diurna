-- Watch renewal work type, claim priority, disconnect-safe enqueue, event TTL.
begin;

alter table integrations.inbound_work
  drop constraint if exists inbound_work_work_type_check;
alter table integrations.inbound_work
  add constraint inbound_work_work_type_check
  check (work_type in (
    'notion_page', 'google_incremental', 'google_full',
    'google_calendar_gone', 'bootstrap_notion', 'bootstrap_google',
    'repair', 'renew_watch'
  ));

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
     order by
       case work_type
         when 'bootstrap_notion' then 0
         when 'bootstrap_google' then 0
         when 'notion_page' then 1
         when 'google_incremental' then 1
         when 'google_calendar_gone' then 1
         when 'renew_watch' then 2
         when 'repair' then 3
         else 4
       end,
       created_at
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
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
end;
$$;

create or replace function integrations.defer_inbound_work(p_id uuid, p_delay interval)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  update integrations.inbound_work
     set status = 'pending',
         locked_until = null,
         available_at = now() + coalesce(p_delay, interval '2 minutes'),
         attempts = greatest(attempts - 1, 0),
         updated_at = now()
   where id = p_id
     and status = 'processing';
  if not found then
    return jsonb_build_object('result', 'ignored');
  end if;
  return jsonb_build_object('result', 'deferred', 'id', p_id);
end;
$$;

create or replace function integrations.purge_inbound_events(p_older_than interval default interval '48 hours')
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare n integer := 0;
begin
  delete from integrations.inbound_events
   where created_at < now() - p_older_than;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function integrations.defer_inbound_work(uuid, interval) from public, anon, authenticated;
revoke all on function integrations.purge_inbound_events(interval) from public, anon, authenticated;
grant execute on function integrations.claim_inbound_work_of(text[]) to postgres, service_role;
grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.defer_inbound_work(uuid, interval) to postgres, service_role;
grant execute on function integrations.purge_inbound_events(interval) to postgres, service_role;

commit;
