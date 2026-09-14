-- Isolated tests: never execute against hosted user data.
begin;
insert into auth.users(id) values ('10000000-0000-0000-0000-000000000901'),('10000000-0000-0000-0000-000000000902');
insert into public.integration_connections(id,user_id,provider,status,inbound_status,container) values
 ('20000000-0000-0000-0000-000000000901','10000000-0000-0000-0000-000000000901','google','connected','active','{"calendar_id":"managed"}'),
 ('20000000-0000-0000-0000-000000000902','10000000-0000-0000-0000-000000000901','notion','connected','active','{"inbox_ds":"inbox","memo_ds":"memo","diary_ds":"diary"}');
do $$
declare
 c uuid := '20000000-0000-0000-0000-000000000901';
 n uuid := '20000000-0000-0000-0000-000000000902';
 u uuid := '10000000-0000-0000-0000-000000000901';
 r jsonb; again jsonb; local_id uuid; recovered_id uuid; before_gen bigint; count_before bigint;
begin
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','manual',null,
   '{"title":"Manual","event_date":"2026-09-10"}','{}','e1','2026-09-10T00:00:00Z');
 if r->>'result'<>'created' then raise exception 'create %',r; end if;
 local_id:=(r->>'entity_id')::uuid;
 if not exists(select 1 from public.calendar_events where id=local_id and user_id=u and revision=1 and not is_completed) then raise exception 'row defaults'; end if;
 if not exists(select 1 from public.external_sync_links where entity_id=local_id and last_synced_revision=1 and sync_status='synced'
   and inbound_state='ready' and external_etag='e1' and external_updated_at is not null and last_synced_at is not null
   and last_remote_event_at is not null and not outbound_hold) then raise exception 'link baseline'; end if;
 select generation into before_gen from public.diurna_sync_signals where user_id=u;
 if before_gen<>1 then raise exception 'create signal %',before_gen; end if;
 again:=integrations.reconcile_external_object(c,'google','managed','calendar_events','manual',gen_random_uuid(),
   '{"title":"Manual","event_date":"2026-09-10"}','{}','e1',null);
 if again->>'result'<>'existing' or again->>'entity_id'<>r->>'entity_id' then raise exception 'retry %',again; end if;
 if (select generation from public.diurna_sync_signals where user_id=u)<>before_gen then raise exception 'retry signal'; end if;
 again:=integrations.apply_external_change(c,'calendar_events',local_id,'manual','update','{"title":"Edited"}','{}','e2','2026-09-10T01:00:00Z');
 if again->>'result'<>'applied' or (again->>'revision_after')::int<>2 then raise exception 'subsequent update %',again; end if;
 -- Recovery compares under the same transaction; no entity insert or signal.
 delete from public.external_sync_links where entity_id=local_id;
 select generation into before_gen from public.diurna_sync_signals where user_id=u;
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','manual',local_id,'{"title":"Edited","event_date":"2026-09-10"}','{}','e2',null);
 if r->>'result'<>'recovered' then raise exception 'recover %',r; end if;
 if (select generation from public.diurna_sync_signals where user_id=u)<>before_gen then raise exception 'recovery changed signal'; end if;
 delete from public.external_sync_links where entity_id=local_id;
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','manual',local_id,'{"title":"Drift"}','{}','e3',null);
 if r->>'result'<>'conflict' then raise exception 'recovery drift %',r; end if;
 if (select title from public.calendar_events where id=local_id)<>'Edited' then raise exception 'recovery overwrote'; end if;
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','copy',local_id,'{"title":"Copy","event_date":"2026-09-10"}','{}',null,null);
 if r->>'reason'<>'entity_already_linked' then raise exception 'stole existing link %',r; end if;
 -- Missing ID never dictates the new UUID.
 recovered_id:=gen_random_uuid();
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','missing',recovered_id,'{"title":"New","event_date":"2026-09-10"}','{}',null,null);
 if r->>'result'<>'created' or (r->>'entity_id')::uuid=recovered_id then raise exception 'missing candidate %',r; end if;
 -- A foreign user's real UUID cannot be recovered.
 perform set_config('diurna.sync_protocol','2',true);
 insert into public.calendar_events(id,user_id,title,event_date) values(recovered_id,'10000000-0000-0000-0000-000000000902','Foreign','2026-09-10');
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','spoof',recovered_id,'{"title":"Own","event_date":"2026-09-10"}','{}',null,null);
 if r->>'result'<>'created' or (r->>'entity_id')::uuid=recovered_id then raise exception 'foreign candidate %',r; end if;
 if exists(select 1 from public.external_sync_links where entity_id=recovered_id) then raise exception 'foreign link'; end if;
 insert into public.diurna_sync_tombstones(user_id,entity_type,entity_id,revision) values(u,'calendar_events',gen_random_uuid(),2) returning entity_id into recovered_id;
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','deleted-id',recovered_id,'{"title":"Deleted","event_date":"2026-09-10"}','{}',null,null);
 if r->>'reason'<>'tombstone' then raise exception 'resurrected %',r; end if;
 r:=integrations.reconcile_external_object(c,'google','other','calendar_events','wrong-container',null,'{}','{}',null,null);
 if r->>'reason'<>'container_mismatch' then raise exception 'container %',r; end if;
 r:=integrations.reconcile_external_object(c,'notion','inbox','inbox_items','wrong-provider',null,'{}','{}',null,null);
 if r->>'reason'<>'container_mismatch' then raise exception 'provider %',r; end if;
 -- All Notion entity types/defaults; required-date policy is retryable.
 r:=integrations.reconcile_external_object(n,'notion','inbox','inbox_items','page-inbox',null,'{"content":"Idea"}','{}',null,null);
 if r->>'result'<>'created' then raise exception 'inbox %',r; end if;
 if not exists(select 1 from public.inbox_items where id=(r->>'entity_id')::uuid and inbox_column='pending' and item_type is null and parent_id is null and not is_completed) then raise exception 'inbox defaults'; end if;
 r:=integrations.reconcile_external_object(n,'notion','memo','memos','page-memo',null,'{"title":"Memo","content":"One\n\nTwo"}','{}',null,null);
 if r->>'result'<>'created' then raise exception 'memo %',r; end if;
 local_id:=(r->>'entity_id')::uuid;
 if not exists(select 1 from integrations.remote_object_status where connection_id=n and external_id='page-memo' and metadata_pending) then raise exception 'writeback not durable'; end if;
 again:=integrations.reconcile_external_object(n,'notion','memo','memos','page-memo',null,'{"title":"Memo"}','{}',null,null);
 if again->>'entity_id'<>r->>'entity_id' then raise exception 'notion duplicate'; end if;
 -- Same external ID under another otherwise valid entity type is rejected.
 again:=integrations.reconcile_external_object(n,'notion','diary','diary_entries','page-memo',null,'{}','{}',null,null);
 if again->>'reason'<>'identity_mismatch' then raise exception 'type hijack %',again; end if;
 delete from public.external_sync_links where entity_id=local_id;
 r:=integrations.reconcile_external_object(n,'notion','memo','memos','page-memo',local_id,'{"title":"Memo","content":"One\n\nTwo"}','{}',null,null);
 if r->>'result'<>'recovered' then raise exception 'notion recovery %',r; end if;
 r:=integrations.reconcile_external_object(n,'notion','diary','diary_entries','page-diary',null,'{"title":"Day","content":"Body"}','{}',null,null);
 if r->>'reason'<>'missing_required_fields' then raise exception 'diary without date %',r; end if;
 r:=integrations.reconcile_external_object(n,'notion','diary','diary_entries','page-diary',null,'{"title":"Day","content":"Body","entry_date":"2026-09-10","mood":"happy"}','{}',null,null);
 if r->>'result'<>'created' then raise exception 'diary retry %',r; end if;
 if not exists(select 1 from public.diary_entries where id=(r->>'entity_id')::uuid and entry_date='2026-09-10' and mood='happy' and tags='{}') then raise exception 'diary defaults'; end if;
 -- Invalid insertion rolls back both row and link, including trigger signal.
 select count(*) into count_before from public.calendar_events;
 select generation into before_gen from public.diurna_sync_signals where user_id=u;
 begin
   perform integrations.reconcile_external_object(c,'google','managed','calendar_events','bad',null,'{"title":"Bad","event_date":"not-a-date"}','{}',null,null);
   raise exception 'expected invalid date';
 exception when invalid_datetime_format then null;
 end;
 if (select count(*) from public.calendar_events)<>count_before or exists(select 1 from public.external_sync_links where external_id='bad')
   or (select generation from public.diurna_sync_signals where user_id=u)<>before_gen then raise exception 'partial create'; end if;
 update public.integration_connections set inbound_status='disabled' where id=c;
 r:=integrations.reconcile_external_object(c,'google','managed','calendar_events','disabled',null,'{"title":"No","event_date":"2026-09-10"}','{}',null,null);
 if r->>'reason'<>'inbound_disabled' then raise exception 'disabled %',r; end if;
