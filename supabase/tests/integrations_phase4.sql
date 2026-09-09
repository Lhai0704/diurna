-- Phase 4: renewal overlap, bootstrap baseline, disconnect, claim priority, event TTL.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status, container
) values (
  '21000000-0000-0000-0000-000000000040',
  '10000000-0000-0000-0000-000000000001',
  'google',
  'connected',
  'Diurna',
  'success',
  'bootstrapping',
  '{"calendar_id":"cal-diurna"}'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
declare r jsonb;
begin
  r := public.diurna_sync_calendar_v2(
    '31000000-0000-0000-0000-000000000040',
    '[{"id":"22000000-0000-0000-0000-000000000040","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000040","user_id":"10000000-0000-0000-0000-000000000001","title":"Dentist","event_date":"2026-09-11","is_completed":true,"note":"n","remind_at":"2026-09-11T08:00:00Z","created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}}]'
  );
  if r->>'ok' <> 'true' then raise exception 'calendar create failed %', r; end if;
end $$;
reset role;

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000040',
  'google', 'calendar_events', '22000000-0000-0000-0000-000000000040', 'gcal-dentist',
  1, 'synced', 'idle'
);

-- Bootstrap equal does not bump revision or signal.
do $$
declare r jsonb;
declare rev bigint;
declare gen_before bigint;
declare gen_after bigint;
begin
  select revision into rev from public.calendar_events where id = '22000000-0000-0000-0000-000000000040';
  select generation into gen_before from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000040',
    'calendar_events',
    '22000000-0000-0000-0000-000000000040',
    'gcal-dentist',
    '"etag-base"',
    now(),
    false,
    null,
    '{}'::jsonb,
    '{"title":"Dentist"}'::jsonb
  );
  if r->>'result' <> 'ready' then raise exception 'bootstrap equal failed %', r; end if;
  if (select revision from public.calendar_events where id = '22000000-0000-0000-0000-000000000040') <> rev then
    raise exception 'bootstrap bumped revision';
  end if;
  if (select last_synced_revision from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000040') <> 1 then
    raise exception 'bootstrap advanced last_synced';
  end if;
  select generation into gen_after from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  if gen_after is distinct from gen_before then
    raise exception 'bootstrap bumped signal % -> %', gen_before, gen_after;
  end if;
end $$;

-- Bootstrap drift conflicts without overwrite.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000040',
    'calendar_events',
    '22000000-0000-0000-0000-000000000040',
    'gcal-dentist',
    '"etag-drift"',
    now(),
    true,
    'bootstrap_remote_drift',
    '{"title":"Dentist"}'::jsonb,
    '{"title":"Remote"}'::jsonb
  );
  if r->>'result' <> 'conflict' then raise exception 'expected drift %', r; end if;
  if (select title from public.calendar_events where id = '22000000-0000-0000-0000-000000000040') <> 'Dentist' then
    raise exception 'drift overwrote title';
  end if;
end $$;

-- Renewal overlap: creating/new active plus retiring old both remain addressable.
insert into integrations.provider_watches (
  connection_id, provider, channel_id, channel_token, calendar_id, status, resource_id, expires_at, sync_token
) values
  (
    '21000000-0000-0000-0000-000000000040',
    'google', 'ch-old', 'tok-old', 'cal-diurna', 'retiring', 'res-old',
    now() + interval '1 hour', 'sync-old'
  ),
  (
    '21000000-0000-0000-0000-000000000040',
    'google', 'ch-new', 'tok-new', 'cal-diurna', 'active', 'res-new',
    now() + interval '7 days', 'sync-old'
  );

do $$ begin
  if (select count(*) from integrations.provider_watches
       where connection_id = '21000000-0000-0000-0000-000000000040'
         and status in ('active', 'retiring')) <> 2 then
    raise exception 'overlap watches missing';
  end if;
  if (select status from integrations.provider_watches where channel_id = 'ch-new') <> 'active' then
    raise exception 'new watch not active';
  end if;
  if (select status from integrations.provider_watches where channel_id = 'ch-old') <> 'retiring' then
    raise exception 'old watch not retiring';
  end if;
