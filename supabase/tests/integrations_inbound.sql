-- Isolated PostgreSQL tests for inbound apply / work queue. Rolled back.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values (
  '21000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'notion',
  'connected',
  'Workspace A',
  'success',
  'active'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

do $$
declare r jsonb;
begin
  r := public.diurna_sync_memos_v2(
    '31000000-0000-0000-0000-000000000001',
    '[{"id":"22000000-0000-0000-0000-000000000001","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000001","user_id":"10000000-0000-0000-0000-000000000001","title":"Memo","content":"hello","position":3,"created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}}]'
  );
  if r->>'ok' <> 'true' then raise exception 'memo create failed %', r; end if;
  r := public.diurna_sync_calendar_v2(
    '31000000-0000-0000-0000-000000000002',
    '[{"id":"22000000-0000-0000-0000-000000000002","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000002","user_id":"10000000-0000-0000-0000-000000000001","title":"Event","event_date":"2026-09-09","is_completed":true,"note":"n","remind_at":"2026-09-09T08:00:00Z","created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}}]'
  );
  if r->>'ok' <> 'true' then raise exception 'calendar create failed %', r; end if;
  r := public.diurna_sync_inbox_v2(
    '31000000-0000-0000-0000-000000000003',
    '[{"id":"22000000-0000-0000-0000-000000000003","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000003","user_id":"10000000-0000-0000-0000-000000000001","content":"topic","item_type":"idea","inbox_column":"pending","position":1,"is_archived":false,"is_pinned":false,"is_topic":true,"parent_id":null,"due_date":"2026-09-10","priority":2,"is_completed":false,"created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}},{"id":"22000000-0000-0000-0000-000000000004","operation":"upsert","expected_revision":0,"payload":{"id":"22000000-0000-0000-0000-000000000004","user_id":"10000000-0000-0000-0000-000000000001","content":"child","item_type":"action","inbox_column":"pending","position":2,"is_archived":false,"is_pinned":false,"is_topic":false,"parent_id":"22000000-0000-0000-0000-000000000003","due_date":null,"priority":null,"is_completed":false,"created_at":"2026-09-09T00:00:00Z","updated_at":"2026-09-09T00:00:00Z"}}]'
  );
  if r->>'ok' <> 'true' then raise exception 'inbox create failed %', r; end if;
end $$;

-- authenticated must not execute apply
do $$ begin
  begin
    perform integrations.apply_external_change(
      '21000000-0000-0000-0000-000000000001',
      'memos',
      '22000000-0000-0000-0000-000000000001',
      'page-memo',
      'update',
      '{"title":"x"}'::jsonb,
      '{}'::jsonb,
      null,
      null
    );
    raise exception 'authenticated executed apply';
  exception
    when insufficient_privilege then null;
    when invalid_schema_name then null;
  end;
end $$;

reset role;

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values
  (
    '10000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion', 'memos', '22000000-0000-0000-0000-000000000001', 'page-memo',
    1, 'synced', 'ready'
  ),
  (
    '10000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion', 'calendar_events', '22000000-0000-0000-0000-000000000002', 'gcal-1',
    1, 'synced', 'ready'
  ),
  (
    '10000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion', 'inbox_items', '22000000-0000-0000-0000-000000000003', 'page-topic',
    1, 'synced', 'ready'
  );

-- Safe apply increments revision, last_synced, and generation.
do $$
declare r jsonb;
declare gen_before bigint;
declare gen_after bigint;
begin
  select generation into gen_before
    from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    'update',
    '{"title":"From Notion","content":"hello"}'::jsonb,
    '{"title":"From Notion"}'::jsonb,
    null,
    '2026-09-09T12:00:00Z'::timestamptz
  );
  if r->>'result' <> 'applied' then raise exception 'safe apply failed %', r; end if;
  if (r->>'revision_before')::bigint <> 1 or (r->>'revision_after')::bigint <> 2 then
    raise exception 'revision not +1 %', r;
  end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'memo revision not persisted';
  end if;
  if (select title from public.memos where id = '22000000-0000-0000-0000-000000000001') <> 'From Notion' then
    raise exception 'title not applied';
  end if;
  if (select position from public.memos where id = '22000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'position was overwritten';
  end if;
  if (select last_synced_revision from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'last_synced_revision not bumped';
  end if;
  select generation into gen_after
    from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000001';
  if gen_after <> gen_before + 1 then
    raise exception 'signal not incremented % -> %', gen_before, gen_after;
  end if;
end $$;

-- Calendar partial mapping preserves is_completed and remind_at.
do $$
declare r jsonb;
begin
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'calendar_events',
    '22000000-0000-0000-0000-000000000002',
    'gcal-1',
    'update',
    '{"title":"Renamed","event_date":"2026-09-11","note":"nn"}'::jsonb,
    '{}'::jsonb,
    'etag-1',
    '2026-09-09T12:00:00Z'::timestamptz
  );
  if r->>'result' <> 'applied' then raise exception 'calendar apply failed %', r; end if;
  if (select is_completed from public.calendar_events where id = '22000000-0000-0000-0000-000000000002') is not true then
    raise exception 'is_completed was cleared';
  end if;
  if (select remind_at from public.calendar_events where id = '22000000-0000-0000-0000-000000000002') is null then
    raise exception 'remind_at was cleared';
  end if;
end $$;

-- Unknown field rejected; no half write (transaction of the function).
do $$
declare rev bigint;
begin
  select revision into rev from public.memos where id = '22000000-0000-0000-0000-000000000001';
  begin
    perform integrations.apply_external_change(
      '21000000-0000-0000-0000-000000000001',
      'memos',
      '22000000-0000-0000-0000-000000000001',
      'page-memo',
      'update',
      '{"title":"x","position":9}'::jsonb,
      '{}'::jsonb, null, null
    );
    raise exception 'unknown field accepted';
  exception
    when raise_exception then
      if sqlerrm not like 'UNKNOWN_FIELD%' then raise; end if;
  end;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000001') <> rev then
    raise exception 'unknown field mutated revision';
  end if;
end $$;

-- Equal last_edited_time + different mapped fields continues (not silent duplicate).
do $$
declare r jsonb;
begin
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    'update',
    '{"title":"Second","content":"hello"}'::jsonb,
    '{}'::jsonb,
    null,
    '2026-09-09T12:00:00Z'::timestamptz
  );
  if r->>'result' <> 'applied' then
    raise exception 'equal timestamp with different mapped should apply %', r;
  end if;
