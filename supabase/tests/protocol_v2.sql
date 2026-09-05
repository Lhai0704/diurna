-- Run ONLY against an isolated test database initialized with schema.sql.
begin;
insert into auth.users(id) values ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002') on conflict do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$
declare result jsonb; changes jsonb;
begin
 changes := '[{"id":"20000000-0000-0000-0000-000000000001","operation":"upsert","expected_revision":0,"payload":{"id":"20000000-0000-0000-0000-000000000001","user_id":"10000000-0000-0000-0000-000000000001","title":"MCP","content":"initial","position":0,"created_at":"2026-09-05T00:00:00Z","updated_at":"2026-09-05T00:00:00Z"}}]';
 result := public.diurna_sync_memos_v2('30000000-0000-0000-0000-000000000001',changes);
 if result->>'ok' <> 'true' then raise exception 'create failed: %',result; end if;
 if public.diurna_sync_memos_v2('30000000-0000-0000-0000-000000000001',changes) <> result then raise exception 'receipt retry failed'; end if;
 if (select count(*) from public.memos) <> 1 then raise exception 'duplicate create'; end if;
 result := public.diurna_sync_memos_v2('30000000-0000-0000-0000-000000000002',changes);
 if result->>'code' <> 'CONFLICT' then raise exception 'stale revision accepted'; end if;
 if (public.diurna_snapshot_v2()->>'complete') <> 'true' then raise exception 'snapshot incomplete'; end if;
 if (public.diurna_snapshot_v2()->>'generation')::int <> 1 then raise exception 'signal generation mismatch'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ begin
 if (select count(*) from public.memos) <> 0 then raise exception 'RLS leak'; end if;
 if (select count(*) from public.diurna_sync_receipts) <> 0 then raise exception 'receipt leak'; end if;
 if (select count(*) from public.diurna_sync_signals) <> 0 then raise exception 'signal leak'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('diurna.sync_protocol','',true);
do $$ begin
 begin
  update public.memos set title='legacy overwrite';
  raise exception 'legacy write accepted';
 exception when raise_exception then
  if sqlerrm not like 'UPGRADE_REQUIRED:%' then raise; end if;
 end;
end $$;
do $$ declare r jsonb; begin
 r:=public.diurna_sync_memos_v2('30000000-0000-0000-0000-000000000003','[{"id":"20000000-0000-0000-0000-000000000001","operation":"delete","expected_revision":1,"payload":null}]');
 if r->>'ok'<>'true' then raise exception 'delete failed'; end if;
 r:=public.diurna_sync_memos_v2('30000000-0000-0000-0000-000000000004','[{"id":"20000000-0000-0000-0000-000000000001","operation":"upsert","expected_revision":0,"payload":null}]');
 if r->>'code'<>'CONFLICT' then raise exception 'deleted ID resurrected'; end if;
 if (public.diurna_snapshot_v2()->>'generation')::int <> 2 then raise exception 'delete signal missing'; end if;
end $$;
-- Large snapshots are one JSON value, not a PostgREST row-limited query.
do $$ declare changes jsonb; r jsonb; begin
 select jsonb_agg(jsonb_build_object(
  'id',('40000000-0000-0000-0000-'||lpad(n::text,12,'0')),
  'operation','upsert','expected_revision',0,
  'payload',jsonb_build_object('id',('40000000-0000-0000-0000-'||lpad(n::text,12,'0')),
   'user_id',auth.uid(),'title','bulk '||n,'content','','position',n,
   'created_at','2026-09-05T00:00:00Z','updated_at','2026-09-05T00:00:00Z')))
 into changes from generate_series(1,1001) n;
 r:=public.diurna_sync_memos_v2('50000000-0000-0000-0000-000000000001',changes);
 if r->>'ok'<>'true' then raise exception 'bulk create failed'; end if;
 if jsonb_array_length(public.diurna_snapshot_v2()->'memos')<>1001 then raise exception 'snapshot truncated'; end if;
 -- One stale member must reject the entire reorder group.
 changes:=jsonb_set(changes,'{0,expected_revision}','1'::jsonb);
 changes:=jsonb_set(changes,'{0,payload,title}','"must not commit"'::jsonb);
 r:=public.diurna_sync_memos_v2('50000000-0000-0000-0000-000000000002',changes);
 if r->>'code'<>'CONFLICT' then raise exception 'group conflict not detected'; end if;
 if exists(select 1 from public.memos where title='must not commit') then raise exception 'partial group committed'; end if;
end $$;
rollback;