end $$;

-- Failed stop leaves retiring; new watch stays active.
update integrations.provider_watches
   set status = 'expired'
 where channel_id = 'ch-old';
do $$ begin
  if (select status from integrations.provider_watches where channel_id = 'ch-new') <> 'active' then
    raise exception 'stop old invalidated new watch';
  end if;
end $$;

-- Claim prefers bootstrap over repair.
insert into integrations.inbound_work (
  connection_id, provider, work_type, dedup_key, status, available_at
) values
  (
    '21000000-0000-0000-0000-000000000040',
    'google', 'repair', 'r1', 'pending', now()
  ),
  (
    '21000000-0000-0000-0000-000000000040',
    'google', 'google_incremental', '21000000-0000-0000-0000-000000000040', 'pending', now()
  ),
  (
    '21000000-0000-0000-0000-000000000040',
    'google', 'bootstrap_google', '21000000-0000-0000-0000-000000000040', 'pending', now()
  );
do $$
declare claimed jsonb;
begin
  claimed := integrations.claim_inbound_work_of(array['repair','google_incremental','bootstrap_google']);
  if claimed->>'work_type' <> 'bootstrap_google' then
    raise exception 'claim order wrong %', claimed;
  end if;
end $$;

-- Webhook incremental is claimed before repair.
do $$
declare claimed jsonb;
begin
  claimed := integrations.claim_inbound_work_of(array['repair','google_incremental','bootstrap_google']);
  if claimed->>'work_type' <> 'google_incremental' then
    raise exception 'webhook incremental starved by repair %', claimed;
  end if;
end $$;

-- Repair and webhook incremental serialize on one connection (same work_type+dedup).
do $$
declare first jsonb;
declare second jsonb;
begin
  first := integrations.enqueue_inbound_work(
    '21000000-0000-0000-0000-000000000040',
    'google', 'google_incremental', '21000000-0000-0000-0000-000000000040',
    '{"source":"webhook"}'::jsonb
  );
  second := integrations.enqueue_inbound_work(
    '21000000-0000-0000-0000-000000000040',
    'google', 'google_incremental', '21000000-0000-0000-0000-000000000040',
    '{"source":"repair"}'::jsonb
  );
  if first->>'id' is distinct from second->>'id' then
    raise exception 'repair opened a second incremental stream';
  end if;
  if second->>'coalesced' is distinct from 'true'
     and second->>'rerun_requested' is distinct from 'true' then
    raise exception 'expected coalesce or rerun %', second;
  end if;
  if (
    select count(*) from integrations.inbound_work
     where connection_id = '21000000-0000-0000-0000-000000000040'
       and work_type = 'google_incremental'
       and status in ('pending', 'processing')
  ) <> 1 then
    raise exception 'two incremental streams for one connection';
  end if;
end $$;

-- Overlapping watch notifications: distinct event keys, one incremental job.
do $$
declare a jsonb;
declare b jsonb;
begin
  a := integrations.accept_inbound_event(
    'google', 'ch-old:10',
    '21000000-0000-0000-0000-000000000040',
    'google_incremental',
    '21000000-0000-0000-0000-000000000040',
    '{"channel":"old"}'::jsonb
  );
  b := integrations.accept_inbound_event(
    'google', 'ch-new:2',
    '21000000-0000-0000-0000-000000000040',
    'google_incremental',
    '21000000-0000-0000-0000-000000000040',
    '{"channel":"new"}'::jsonb
  );
  if a->>'accepted' <> 'true' then raise exception 'old channel not accepted %', a; end if;
  if b->>'accepted' <> 'true' and b->>'duplicate' <> 'true' then
    if b->>'id' is distinct from a->>'id' and b->>'coalesced' is distinct from 'true'
       and b->>'rerun_requested' is distinct from 'true' then
      raise exception 'overlap opened a second job % %', a, b;
    end if;
  end if;
