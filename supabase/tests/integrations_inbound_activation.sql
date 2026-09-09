-- Explicit inbound activation: disabled connections stay untouched.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values
  (
    '21000000-0000-0000-0000-000000000060',
    '10000000-0000-0000-0000-000000000001',
    'notion', 'connected', 'Prod Notion', 'success', 'disabled'
  ),
  (
    '21000000-0000-0000-0000-000000000061',
    '10000000-0000-0000-0000-000000000001',
    'google', 'connected', 'Prod Google', 'success', 'disabled'
  ),
  (
    '21000000-0000-0000-0000-000000000062',
    '10000000-0000-0000-0000-000000000002',
    'notion', 'connected', 'Test Notion', 'success', 'disabled'
  );

select set_config('diurna.sync_protocol', '2', true);
insert into public.memos (id, user_id, title, content, position, revision)
values (
  '22000000-0000-0000-0000-000000000060',
  '10000000-0000-0000-0000-000000000001',
  'Note',
  'body',
  1,
  1
);
insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state, outbound_hold
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000060',
  'notion', 'memos', '22000000-0000-0000-0000-000000000060', 'page-prod',
  1, 'synced', 'ready', false
);

-- 1. connected + disabled + Notion webhook ignored, no work, no outbound_hold.
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'notion', 'evt-disabled-n',
    '21000000-0000-0000-0000-000000000060',
    'notion_page', 'page-prod', '{}'::jsonb
  );
  if r->>'ignored' <> 'true' or r->>'reason' <> 'inbound_disabled' then
    raise exception 'disabled notion accepted %', r;
  end if;
  if exists (
    select 1 from integrations.inbound_work
     where connection_id = '21000000-0000-0000-0000-000000000060'
  ) then
    raise exception 'disabled notion enqueued work';
  end if;
  if (select outbound_hold from public.external_sync_links
        where external_id = 'page-prod') is not false then
    raise exception 'disabled notion set outbound_hold';
  end if;
end $$;

-- 2. connected + disabled + Google webhook ignored, no inbound_delta_hold.
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'google', 'ch-prod:1',
    '21000000-0000-0000-0000-000000000061',
    'google_incremental',
    '21000000-0000-0000-0000-000000000061',
    '{}'::jsonb
  );
  if r->>'ignored' <> 'true' or r->>'reason' <> 'inbound_disabled' then
    raise exception 'disabled google accepted %', r;
  end if;
  if exists (
    select 1 from integrations.inbound_work
     where connection_id = '21000000-0000-0000-0000-000000000061'
  ) then
    raise exception 'disabled google enqueued work';
  end if;
  if (select inbound_delta_hold from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000061') is not false then
    raise exception 'disabled google set inbound_delta_hold';
  end if;
end $$;

-- 3. maintenance due bootstraps: disabled production connections enqueue zero.
do $$ begin
  if exists (select 1 from integrations.due_inbound_bootstraps()) then
    raise exception 'disabled connections appeared in due bootstraps';
  end if;
end $$;

-- 4. explicit activation of one connection bootstraps only that one.
do $$
declare r jsonb;
begin
  r := integrations.activate_inbound('21000000-0000-0000-0000-000000000062');
  if r->>'ok' <> 'true' then raise exception 'activate failed %', r; end if;
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000062') <> 'bootstrapping' then
    raise exception 'activated connection not bootstrapping';
  end if;
  if (
    select count(*) from integrations.inbound_work
     where connection_id = '21000000-0000-0000-0000-000000000062'
       and work_type = 'bootstrap_notion'
       and status in ('pending', 'processing')
  ) <> 1 then
    raise exception 'activate did not enqueue bootstrap';
  end if;
end $$;

-- 5. other disabled connections remain untouched.
do $$ begin
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000060') <> 'disabled' then
    raise exception 'prod notion was promoted';
  end if;
  if (select inbound_status from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000061') <> 'disabled' then
    raise exception 'prod google was promoted';
  end if;
  if exists (
    select 1 from integrations.due_inbound_bootstraps()
     where id in (
       '21000000-0000-0000-0000-000000000060',
       '21000000-0000-0000-0000-000000000061'
     )
  ) then
    raise exception 'prod connections due for bootstrap';
  end if;
  if exists (
    select 1 from integrations.inbound_work
     where connection_id in (
       '21000000-0000-0000-0000-000000000060',
       '21000000-0000-0000-0000-000000000061'
     )
  ) then
    raise exception 'prod connections have inbound work';
  end if;
end $$;

-- activate is idempotent while bootstrapping (coalesces work).
do $$
declare r jsonb;
begin
  r := integrations.activate_inbound('21000000-0000-0000-0000-000000000062');
  if r->>'ok' <> 'true' then raise exception 'second activate failed %', r; end if;
  if (
    select count(*) from integrations.inbound_work
     where connection_id = '21000000-0000-0000-0000-000000000062'
       and work_type = 'bootstrap_notion'
       and status in ('pending', 'processing')
  ) <> 1 then
    raise exception 'second activate duplicated bootstrap';
  end if;
end $$;

-- 6. stuck bootstrapping without inflight work is recoverable.
update integrations.inbound_work
   set status = 'done', last_error = 'stale_lock'
 where connection_id = '21000000-0000-0000-0000-000000000062';
do $$ begin
  if not exists (
    select 1 from integrations.due_inbound_bootstraps()
     where id = '21000000-0000-0000-0000-000000000062'
  ) then
    raise exception 'stuck bootstrapping not recoverable';
  end if;
end $$;

-- bootstrap/apply mutations also ignore disabled connections (no freeze).
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000060',
    'memos',
    '22000000-0000-0000-0000-000000000060',
    'page-prod',
    'etag',
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'ignored' <> 'true' or r->>'reason' <> 'inbound_disabled' then
    raise exception 'bootstrap_link_version on disabled %', r;
  end if;
  r := integrations.freeze_link_conflict(
    '21000000-0000-0000-0000-000000000060',
    'memos',
    '22000000-0000-0000-0000-000000000060',
    'page-prod',
    'unsupported_content',
    '{}'::jsonb
  );
  if r->>'ignored' <> 'true' or r->>'reason' <> 'inbound_disabled' then
    raise exception 'freeze_link_conflict on disabled %', r;
  end if;
  if (select inbound_state from public.external_sync_links
        where external_id = 'page-prod') <> 'ready' then
    raise exception 'disabled inbound mutated link state';
  end if;
end $$;

-- 7. outbound remains operational: no hold on disabled, last_synced still matches.
do $$ begin
  if (select outbound_hold from public.external_sync_links
        where external_id = 'page-prod') is not false then
    raise exception 'outbound hold on disabled connection';
  end if;
  if (select last_synced_revision from public.external_sync_links
        where external_id = 'page-prod') <> 1 then
    raise exception 'disabled inbound mutated last_synced';
  end if;
  if (select revision from public.memos
        where id = '22000000-0000-0000-0000-000000000060') <> 1 then
    raise exception 'disabled inbound mutated memo';
  end if;
end $$;

-- deactivate returns to disabled and clears work/holds.
update public.integration_connections
   set inbound_status = 'active', inbound_delta_hold = true
 where id = '21000000-0000-0000-0000-000000000061';
do $$
declare r jsonb;
begin
  r := integrations.deactivate_inbound('21000000-0000-0000-0000-000000000061');
  if r->>'inbound_status' <> 'disabled' then raise exception 'deactivate %', r; end if;
  if (select inbound_delta_hold from public.integration_connections
        where id = '21000000-0000-0000-0000-000000000061') is not false then
    raise exception 'deactivate left delta hold';
  end if;
end $$;

rollback;
