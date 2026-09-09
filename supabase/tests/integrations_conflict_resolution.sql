-- Isolated tests for explicit Keep Diurna / Use External resolution.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000190'),
  ('10000000-0000-0000-0000-000000000191')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values
  (
    '21000000-0000-0000-0000-000000000190',
    '10000000-0000-0000-0000-000000000190',
    'notion', 'connected', 'Conflicts', 'success', 'active'
  ),
  (
    '21000000-0000-0000-0000-000000000191',
    '10000000-0000-0000-0000-000000000190',
    'google', 'connected', 'Cal', 'success', 'active'
  );

select set_config('diurna.sync_protocol', '2', true);

insert into public.diary_entries (
  id, user_id, entry_date, title, content, mood, tags, revision
) values
  (
    '22000000-0000-0000-0000-000000000190',
    '10000000-0000-0000-0000-000000000190',
    '2026-07-31', 'Local title', 'local body', 'ok', '{}', 1
  ),
  (
    '22000000-0000-0000-0000-000000000191',
    '10000000-0000-0000-0000-000000000190',
    '2026-07-30', 'Equal title', 'same', null, '{}', 1
  ),
  (
    '22000000-0000-0000-0000-000000000192',
    '10000000-0000-0000-0000-000000000190',
    '2026-07-29', 'Gone local', 'keep me', null, '{}', 2
  ),
  (
    '22000000-0000-0000-0000-000000000193',
    '10000000-0000-0000-0000-000000000190',
    '2026-07-28', 'Stale local', 'body', null, '{}', 3
  );

insert into public.calendar_events (
  id, user_id, event_date, title, note, is_completed, revision
) values
  (
    '22000000-0000-0000-0000-000000000194',
    '10000000-0000-0000-0000-000000000190',
    '2027-03-01', 'Warranty', null, false, 1
  ),
  (
    '22000000-0000-0000-0000-000000000195',
    '10000000-0000-0000-0000-000000000190',
    '2027-04-01', 'Standup', null, false, 1
  );

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state, outbound_hold
) values
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000190', 'page-drift',
    1, 'synced', 'conflict', false
  ),
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000191', 'page-equal',
    1, 'synced', 'conflict', false
  ),
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000192', 'page-gone',
    1, 'synced', 'conflict', false
  ),
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000193', 'page-stale',
    1, 'synced', 'conflict', false
  ),
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000191',
    'google', 'calendar_events', '22000000-0000-0000-0000-000000000194', 'gcal-1',
    1, 'synced', 'conflict', false
  ),
  (
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000191',
    'google', 'calendar_events', '22000000-0000-0000-0000-000000000195', 'gcal-recurring',
    1, 'synced', 'conflict', true
  );

insert into public.external_sync_conflicts (
  id, user_id, connection_id, provider, entity_type, entity_id, external_id,
  status, reason, local_revision, last_synced_revision, local_snapshot, remote_snapshot
) values
  (
    '23000000-0000-0000-0000-000000000190',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000190', 'page-drift',
    'open', 'bootstrap_remote_drift', 1, 1,
    '{"title":"Local title","content":"local body","entry_date":"2026-07-31"}'::jsonb,
    '{"patch":{"title":"Remote title","content":"remote body","entry_date":"2026-07-31","mood":"ok"}}'::jsonb
  ),
  (
    '23000000-0000-0000-0000-000000000191',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000191', 'page-equal',
    'open', 'bootstrap_remote_drift', 1, 1,
    '{"title":"Equal title"}'::jsonb,
    '{"patch":{"title":"Equal title","content":"same"}}'::jsonb
  ),
  (
    '23000000-0000-0000-0000-000000000192',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000192', 'page-gone',
    'open', 'remote_deleted_with_local_edit', 2, 1,
    '{"title":"Gone local"}'::jsonb,
    '{"missing":true}'::jsonb
  ),
  (
    '23000000-0000-0000-0000-000000000193',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000193', 'page-stale',
    'open', 'bootstrap_remote_drift', 1, 1,
    '{"title":"old"}'::jsonb,
    '{"patch":{"title":"remote"}}'::jsonb
  ),
  (
    '23000000-0000-0000-0000-000000000194',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000191',
    'google', 'calendar_events', '22000000-0000-0000-0000-000000000194', 'gcal-1',
    'open', 'bootstrap_remote_drift', 1, 1,
    '{"title":"Warranty"}'::jsonb,
    '{"patch":{"title":"Warranty remote","event_date":"2027-03-01"}}'::jsonb
  ),
  (
    '23000000-0000-0000-0000-000000000195',
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000191',
    'google', 'calendar_events', '22000000-0000-0000-0000-000000000195', 'gcal-recurring',
    'open', 'unsupported_recurrence', 1, 1,
    '{"title":"Standup"}'::jsonb,
    '{"recurrence":["RRULE:FREQ=DAILY"]}'::jsonb
  );