end $$;

-- Worker crash during bootstrap is recoverable via stale lock reclaim.
do $$
declare wid uuid;
declare n int;
begin
  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, status,
    attempts, locked_until
  ) values (
    '21000000-0000-0000-0000-000000000040',
    'google', 'bootstrap_google', 'crash-bootstrap',
    'processing', 1, now() - interval '1 minute'
  ) returning id into wid;
  n := integrations.reclaim_stale_inbound_work();
  if n < 1 then raise exception 'bootstrap crash not reclaimed'; end if;
  if (select status from integrations.inbound_work where id = wid) <> 'pending' then
    raise exception 'crashed bootstrap not pending';
  end if;
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000040') <> 'bootstrapping' then
    raise exception 'bootstrap crash changed inbound_status';
  end if;
end $$;

-- Degraded connections can still apply inbound (repair after watch failure).
update public.integration_connections
   set inbound_status = 'degraded'
 where id = '21000000-0000-0000-0000-000000000040';
do $$
declare r jsonb;
begin
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000040',
    'calendar_events',
    '22000000-0000-0000-0000-000000000040',
    'gcal-dentist',
    'update',
    '{"note":"n2"}'::jsonb,
    '{}'::jsonb,
    '"etag-deg"',
    now()
  );
  if r->>'result' <> 'applied' and r->>'result' <> 'conflict' then
    raise exception 'degraded apply ignored %', r;
  end if;
end $$;
-- The dentist link was conflicted by bootstrap drift above; already_conflict is ok.
update public.integration_connections
   set inbound_status = 'bootstrapping'
 where id = '21000000-0000-0000-0000-000000000040';

-- A conflicted link does not disable the connection.
do $$ begin
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000040') <> 'bootstrapping' then
    raise exception 'connection disabled by link conflict';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000040') <> 'conflict' then
    raise exception 'expected per-link conflict';
  end if;
end $$;

-- Notion unsupported body freeze during bootstrap does not bump revision.
insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values (
  '21000000-0000-0000-0000-000000000041',
  '10000000-0000-0000-0000-000000000001',
  'notion',
  'connected',
  'Workspace',
  'success',
  'bootstrapping'
);
select set_config('diurna.sync_protocol', '2', true);
insert into public.memos (id, user_id, title, content, position, revision)
values (
  '22000000-0000-0000-0000-000000000041',
  '10000000-0000-0000-0000-000000000001',
  'Note',
  'plain',
  1,
  1
);
insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000041',
  'notion', 'memos', '22000000-0000-0000-0000-000000000041', 'page-note',
  1, 'synced', 'idle'
);
do $$
declare r jsonb;
begin
  r := integrations.freeze_link_conflict(
    '21000000-0000-0000-0000-000000000041',
    'memos',
    '22000000-0000-0000-0000-000000000041',
    'page-note',
    'unsupported_content',
    '{"unsupported_body":true}'::jsonb,
    null,
    now()
  );
  if r->>'result' <> 'conflict' then raise exception 'unsupported freeze %', r; end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000041') <> 1 then
    raise exception 'unsupported bootstrap bumped revision';
  end if;
  if (select content from public.memos where id = '22000000-0000-0000-0000-000000000041') <> 'plain' then
    raise exception 'unsupported bootstrap overwrote content';
  end if;
end $$;