end $$;
do $$ begin
 if has_function_privilege('authenticated','integrations.reconcile_external_object(uuid,text,text,text,text,uuid,jsonb,jsonb,text,timestamptz,text)','execute')
 or has_function_privilege('anon','integrations.reconcile_external_object(uuid,text,text,text,text,uuid,jsonb,jsonb,text,timestamptz,text)','execute')
 then raise exception 'public execute'; end if;
end $$;
-- Clients see remote-created objects through the ordinary authenticated v2 pull.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000901',true);
do $$ declare snapshot jsonb; begin
 snapshot:=public.diurna_snapshot_v2();
 if jsonb_array_length(snapshot->'memos')=0 or jsonb_array_length(snapshot->'calendar_events')=0
   or jsonb_array_length(snapshot->'diary_entries')=0 or jsonb_array_length(snapshot->'inbox_items')=0
 then raise exception 'remote create missing from client snapshot'; end if;
 if exists(select 1 from jsonb_array_elements(snapshot->'calendar_events') r
   where r->>'user_id'<>'10000000-0000-0000-0000-000000000901') then raise exception 'foreign snapshot row'; end if;
end $$;
reset role;

-- Fail precisely between local INSERT (including its signal) and link INSERT.
create function pg_temp.reject_fixture_link() returns trigger language plpgsql as $$
begin if new.external_id='rollback-link' then raise exception 'fixture_link_failure'; end if; return new; end $$;
create trigger reject_fixture_link before insert on public.external_sync_links for each row execute function pg_temp.reject_fixture_link();
do $$ declare before_rows bigint; before_generation bigint; begin
 update public.integration_connections set inbound_status='active' where id='20000000-0000-0000-0000-000000000901';
 select count(*) into before_rows from public.calendar_events;
 select generation into before_generation from public.diurna_sync_signals where user_id='10000000-0000-0000-0000-000000000901';
 begin
  perform integrations.reconcile_external_object('20000000-0000-0000-0000-000000000901','google','managed','calendar_events','rollback-link',null,
    '{"title":"Rollback","event_date":"2026-09-10"}','{}',null,null);
  raise exception 'link insert should have failed';
 exception when raise_exception then if sqlerrm<>'fixture_link_failure' then raise; end if;
 end;
 if (select count(*) from public.calendar_events)<>before_rows
   or (select generation from public.diurna_sync_signals where user_id='10000000-0000-0000-0000-000000000901')<>before_generation
 then raise exception 'half-created entity/signal escaped rollback'; end if;
end $$;
rollback;