-- authenticated cannot execute resolver finishers or read snapshots.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000190', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000190","role":"authenticated"}', true);

do $$ begin
  begin
    perform integrations.finish_conflict_keep_local(
      '10000000-0000-0000-0000-000000000190',
      '23000000-0000-0000-0000-000000000190',
      1, null, null, false
    );
    raise exception 'authenticated executed finish_conflict_keep_local';
  exception
    when insufficient_privilege then null;
    when undefined_function then null;
  end;
end $$;

do $$
declare n int;
begin
  begin
    select count(*) into n from public.external_sync_conflicts;
    if n is not null then
      raise exception 'authenticated still selects conflict snapshots';
    end if;
  exception
    when insufficient_privilege then null;
  end;
end $$;

do $$
declare n int;
  recorded bigint;
begin
  select count(*) into n from public.external_sync_conflict_summaries;
  if n <> 6 then
    raise exception 'summary view count %', n;
  end if;
  select local_revision, recorded_local_revision into n, recorded
    from public.external_sync_conflict_summaries
   where id = '23000000-0000-0000-0000-000000000193';
  if n <> 3 then
    raise exception 'view current revision %', n;
  end if;
  if recorded <> 1 then
    raise exception 'view recorded revision %', recorded;
  end if;
end $$;

reset role;

-- Freshness: old expected revision is stale; refresh is not auto-resolve;
-- a new explicit decision at the current revision can proceed.
do $$
declare r jsonb;
  listed jsonb;
  current_rev bigint;
  recorded bigint;
  st text;
  lock_count int;
begin
  r := integrations.finish_conflict_keep_local(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000193',
    1, 'etag-stale', '2026-09-09T10:05:00Z', false
  );
  if r->>'result' <> 'stale' then
    raise exception 'expected stale got %', r;
  end if;
  select status into st
    from public.external_sync_conflicts
   where id = '23000000-0000-0000-0000-000000000193';
  if st <> 'open' then
    raise exception 'stale finish must leave conflict open %', st;
  end if;

  listed := integrations.list_open_conflict_summaries(
    '10000000-0000-0000-0000-000000000190',
    '21000000-0000-0000-0000-000000000190'
  );
  select (elem->>'local_revision')::bigint, (elem->>'recorded_local_revision')::bigint
    into current_rev, recorded
    from jsonb_array_elements(listed) elem
   where elem->>'id' = '23000000-0000-0000-0000-000000000193';
  if current_rev <> 3 then
    raise exception 'summary current revision %', current_rev;
  end if;
  if recorded <> 1 then
    raise exception 'recorded revision should stay 1 got %', recorded;
  end if;
  select status into st
    from public.external_sync_conflicts
   where id = '23000000-0000-0000-0000-000000000193';
  if st <> 'open' then
    raise exception 'refresh must not auto-resolve %', st;
  end if;

  r := integrations.load_conflict_for_resolve(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000193',
    3
  );
  if r->>'result' <> 'ready' then
    raise exception 'refreshed expected current revision should load %', r;
  end if;
  if (r->'conflict'->>'local_revision')::bigint <> 1 then
    raise exception 'conflict.local_revision is historical %', r;
  end if;
  select count(*) into lock_count
    from pg_locks
   where pid = pg_backend_pid()
     and locktype = 'advisory';
  if lock_count < 1 then
    raise exception 'user mutation advisory lock not held after load';
  end if;

  r := integrations.finish_conflict_keep_local(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000193',
    3, 'etag-stale', '2026-09-09T10:05:00Z', false
  );
  if r->>'result' <> 'resolved_local' then
    raise exception 'fresh decision after local edit %', r;
  end if;
  if (r->>'revision')::bigint <> 3 then
    raise exception 'resolved at current revision %', r;
  end if;