end $$;

-- Diverged revision records conflict and does not overwrite.
do $$
declare r jsonb;
begin
  update public.external_sync_links
     set last_synced_revision = 1
   where entity_id = '22000000-0000-0000-0000-000000000001';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    'update',
    '{"title":"Should not apply"}'::jsonb,
    '{}'::jsonb, null, '2026-09-09T13:00:00Z'::timestamptz
  );
  if r->>'result' <> 'conflict' then raise exception 'expected conflict %', r; end if;
  if (select title from public.memos where id = '22000000-0000-0000-0000-000000000001') = 'Should not apply' then
    raise exception 'conflict overwrote entity';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000001') <> 'conflict' then
    raise exception 'inbound_state not conflict';
  end if;
  if not exists (
    select 1 from public.external_sync_conflicts
     where entity_id = '22000000-0000-0000-0000-000000000001' and status = 'open'
  ) then
    raise exception 'conflict row missing';
  end if;
end $$;

-- Mapped-equal is duplicate and does not bump revision.
do $$
declare r jsonb;
declare rev bigint;
begin
  update public.external_sync_links
     set inbound_state = 'ready', last_synced_revision = 3
   where entity_id = '22000000-0000-0000-0000-000000000001';
  select revision into rev from public.memos where id = '22000000-0000-0000-0000-000000000001';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    'update',
    jsonb_build_object(
      'title', (select title from public.memos where id = '22000000-0000-0000-0000-000000000001'),
      'content', (select content from public.memos where id = '22000000-0000-0000-0000-000000000001')
    ),
    '{}'::jsonb, null, '2026-09-09T14:00:00Z'::timestamptz
  );
  if r->>'result' <> 'duplicate' then raise exception 'expected duplicate %', r; end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000001') <> rev then
    raise exception 'duplicate bumped revision';
  end if;
end $$;

-- Stale provider updated_at.
do $$
declare r jsonb;
begin
  update public.external_sync_links
     set inbound_state = 'ready',
         last_synced_revision = (select revision from public.memos where id = '22000000-0000-0000-0000-000000000001'),
         external_updated_at = '2026-09-09T14:00:00Z'
   where entity_id = '22000000-0000-0000-0000-000000000001';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    'update',
    '{"title":"stale"}'::jsonb,
    '{}'::jsonb, null, '2026-09-09T13:00:00Z'::timestamptz
  );
  if r->>'result' <> 'stale' then raise exception 'expected stale %', r; end if;
