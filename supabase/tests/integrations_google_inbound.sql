-- Isolated PostgreSQL tests for Google inbound mapping helpers. Rolled back.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status, container
) values (
  '21000000-0000-0000-0000-000000000010',
  '10000000-0000-0000-0000-000000000001',
  'google',
  'connected',
  'Diurna',
  'success',
  'active',
  '{"calendar_id":"cal-diurna"}'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
declare r jsonb;
begin
  r := public.diurna_sync_calendar_v2(
    '31000000-0000-0000-0000-000000000010',
    '[{"id":"22000000-0000-0000-0000-000000000020","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000020","user_id":"10000000-0000-0000-0000-000000000001","title":"Dentist","event_date":"2026-09-11","is_completed":true,"note":"Bring xrays","remind_at":"2026-09-11T08:00:00Z","created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}}]'
  );
  if r->>'ok' <> 'true' then raise exception 'calendar create failed %', r; end if;
end $$;
reset role;

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state, external_etag
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000010',
  'google', 'calendar_events', '22000000-0000-0000-0000-000000000020', 'gcal-dentist',
  1, 'synced', 'ready', '"etag-1"'
);

insert into integrations.provider_watches (
  connection_id, provider, channel_id, channel_token, calendar_id, status, resource_id
) values (
  '21000000-0000-0000-0000-000000000010',
  'google', 'ch-creating', 'tok-secret', 'cal-diurna', 'creating', null
);

-- Early sync can see the creating row before events.watch returns.
do $$ begin
  if not exists (
    select 1 from integrations.provider_watches
     where channel_id = 'ch-creating' and status = 'creating' and resource_id is null
  ) then
    raise exception 'creating watch missing';
  end if;
end $$;

-- Safe all-day apply preserves is_completed and remind_at.
do $$
declare r jsonb;
begin
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000010',
    'calendar_events',
    '22000000-0000-0000-0000-000000000020',
    'gcal-dentist',
    'update',
    '{"title":"Dentist 2","event_date":"2026-09-12","note":"Bring xrays"}'::jsonb,
    '{}'::jsonb,
    '"etag-2"',
    '2026-09-09T13:00:00Z'::timestamptz
  );
  if r->>'result' <> 'applied' then raise exception 'google apply failed %', r; end if;
  if (select is_completed from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') is not true then
    raise exception 'is_completed cleared';
  end if;
  if (select remind_at from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') is null then
    raise exception 'remind_at cleared';
  end if;
  if (select event_date::text from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') <> '2026-09-12' then
    raise exception 'event_date not updated';
  end if;
end $$;

-- Same etag is duplicate (equality only; no ordering).
do $$
declare r jsonb;
declare rev bigint;
begin
  select revision into rev from public.calendar_events where id = '22000000-0000-0000-0000-000000000020';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000010',
    'calendar_events',
    '22000000-0000-0000-0000-000000000020',
    'gcal-dentist',
    'update',
    '{"title":"ignored"}'::jsonb,
    '{}'::jsonb,
    '"etag-2"',
    '2026-09-09T14:00:00Z'::timestamptz
  );
  if r->>'result' <> 'duplicate' then raise exception 'expected etag duplicate %', r; end if;
  if (select revision from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') <> rev then
    raise exception 'etag duplicate bumped revision';
  end if;
  if (select title from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') = 'ignored' then
    raise exception 'etag duplicate overwrote title';
  end if;
end $$;

-- Timed event freeze does not convert the date.
do $$
declare r jsonb;
declare dt date;
begin
  select event_date into dt from public.calendar_events where id = '22000000-0000-0000-0000-000000000020';
  r := integrations.freeze_link_conflict(
    '21000000-0000-0000-0000-000000000010',
    'calendar_events',
    '22000000-0000-0000-0000-000000000020',
    'gcal-dentist',
    'unsupported_timed_event',
    '{"start":{"dateTime":"2026-09-12T15:00:00Z"}}'::jsonb,
    '"etag-3"',
    now()
  );
  if r->>'result' <> 'conflict' then raise exception 'timed freeze failed %', r; end if;
  if (select event_date from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') <> dt then
    raise exception 'timed event coerced date';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000020') <> 'conflict' then
    raise exception 'timed event did not freeze';
  end if;
end $$;

-- remote_deleted does not write a tombstone.
do $$
declare r jsonb;
begin
  update public.external_sync_links
     set inbound_state = 'ready',
         last_synced_revision = (
           select revision from public.calendar_events
            where id = '22000000-0000-0000-0000-000000000020'
         )
   where entity_id = '22000000-0000-0000-0000-000000000020';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000010',
    'calendar_events',
    '22000000-0000-0000-0000-000000000020',
    'gcal-dentist',
    'remote_deleted',
    '{}'::jsonb, '{}'::jsonb, '"etag-4"', now()
  );
  if r->>'result' <> 'remote_deleted' then raise exception 'expected remote_deleted %', r; end if;
  if not exists (select 1 from public.calendar_events where id = '22000000-0000-0000-0000-000000000020') then
    raise exception 'google delete removed diurna row';
  end if;
  if exists (
    select 1 from public.diurna_sync_tombstones
     where entity_id = '22000000-0000-0000-0000-000000000020'
  ) then
    raise exception 'google delete wrote tombstone';
  end if;
end $$;

-- Incremental enqueue while processing sets rerun_requested.
do $$
declare q jsonb;
declare c jsonb;
declare wid uuid;
begin
  q := integrations.enqueue_inbound_work(
    '21000000-0000-0000-0000-000000000010',
    'google', 'google_incremental', '21000000-0000-0000-0000-000000000010', '{}'::jsonb
  );
  wid := (q->>'id')::uuid;
  update integrations.inbound_work
     set status = 'processing', locked_until = now() + interval '3 minutes', attempts = 1
   where id = wid;
  q := integrations.accept_inbound_event(
    'google',
    'ch-1:11',
    '21000000-0000-0000-0000-000000000010',
    'google_incremental',
    '21000000-0000-0000-0000-000000000010',
    '{}'::jsonb
  );
  if q->>'rerun_requested' <> 'true' then
    raise exception 'google processing accept did not rerun %', q;
  end if;
  c := integrations.complete_inbound_work(wid, null);
  if c->>'rerun' <> 'true' then raise exception 'google complete dropped rerun %', c; end if;
end $$;

rollback;
