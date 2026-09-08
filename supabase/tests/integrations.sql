-- Isolated PostgreSQL tests only. Run after bootstrap.sql + schema.sql.
begin;
insert into auth.users(id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002')
on conflict do nothing;

insert into public.integration_connections (
  id, user_id, provider, status, display_name, last_sync_status
) values (
  '21000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'notion',
  'connected',
  'Workspace A',
  'success'
);

insert into public.external_sync_links (
  user_id, connection_id, provider, entity_type, entity_id, external_id,
  last_synced_revision, sync_status
) values (
  '10000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  'notion',
  'inbox_items',
  '22000000-0000-0000-0000-000000000001',
  'page-a',
  1,
  'synced'
);

insert into integrations.credentials (
  connection_id, token_bundle_cipher, token_bundle_nonce
) values (
  '21000000-0000-0000-0000-000000000001',
  'cipher',
  decode('00112233445566778899aabb', 'hex')
);

-- User B cannot see user A's connection, links, or credentials.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$ begin
  if (select count(*) from public.integration_connections) <> 0 then
    raise exception 'connection RLS leak';
  end if;
  if (select count(*) from public.external_sync_links) <> 0 then
    raise exception 'link RLS leak';
  end if;
  begin
    perform count(*) from integrations.credentials;
    raise exception 'credentials schema leaked to authenticated';
  exception
    when insufficient_privilege then null;
    when invalid_schema_name then null;
  end;
end $$;

-- User A sees own metadata only; still cannot read credentials.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$ begin
  if (select count(*) from public.integration_connections) <> 1 then
    raise exception 'owner cannot select connection';
  end if;
  if (select count(*) from public.external_sync_links) <> 1 then
    raise exception 'owner cannot select links';
  end if;
  begin
    update public.integration_connections set display_name = 'hacked';
    if found then
      raise exception 'authenticated must not update connections';
    end if;
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform count(*) from integrations.credentials;
    raise exception 'credentials readable by authenticated';
  exception
    when insufficient_privilege then null;
    when invalid_schema_name then null;
  end;
end $$;

reset role;

-- Link user_id must match connection owner.
do $$ begin
  begin
    insert into public.external_sync_links (
      user_id, connection_id, provider, entity_type, entity_id, external_id,
      last_synced_revision
    ) values (
      '10000000-0000-0000-0000-000000000002',
      '21000000-0000-0000-0000-000000000001',
      'notion',
      'memos',
      '22000000-0000-0000-0000-000000000002',
      'page-b',
      1
    );
    raise exception 'mismatched link user_id accepted';
  exception
    when foreign_key_violation then null;
  end;
end $$;

-- One active connection per provider.
insert into public.integration_connections (
  id, user_id, provider, status
) values (
  '21000000-0000-0000-0000-000000000099',
  '10000000-0000-0000-0000-000000000001',
  'notion',
  'disconnected'
);
do $$ begin
  begin
    insert into public.integration_connections (
      user_id, provider, status
    ) values (
      '10000000-0000-0000-0000-000000000001',
      'notion',
      'connected'
    );
    raise exception 'second active notion connection accepted';
  exception
    when unique_violation then null;
  end;
end $$;

-- Deleting a connection removes links and credentials.
delete from public.integration_connections
 where id = '21000000-0000-0000-0000-000000000001';
do $$ begin
  if exists(select 1 from public.external_sync_links where connection_id = '21000000-0000-0000-0000-000000000001') then
    raise exception 'links survived connection delete';
  end if;
  if exists(select 1 from integrations.credentials where connection_id = '21000000-0000-0000-0000-000000000001') then
    raise exception 'credentials survived connection delete';
  end if;
end $$;

rollback;