end $$;

-- Inbox relationship conflict does not un-topic a parent with children.
do $$
declare r jsonb;
begin
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'inbox_items',
    '22000000-0000-0000-0000-000000000003',
    'page-topic',
    'update',
    '{"is_topic":false,"content":"topic"}'::jsonb,
    '{}'::jsonb, null, now()
  );
  if r->>'result' <> 'conflict' or r->>'reason' <> 'inbox_relationship' then
    raise exception 'expected inbox_relationship %', r;
  end if;
  if (select is_topic from public.inbox_items where id = '22000000-0000-0000-0000-000000000003') is not true then
    raise exception 'topic was un-topiced';
  end if;
end $$;

-- remote_deleted does not tombstone.
do $$
declare r jsonb;
begin
  update public.external_sync_links
     set inbound_state = 'ready',
         last_synced_revision = (
           select revision from public.calendar_events
            where id = '22000000-0000-0000-0000-000000000002'
         )
   where entity_id = '22000000-0000-0000-0000-000000000002';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'calendar_events',
    '22000000-0000-0000-0000-000000000002',
    'gcal-1',
    'remote_deleted',
    '{}'::jsonb, '{}'::jsonb, null, now()
  );
  if r->>'result' <> 'remote_deleted' then raise exception 'expected remote_deleted %', r; end if;
  if not exists (select 1 from public.calendar_events where id = '22000000-0000-0000-0000-000000000002') then
    raise exception 'entity hard-deleted';
  end if;
  if exists (
    select 1 from public.diurna_sync_tombstones
     where entity_id = '22000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'tombstone written';
  end if;
end $$;

-- Local edit after remote_deleted becomes a visible conflict.
do $$
declare r jsonb;
begin
  update public.calendar_events
     set revision = 3
   where id = '22000000-0000-0000-0000-000000000002';
  r := integrations.apply_external_change(
    '21000000-0000-0000-0000-000000000001',
    'calendar_events',
    '22000000-0000-0000-0000-000000000002',
    'gcal-1',
    'update',
    '{"title":"after delete"}'::jsonb,
    '{}'::jsonb, null, now()
  );
  if r->>'result' <> 'conflict' or r->>'reason' <> 'remote_deleted_with_local_edit' then
    raise exception 'expected remote_deleted_with_local_edit %', r;
  end if;
end $$;

-- Bootstrap drift does not bump revision.
do $$
declare r jsonb;
declare rev bigint;
begin
  select revision into rev from public.memos where id = '22000000-0000-0000-0000-000000000001';
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000001',
    'page-memo',
    null,
    now(),
    true,
    'bootstrap_remote_drift',
    '{}'::jsonb,
    '{"title":"remote"}'::jsonb
  );
  if r->>'result' <> 'conflict' then raise exception 'expected bootstrap drift %', r; end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000001') <> rev then
    raise exception 'bootstrap bumped revision';
  end if;
end $$;

-- Work queue: enqueue during processing sets rerun_requested; complete re-queues.
do $$
declare q jsonb;
declare c jsonb;
declare wid uuid;
begin
  q := integrations.enqueue_inbound_work(
    '21000000-0000-0000-0000-000000000001',
    'notion', 'notion_page', 'page-memo', '{}'::jsonb
  );
  wid := (q->>'id')::uuid;
  update integrations.inbound_work
     set status = 'processing', locked_until = now() + interval '3 minutes', attempts = 1
   where id = wid;
  q := integrations.enqueue_inbound_work(
    '21000000-0000-0000-0000-000000000001',
    'notion', 'notion_page', 'page-memo', '{}'::jsonb
  );
  if q->>'rerun_requested' <> 'true' then
    raise exception 'processing enqueue did not set rerun %', q;
  end if;
  if (select rerun_requested from integrations.inbound_work where id = wid) is not true then
    raise exception 'rerun_requested not stored';
  end if;
  c := integrations.complete_inbound_work(wid, null);
  if c->>'status' <> 'pending' or c->>'rerun' <> 'true' then
    raise exception 'complete did not re-queue %', c;
  end if;
  if (select status from integrations.inbound_work where id = wid) <> 'pending' then
    raise exception 'row not pending after rerun complete';
  end if;
  if (select rerun_requested from integrations.inbound_work where id = wid) is not false then
    raise exception 'rerun flag not cleared';
  end if;