end $$;

-- Keep Diurna: no revision bump, ready, resolved_local, last_synced=local.
do $$
declare r jsonb;
  rev bigint;
  gen_before bigint;
  gen_after bigint;
  st text;
  inbound text;
  synced bigint;
  hold boolean;
begin
  select generation into gen_before
    from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000190';
  r := integrations.finish_conflict_keep_local(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000190',
    1, 'etag-1', '2026-09-09T10:00:00Z', false
  );
  if r->>'result' <> 'resolved_local' then
    raise exception 'keep local %', r;
  end if;
  select revision into rev from public.diary_entries
   where id = '22000000-0000-0000-0000-000000000190';
  if rev <> 1 then
    raise exception 'keep local mutated revision %', rev;
  end if;
  select title into st from public.diary_entries
   where id = '22000000-0000-0000-0000-000000000190';
  if st <> 'Local title' then
    raise exception 'keep local changed title';
  end if;
  select status into st from public.external_sync_conflicts
   where id = '23000000-0000-0000-0000-000000000190';
  if st <> 'resolved_local' then
    raise exception 'status %', st;
  end if;
  select inbound_state, last_synced_revision, outbound_hold
    into inbound, synced, hold
    from public.external_sync_links
   where entity_id = '22000000-0000-0000-0000-000000000190';
  if inbound <> 'ready' or synced <> 1 or hold then
    raise exception 'link after keep local % % %', inbound, synced, hold;
  end if;
  select generation into gen_after
    from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000190';
  if coalesce(gen_after, 0) is distinct from coalesce(gen_before, 0) then
    raise exception 'keep local bumped generation';
  end if;
  r := integrations.finish_conflict_keep_local(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000190',
    1, null, null, false
  );
  if r->>'result' <> 'already_resolved' then
    raise exception 'idempotent keep local %', r;
  end if;
end $$;

-- Use External equal: no revision bump.
do $$
declare r jsonb;
  rev bigint;
begin
  r := integrations.finish_conflict_use_remote(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000191',
    1, 'update', '{"title":"Equal title","content":"same"}'::jsonb,
    '{"patch":{"title":"Equal title"}}'::jsonb,
    'etag-eq', '2026-09-09T10:01:00Z', true
  );
  if r->>'result' <> 'resolved_remote' then
    raise exception 'use remote equal %', r;
  end if;
  select revision into rev from public.diary_entries
   where id = '22000000-0000-0000-0000-000000000191';
  if rev <> 1 then
    raise exception 'equal apply bumped revision %', rev;
  end if;
end $$;

-- Use External drift: exactly one revision bump.
do $$
declare r jsonb;
  rev bigint;
  gen_after bigint;
  inbound text;
begin
  r := integrations.finish_conflict_use_remote(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000194',
    1, 'update', '{"title":"Warranty remote","event_date":"2027-03-01"}'::jsonb,
    '{"patch":{"title":"Warranty remote"}}'::jsonb,
    'g-etag', '2026-09-09T10:02:00Z', false
  );
  if r->>'result' <> 'resolved_remote' then
    raise exception 'google use remote %', r;
  end if;
  if (r->>'revision_after')::bigint <> 2 then
    raise exception 'revision_after %', r;
  end if;
  select revision, title into rev, inbound from public.calendar_events
   where id = '22000000-0000-0000-0000-000000000194';
  if rev <> 2 or inbound <> 'Warranty remote' then
    raise exception 'calendar after use remote % %', rev, inbound;
  end if;
  select event_date::text into inbound from public.calendar_events
   where id = '22000000-0000-0000-0000-000000000194';
  if inbound <> '2027-03-01' then
    raise exception 'event_date changed %', inbound;
  end if;
  select inbound_state into inbound from public.external_sync_links
   where entity_id = '22000000-0000-0000-0000-000000000194';
  if inbound <> 'ready' then
    raise exception 'google link %', inbound;
  end if;
  select generation into gen_after from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000190';
  if gen_after is null then
    raise exception 'missing generation after apply';
  end if;