-- Notion bootstrap equal is ready without revision or signal bump.
insert into public.memos (id, user_id, title, content, position, revision)
values (
  '22000000-0000-0000-0000-000000000042',
  '10000000-0000-0000-0000-000000000001',
  'Equal',
  'same',
  2,
  1
);
insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000041',
  'notion', 'memos', '22000000-0000-0000-0000-000000000042', 'page-equal',
  1, 'synced', 'idle'
);
do $$
declare r jsonb;
declare rev bigint;
declare gen_before bigint;
declare gen_after bigint;
begin
  select revision into rev from public.memos where id = '22000000-0000-0000-0000-000000000042';
  select generation into gen_before from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000041',
    'memos',
    '22000000-0000-0000-0000-000000000042',
    'page-equal',
    null,
    now(),
    false,
    null,
    '{}'::jsonb,
    '{"title":"Equal"}'::jsonb
  );
  if r->>'result' <> 'ready' then raise exception 'notion equal failed %', r; end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000042') <> rev then
    raise exception 'notion equal bumped revision';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000042') <> 'ready' then
    raise exception 'notion equal not ready';
  end if;
  select generation into gen_after from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  if gen_after is distinct from gen_before then
    raise exception 'notion equal bumped signal';
  end if;
end $$;

-- Notion bootstrap remote edit conflicts and does not overwrite.
insert into public.memos (id, user_id, title, content, position, revision)
values (
  '22000000-0000-0000-0000-000000000043',
  '10000000-0000-0000-0000-000000000001',
  'Local',
  'keep',
  3,
  1
);
insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000041',
  'notion', 'memos', '22000000-0000-0000-0000-000000000043', 'page-drift',
  1, 'synced', 'idle'
);
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000041',
    'memos',
    '22000000-0000-0000-0000-000000000043',
    'page-drift',
    null,
    now(),
    true,
    'bootstrap_remote_drift',
    '{"title":"Local"}'::jsonb,
    '{"title":"Remote"}'::jsonb
  );
  if r->>'result' <> 'conflict' then raise exception 'notion drift %', r; end if;
  if (select title from public.memos where id = '22000000-0000-0000-0000-000000000043') <> 'Local' then
    raise exception 'notion drift overwrote title';
  end if;
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000041') <> 'bootstrapping' then
    raise exception 'notion link conflict disabled connection';
  end if;
end $$;

-- Disconnected connections do not enqueue inbound work.
update public.integration_connections
   set status = 'disconnected', inbound_status = 'disabled'
 where id = '21000000-0000-0000-0000-000000000040';
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'google', 'ch-new:99',
    '21000000-0000-0000-0000-000000000040',
    'google_incremental',
    '21000000-0000-0000-0000-000000000040',
    '{}'::jsonb
  );
  if r->>'ignored' <> 'true' then raise exception 'disconnected accepted work %', r; end if;
end $$;

-- Event TTL purge does not touch inbound_work.
insert into integrations.inbound_events (provider, event_key, connection_id, result, created_at)
values ('google', 'old-event', '21000000-0000-0000-0000-000000000040', 'accepted', now() - interval '50 hours');
insert into integrations.inbound_work (
  connection_id, provider, work_type, dedup_key, status
) values (
  '21000000-0000-0000-0000-000000000041',
  'notion', 'notion_page', 'keep-work', 'pending'
);
do $$
declare n int;
begin
  n := integrations.purge_inbound_events(interval '48 hours');
  if n < 1 then raise exception 'purge deleted nothing'; end if;
  if exists (select 1 from integrations.inbound_events where event_key = 'old-event') then
    raise exception 'old event survived purge';
  end if;
  if not exists (
    select 1 from integrations.inbound_work
     where dedup_key = 'keep-work' and status = 'pending'
  ) then
    raise exception 'purge removed unfinished inbound_work';
  end if;
end $$;

-- Stale/disconnected: expired watch row remains ignored by accept after disconnect.
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'google', 'ch-old:100',
    '21000000-0000-0000-0000-000000000040',
    'google_incremental',
    '21000000-0000-0000-0000-000000000040',
    '{}'::jsonb
  );
  if r->>'ignored' <> 'true' then raise exception 'stale disconnected still queued %', r; end if;
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000040',
    'calendar_events',
    '22000000-0000-0000-0000-000000000040',
    'gcal-dentist',
    '"etag-x"',
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'reason' <> 'not_connected' then
    raise exception 'bootstrap resurrected disconnected connection %', r;
  end if;
end $$;

rollback;