end $$;

-- Stale lock reclaim preserves rerun_requested.
do $$
declare wid uuid;
declare n int;
begin
  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, status,
    rerun_requested, attempts, locked_until
  ) values (
    '21000000-0000-0000-0000-000000000001',
    'google', 'google_incremental', 'conn',
    'processing', true, 1, now() - interval '1 minute'
  ) returning id into wid;
  n := integrations.reclaim_stale_inbound_work();
  if n < 1 then raise exception 'reclaim changed no rows'; end if;
  if (select status from integrations.inbound_work where id = wid) <> 'pending' then
    raise exception 'stale lock not pending';
  end if;
  if (select rerun_requested from integrations.inbound_work where id = wid) is not true then
    raise exception 'reclaim dropped rerun_requested';
  end if;
end $$;

-- Atomic accept: inbound_events and inbound_work land together.
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'notion',
    'evt-atomic-1:21000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion_page',
    'page-atomic',
    '{"page_id":"page-atomic","event_type":"page.properties_updated"}'::jsonb
  );
  if r->>'accepted' <> 'true' then raise exception 'accept failed %', r; end if;
  if not exists (
    select 1 from integrations.inbound_events
     where event_key = 'evt-atomic-1:21000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'event row missing after accept';
  end if;
  if not exists (
    select 1 from integrations.inbound_work
     where dedup_key = 'page-atomic' and status = 'pending'
  ) then
    raise exception 'work row missing after accept';
  end if;
  r := integrations.accept_inbound_event(
    'notion',
    'evt-atomic-1:21000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion_page',
    'page-atomic',
    '{}'::jsonb
  );
  if r->>'duplicate' <> 'true' then raise exception 'duplicate event not detected %', r; end if;
  if (select count(*) from integrations.inbound_work where dedup_key = 'page-atomic') <> 1 then
    raise exception 'duplicate event created extra work';
  end if;
end $$;

-- Unsupported content freezes the link without bumping revision.
do $$
declare r jsonb;
declare rev bigint;
begin
  perform set_config('diurna.sync_protocol', '2', true);
  insert into public.memos (id, user_id, title, content, position, revision)
  values (
    '22000000-0000-0000-0000-000000000010',
    '10000000-0000-0000-0000-000000000001',
    'Freeze me',
    'plain',
    9,
    1
  );
  insert into public.external_sync_links (
    user_id, connection_id, provider, entity_type, entity_id, external_id,
    last_synced_revision, sync_status, inbound_state
  ) values (
    '10000000-0000-0000-0000-000000000001',
    '21000000-0000-0000-0000-000000000001',
    'notion', 'memos', '22000000-0000-0000-0000-000000000010', 'page-freeze',
    1, 'synced', 'ready'
  );
  select revision into rev from public.memos where id = '22000000-0000-0000-0000-000000000010';
  r := integrations.freeze_link_conflict(
    '21000000-0000-0000-0000-000000000001',
    'memos',
    '22000000-0000-0000-0000-000000000010',
    'page-freeze',
    'unsupported_content',
    '{"unsupported_body":true}'::jsonb,
    null,
    now()
  );
  if r->>'result' <> 'conflict' then raise exception 'freeze failed %', r; end if;
  if (select revision from public.memos where id = '22000000-0000-0000-0000-000000000010') <> rev then
    raise exception 'freeze bumped revision';
  end if;
  if (select title from public.memos where id = '22000000-0000-0000-0000-000000000010') <> 'Freeze me' then
    raise exception 'freeze mutated title';
  end if;
  if (select last_synced_revision from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000010') <> 1 then
    raise exception 'freeze advanced last_synced_revision';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000010') <> 'conflict' then
    raise exception 'freeze did not set inbound_state';
  end if;
end $$;

-- Protocol guard still rejects raw updates without the GUC.
do $$ begin
  perform set_config('diurna.sync_protocol', '', true);
  begin
    update public.memos set title = 'raw';
    raise exception 'raw update accepted';
  exception
    when raise_exception then
      if sqlerrm not like 'UPGRADE_REQUIRED:%' then raise; end if;
  end;
end $$;

-- User B cannot see A's conflicts.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select count(*) from public.external_sync_conflicts) <> 0 then
    raise exception 'conflict RLS leak';
  end if;
end $$;

rollback;
