-- Review-fix SQL: handshake arm, outbound hold, remote_deleted local edit.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status, inbound_status
) values (
  '21000000-0000-0000-0000-000000000050',
  '10000000-0000-0000-0000-000000000001',
  'notion',
  'connected',
  'Workspace',
  'success',
  'active'
);

-- Handshake: unsolicited consume is rejected; armed consume works once.
insert into integrations.webhook_handshake_arms (
  provider, purpose, nonce_hash, expires_at
) values (
  'notion', 'initial', 'hash-initial', now() + interval '30 minutes'
);
do $$
declare r jsonb;
begin
  r := integrations.consume_handshake_arm('missing', false);
  if r->>'result' <> 'rejected' then raise exception 'unknown nonce %', r; end if;
  r := integrations.consume_handshake_arm('hash-initial', false);
  if r->>'result' <> 'ok' then raise exception 'initial arm failed %', r; end if;
  r := integrations.consume_handshake_arm('hash-initial', true);
  if r->>'result' <> 'rejected' then raise exception 'replay arm %', r; end if;
end $$;

insert into integrations.webhook_handshake_arms (
  provider, purpose, nonce_hash, expires_at
) values (
  'notion', 'initial', 'hash-active', now() + interval '30 minutes'
);
do $$
declare r jsonb;
begin
  r := integrations.consume_handshake_arm('hash-active', true);
  if r->>'reason' <> 'active_token' then
    raise exception 'active token not protected %', r;
  end if;
end $$;

insert into integrations.webhook_handshake_arms (
  provider, purpose, nonce_hash, expires_at
) values (
  'notion', 'rotate', 'hash-rotate', now() + interval '30 minutes'
);
do $$
declare r jsonb;
begin
  r := integrations.consume_handshake_arm('hash-rotate', true);
  if r->>'result' <> 'ok' then raise exception 'rotate failed %', r; end if;
end $$;

-- Webhook accept sets outbound_hold.
select set_config('diurna.sync_protocol', '2', true);
insert into public.memos (id, user_id, title, content, position, revision)
values (
  '22000000-0000-0000-0000-000000000050',
  '10000000-0000-0000-0000-000000000001',
  'Note',
  'body',
  1,
  1
);
insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status, inbound_state
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000050',
  'notion', 'memos', '22000000-0000-0000-0000-000000000050', 'page-note',
  1, 'synced', 'ready'
);
do $$
declare r jsonb;
begin
  r := integrations.accept_inbound_event(
    'notion', 'evt-hold',
    '21000000-0000-0000-0000-000000000050',
    'notion_page',
    'page-note',
    '{}'::jsonb
  );
  if r->>'accepted' <> 'true' then raise exception 'accept failed %', r; end if;
  if (select outbound_hold from public.external_sync_links
        where external_id = 'page-note') is not true then
    raise exception 'outbound hold not set';
  end if;
end $$;

-- remote_deleted + later local revision becomes a visible conflict.
update public.external_sync_links
   set inbound_state = 'remote_deleted', outbound_hold = false
 where entity_id = '22000000-0000-0000-0000-000000000050';
update public.memos set revision = 2, title = 'Local edit'
 where id = '22000000-0000-0000-0000-000000000050';
do $$
declare r jsonb;
begin
  r := integrations.freeze_link_conflict(
    '21000000-0000-0000-0000-000000000050',
    'memos',
    '22000000-0000-0000-0000-000000000050',
    'page-note',
    'remote_deleted_with_local_edit',
    '{"local_edit":true}'::jsonb,
    null,
    now()
  );
  if r->>'result' <> 'conflict' then raise exception 'expected conflict %', r; end if;
  if (select inbound_state from public.external_sync_links
        where entity_id = '22000000-0000-0000-0000-000000000050') <> 'conflict' then
    raise exception 'inbound_state not conflict';
  end if;
  if (select title from public.memos where id = '22000000-0000-0000-0000-000000000050') <> 'Local edit' then
    raise exception 'local edit overwritten';
  end if;
end $$;

-- Heartbeat keeps a waiting processing lease from being reclaimed.
do $$
declare a uuid;
declare b uuid;
declare hb jsonb;
declare n int;
begin
  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, status, attempts, locked_until
  ) values (
    '21000000-0000-0000-0000-000000000050',
    'notion', 'bootstrap_notion', 'lease-a', 'processing', 1, now() - interval '1 minute'
  ) returning id into a;
  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, status, attempts, locked_until
  ) values (
    '21000000-0000-0000-0000-000000000050',
    'notion', 'notion_page', 'lease-b', 'processing', 1, now() - interval '1 minute'
  ) returning id into b;
  hb := integrations.heartbeat_inbound_work(b, interval '3 minutes');
  if hb->>'result' <> 'ok' then raise exception 'heartbeat failed %', hb; end if;
  n := integrations.reclaim_stale_inbound_work();
  if n < 1 then raise exception 'expired A was not reclaimed'; end if;
  if (select status from integrations.inbound_work where id = a) <> 'pending' then
    raise exception 'A still processing after reclaim';
  end if;
  if (select status from integrations.inbound_work where id = b) <> 'processing' then
    raise exception 'live waiting worker B was reclaimed';
  end if;
end $$;

rollback;