end $$;

-- Remote gone: keep local does not delete the Diurna row.
do $$
declare r jsonb;
  n int;
  inbound text;
  hold boolean;
begin
  r := integrations.finish_conflict_keep_local(
    '10000000-0000-0000-0000-000000000190',
    '23000000-0000-0000-0000-000000000192',
    2, null, null, true
  );
  if r->>'result' <> 'resolved_local' then
    raise exception 'remote gone keep %', r;
  end if;
  select count(*) into n from public.diary_entries
   where id = '22000000-0000-0000-0000-000000000192';
  if n <> 1 then
    raise exception 'hard deleted local row';
  end if;
  select inbound_state, outbound_hold into inbound, hold
    from public.external_sync_links
   where entity_id = '22000000-0000-0000-0000-000000000192';
  if inbound <> 'remote_deleted' or hold is not true then
    raise exception 'remote gone link % %', inbound, hold;
  end if;
end $$;

-- Summaries omit snapshot keys and include field categories.
-- Recurrence is not resolvable: both actions disabled, conflict stays open.
do $$
declare r jsonb;
  elem jsonb;
  st text;
  inbound text;
  hold boolean;
  rev bigint;
begin
  r := integrations.list_open_conflict_summaries(
    '10000000-0000-0000-0000-000000000190',
    null
  );
  if jsonb_typeof(r) <> 'array' then
    raise exception 'summaries not array';
  end if;
  if r::text like '%local_snapshot%' or r::text like '%remote_snapshot%' then
    raise exception 'summaries leaked snapshots';
  end if;
  select value into elem
    from jsonb_array_elements(r)
   where value->>'id' = '23000000-0000-0000-0000-000000000195';
  if elem is null then
    raise exception 'recurrence conflict missing from summaries';
  end if;
  if (elem->>'can_keep_local')::boolean is not false then
    raise exception 'recurrence can_keep_local %', elem;
  end if;
  if (elem->>'can_keep_local_push')::boolean is not false then
    raise exception 'recurrence can_keep_local_push %', elem;
  end if;
  if (elem->>'can_use_remote')::boolean is not false then
    raise exception 'recurrence can_use_remote %', elem;
  end if;
  if elem->>'blocked_reason' <> 'unsupported_recurrence' then
    raise exception 'recurrence blocked_reason %', elem;
  end if;
  select status into st
    from public.external_sync_conflicts
   where id = '23000000-0000-0000-0000-000000000195';
  if st <> 'open' then
    raise exception 'recurrence conflict resolved %', st;
  end if;
  select inbound_state, outbound_hold into inbound, hold
    from public.external_sync_links
   where entity_id = '22000000-0000-0000-0000-000000000195';
  if inbound <> 'conflict' or hold is not true then
    raise exception 'recurrence link mutated % %', inbound, hold;
  end if;
  select revision into rev
    from public.calendar_events
   where id = '22000000-0000-0000-0000-000000000195';
  if rev <> 1 then
    raise exception 'recurrence local revision mutated %', rev;
  end if;
end $$;

-- Other user cannot load this conflict.
do $$
declare r jsonb;
begin
  r := integrations.load_conflict_for_resolve(
    '10000000-0000-0000-0000-000000000191',
    '23000000-0000-0000-0000-000000000193',
    3
  );
  if r->>'result' <> 'not_found' then
    raise exception 'cross-user load %', r;
  end if;
end $$;

rollback;
