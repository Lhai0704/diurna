-- Stale bootstrap_remote_drift may close only on a fresh equal baseline.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000180')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values (
  '21000000-0000-0000-0000-000000000180',
  '10000000-0000-0000-0000-000000000180',
  'notion', 'connected', 'Date baseline', 'success', 'bootstrapping'
);

select set_config('diurna.sync_protocol', '2', true);

insert into public.diary_entries (
  id, user_id, entry_date, title, content, mood, tags, revision
) values
  (
    '22000000-0000-0000-0000-000000000180',
    '10000000-0000-0000-0000-000000000180',
    '2026-09-09', 'Stale', 'same body', 'ok', '{}', 1
  ),
  (
    '22000000-0000-0000-0000-000000000181',
    '10000000-0000-0000-0000-000000000180',
    '2026-09-08', 'Still drifting', 'local body', 'ok', '{}', 1
  ),
  (
    '22000000-0000-0000-0000-000000000182',
    '10000000-0000-0000-0000-000000000180',
    '2026-09-07', 'Unsupported', 'plain', null, '{}', 1
  ),
  (
    '22000000-0000-0000-0000-000000000183',
    '10000000-0000-0000-0000-000000000180',
    '2026-09-06', 'Advanced', 'body', null, '{}', 2
  ),
  (
    '22000000-0000-0000-0000-000000000184',
    '10000000-0000-0000-0000-000000000180',
    '2026-09-05', 'Deleted edit', 'body', null, '{}', 1
  );

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state, outbound_hold
) values
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000180', 'page-stale',
    1, 'synced', 'conflict', true
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000181', 'page-drift',
    1, 'synced', 'conflict', true
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000182', 'page-unsupported',
    1, 'synced', 'conflict', true
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000183', 'page-advanced',
    1, 'synced', 'conflict', true
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000184', 'page-deleted',
    1, 'synced', 'conflict', true
  );

insert into public.external_sync_conflicts (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  status, reason, local_revision, last_synced_revision, local_snapshot, remote_snapshot
) values
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000180', 'page-stale',
    'open', 'bootstrap_remote_drift', 1, 1, '{}'::jsonb, '{}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000181', 'page-drift',
    'open', 'bootstrap_remote_drift', 1, 1, '{}'::jsonb, '{}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000182', 'page-unsupported',
    'open', 'unsupported_content', 1, 1, '{}'::jsonb, '{}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000183', 'page-advanced',
    'open', 'bootstrap_remote_drift', 2, 1, '{}'::jsonb, '{}'::jsonb
  ),
  (
    '10000000-0000-0000-0000-000000000180',
    '21000000-0000-0000-0000-000000000180',
    'notion', 'diary_entries', '22000000-0000-0000-0000-000000000184', 'page-deleted',
    'open', 'remote_deleted_with_local_edit', 1, 1, '{}'::jsonb, '{}'::jsonb
  );

-- Fresh equal baseline dismisses only stale bootstrap_remote_drift.
do $$
declare r jsonb;
declare rev bigint;
declare gen_before bigint;
declare gen_after bigint;
begin
  select revision into rev from public.diary_entries
   where id = '22000000-0000-0000-0000-000000000180';
  select generation into gen_before from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000180';
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000180',
    'page-stale',
    null,
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'result' <> 'ready' then
    raise exception 'stale equal failed %', r;
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000180') <> 'ready' then
    raise exception 'stale equal not ready';
  end if;
  if (select outbound_hold from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000180') is not false then
    raise exception 'stale equal left outbound_hold';
  end if;
  if (select status from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000180') <> 'dismissed' then
    raise exception 'stale conflict not dismissed';
  end if;
  if (select resolved_at from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000180') is null then
    raise exception 'stale conflict missing resolved_at';
  end if;
  if (select last_synced_revision from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000180') <> 1 then
    raise exception 'stale equal advanced last_synced';
  end if;
  if (select revision from public.diary_entries
        where id = '22000000-0000-0000-0000-000000000180') <> rev then
    raise exception 'stale equal bumped revision';
  end if;
  select generation into gen_after from public.diurna_sync_signals
   where user_id = '10000000-0000-0000-0000-000000000180';
  if gen_after is distinct from gen_before then
    raise exception 'stale equal bumped signal';
  end if;
end $$;

-- Fresh drift keeps bootstrap_remote_drift open.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000181',
    'page-drift',
    null,
    now(),
    true,
    'bootstrap_remote_drift',
    '{}'::jsonb,
    '{"title":"remote"}'::jsonb
  );
  if r->>'result' <> 'conflict' then
    raise exception 'fresh drift %', r;
  end if;
  if (select status from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000181') <> 'open' then
    raise exception 'fresh drift dismissed';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000181') <> 'conflict' then
    raise exception 'fresh drift not conflict';
  end if;
end $$;

-- Local revision past last_synced_revision keeps bootstrap_remote_drift open.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000183',
    'page-advanced',
    null,
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'result' <> 'conflict' then
    raise exception 'advanced local %', r;
  end if;
  if (select status from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000183') <> 'open' then
    raise exception 'advanced local dismissed';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000183') <> 'conflict' then
    raise exception 'advanced local not conflict';
  end if;
end $$;

-- unsupported_content stays frozen on a fresh equal baseline.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000182',
    'page-unsupported',
    null,
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'result' <> 'conflict' or r->>'reason' <> 'unsupported_content' then
    raise exception 'unsupported equal %', r;
  end if;
  if (select status from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000182') <> 'open' then
    raise exception 'unsupported_content was dismissed';
  end if;
  if (select reason from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000182') <> 'unsupported_content' then
    raise exception 'unsupported reason changed';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000182') <> 'conflict' then
    raise exception 'unsupported equal unfroze inbound_state';
  end if;
  if (select outbound_hold from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000182') is not true then
    raise exception 'unsupported equal cleared outbound_hold';
  end if;
end $$;

-- remote_deleted_with_local_edit stays frozen on a fresh equal baseline.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000184',
    'page-deleted',
    null,
    now(),
    false,
    null,
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'result' <> 'conflict'
     or r->>'reason' <> 'remote_deleted_with_local_edit' then
    raise exception 'deleted-edit equal %', r;
  end if;
  if (select status from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000184') <> 'open' then
    raise exception 'remote_deleted_with_local_edit was dismissed';
  end if;
  if (select reason from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000184')
       <> 'remote_deleted_with_local_edit' then
    raise exception 'deleted-edit reason changed';
  end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000184') <> 'conflict' then
    raise exception 'deleted-edit equal unfroze inbound_state';
  end if;
  if (select outbound_hold from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000184') is not true then
    raise exception 'deleted-edit equal cleared outbound_hold';
  end if;
end $$;

-- Non-bootstrap open conflicts are not rewritten by _open_conflict.
do $$
declare r jsonb;
begin
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000182',
    'page-unsupported',
    null,
    now(),
    true,
    'bootstrap_remote_drift',
    '{}'::jsonb,
    '{"title":"should not upsert"}'::jsonb
  );
  if r->>'result' <> 'conflict' or r->>'reason' <> 'unsupported_content' then
    raise exception 'unsupported drift overwrite %', r;
  end if;
  if (select reason from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000182'
          and status = 'open') <> 'unsupported_content' then
    raise exception 'unsupported reason overwritten on drift';
  end if;

  update public.diary_entries
     set revision = 3
   where id = '22000000-0000-0000-0000-000000000184';
  r := integrations.bootstrap_link_version(
    '21000000-0000-0000-0000-000000000180',
    'diary_entries',
    '22000000-0000-0000-0000-000000000184',
    'page-deleted',
    null,
    now(),
    false,
    'bootstrap_remote_drift',
    '{}'::jsonb,
    '{}'::jsonb
  );
  if r->>'result' <> 'conflict'
     or r->>'reason' <> 'remote_deleted_with_local_edit' then
    raise exception 'deleted-edit advanced overwrite %', r;
  end if;
  if (select reason from public.external_sync_conflicts
        where entity_id = '22000000-0000-0000-0000-000000000184'
          and status = 'open') <> 'remote_deleted_with_local_edit' then
    raise exception 'deleted-edit reason overwritten on advanced revision';
  end if;
end $$;

rollback;
