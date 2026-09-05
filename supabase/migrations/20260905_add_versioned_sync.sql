-- Additive protocol v2. Run on a backup-tested database before enforcing v2.
begin;
create table if not exists public.diurna_sync_tombstones (
 user_id uuid not null references auth.users(id) on delete cascade,
 entity_type text not null check(entity_type in ('inbox_items','calendar_events','diary_entries','memos')),
 entity_id uuid not null, revision bigint not null,
 primary key(user_id,entity_type,entity_id));
create table if not exists public.diurna_sync_receipts (
 user_id uuid not null references auth.users(id) on delete cascade,
 attempt_id uuid not null, entity_type text not null, request jsonb not null, response jsonb not null,
 primary key(user_id,attempt_id));
create table if not exists public.diurna_sync_signals (
 user_id uuid primary key references auth.users(id) on delete cascade,
 generation bigint not null default 0);
alter table public.diurna_sync_tombstones enable row level security;
grant select,insert,update,delete on public.diurna_sync_tombstones to authenticated;
drop policy if exists own on public.diurna_sync_tombstones;
create policy own on public.diurna_sync_tombstones to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
alter table public.diurna_sync_receipts enable row level security;
grant select,insert,update,delete on public.diurna_sync_receipts to authenticated;
drop policy if exists own on public.diurna_sync_receipts;
create policy own on public.diurna_sync_receipts to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
alter table public.diurna_sync_signals enable row level security;
grant select,insert,update,delete on public.diurna_sync_signals to authenticated;
drop policy if exists own on public.diurna_sync_signals;
create policy own on public.diurna_sync_signals to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
alter table public.inbox_items add column if not exists revision bigint not null default 1;
alter table public.calendar_events add column if not exists revision bigint not null default 1;
alter table public.diary_entries add column if not exists revision bigint not null default 1;
alter table public.memos add column if not exists revision bigint not null default 1;
create or replace function public.diurna_snapshot_v2() returns jsonb
language sql stable security invoker set search_path = pg_catalog, public as $$
 select jsonb_build_object('protocol',2,'complete',true,'user_id',auth.uid(),
 'generation',coalesce((select generation from public.diurna_sync_signals where user_id=auth.uid()),0),
 'inbox_items',coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.inbox_items r where r.user_id=auth.uid()),'[]'::jsonb),
 'calendar_events',coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.calendar_events r where r.user_id=auth.uid()),'[]'::jsonb),
 'diary_entries',coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.diary_entries r where r.user_id=auth.uid()),'[]'::jsonb),
 'memos',coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.memos r where r.user_id=auth.uid()),'[]'::jsonb),
 'tombstones',coalesce((select jsonb_agg(to_jsonb(r)) from public.diurna_sync_tombstones r where r.user_id=auth.uid()),'[]'::jsonb)) where auth.uid() is not null;
$$;
revoke all on function public.diurna_snapshot_v2() from public,anon;
grant execute on function public.diurna_snapshot_v2() to authenticated;
create or replace function public.diurna_sync_inbox_v2(attempt_id uuid, changes jsonb) returns jsonb
language plpgsql security invoker set search_path = pg_catalog, public as $$
declare c jsonb; p jsonb; current_row jsonb; current_revision bigint; next_revision bigint;
 receipt public.diurna_sync_receipts%rowtype; revisions jsonb := '[]'::jsonb; response jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if attempt_id is null or jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes)=0 then raise exception 'VALIDATION'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into receipt from public.diurna_sync_receipts where user_id=auth.uid() and diurna_sync_receipts.attempt_id=diurna_sync_inbox_v2.attempt_id;
 if found then
  if receipt.entity_type <> 'inbox_items' or receipt.request <> changes then raise exception 'REQUEST_ID_REUSED'; end if;
  return receipt.response;
 end if;
 if (select count(*) from jsonb_array_elements(changes)) <> (select count(distinct x->>'id') from jsonb_array_elements(changes) x) then raise exception 'DUPLICATE_ID'; end if;
 for c in select value from jsonb_array_elements(changes) loop
  if exists(select 1 from jsonb_object_keys(c) k where k not in ('id','operation','payload','expected_revision')) or not(c ?& array['id','operation','payload','expected_revision']) or jsonb_typeof(c->'expected_revision') <> 'number' or c->>'operation' is null or c->>'operation' not in ('upsert','delete') then raise exception 'VALIDATION'; end if;
  select to_jsonb(r) into current_row from public.inbox_items r where r.id=(c->>'id')::uuid and r.user_id=auth.uid() for update;
  current_revision := (current_row->>'revision')::bigint;
  if current_row is null then
   select revision into current_revision from public.diurna_sync_tombstones where user_id=auth.uid() and entity_type='inbox_items' and entity_id=(c->>'id')::uuid;
   -- Any tombstone prevents recreation under the same ID.
   if found or (c->>'expected_revision')::bigint <> 0 then
    return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(jsonb_build_object('id',c->>'id','deleted',true)));
   end if;
  elsif current_revision is distinct from (c->>'expected_revision')::bigint then
   return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(current_row));
  end if;
  if (current_row->>'is_topic')::boolean and (c->>'operation'='delete' or (c->'payload'->>'is_archived')::boolean or not (c->'payload'->>'is_topic')::boolean) then
   if exists(select 1 from public.inbox_items child where child.user_id=auth.uid() and child.parent_id=(c->>'id')::uuid and not exists(select 1 from jsonb_array_elements(changes) x where (x->>'id')::uuid=child.id and (x->>'operation'='delete' or x->'payload'->>'parent_id' is null))) then
    return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(current_row));
   end if;
  end if;
  if c->>'operation'='upsert' then
   p:=c->'payload';
   if jsonb_typeof(p) is distinct from 'object' then raise exception 'VALIDATION'; end if;
   if p->>'user_id' is distinct from auth.uid()::text or p->>'id' is distinct from c->>'id' then raise exception 'IDENTITY_MISMATCH'; end if;
   if exists(select 1 from jsonb_object_keys(p) k where k not in ('id','user_id','content','item_type','inbox_column','position','is_archived','is_pinned','is_topic','parent_id','due_date','priority','is_completed','created_at','updated_at')) then raise exception 'UNKNOWN_FIELD'; end if;
  end if;
 end loop;
 perform set_config('diurna.sync_protocol','2',true);
 for c in select value from jsonb_array_elements(changes) order by case when value->'payload'->>'is_topic'='true' then 0 else 1 end loop
  select revision+1 into next_revision from public.inbox_items where id=(c->>'id')::uuid and user_id=auth.uid();
  next_revision:=coalesce(next_revision,1);
  if c->>'operation'='delete' then
   delete from public.inbox_items where id=(c->>'id')::uuid and user_id=auth.uid();
   insert into public.diurna_sync_tombstones values(auth.uid(),'inbox_items',(c->>'id')::uuid,next_revision);
  else
   p:=c->'payload';
   insert into public.inbox_items(id,user_id,content,item_type,inbox_column,position,is_archived,is_pinned,is_topic,parent_id,due_date,priority,is_completed,created_at,updated_at,revision)
   values((c->>'id')::uuid,auth.uid(),(p->>'content')::text,(p->>'item_type')::text,(p->>'inbox_column')::text,(p->>'position')::double precision,(p->>'is_archived')::boolean,(p->>'is_pinned')::boolean,(p->>'is_topic')::boolean,(p->>'parent_id')::uuid,(p->>'due_date')::date,(p->>'priority')::integer,(p->>'is_completed')::boolean,(p->>'created_at')::timestamptz,clock_timestamp(),next_revision)
   on conflict(id) do update set content=excluded.content,item_type=excluded.item_type,inbox_column=excluded.inbox_column,position=excluded.position,is_archived=excluded.is_archived,is_pinned=excluded.is_pinned,is_topic=excluded.is_topic,parent_id=excluded.parent_id,due_date=excluded.due_date,priority=excluded.priority,is_completed=excluded.is_completed,updated_at=excluded.updated_at,revision=excluded.revision
   where inbox_items.user_id=auth.uid();
   if not found then raise exception 'NOT_FOUND'; end if;
  end if;
  revisions:=revisions || jsonb_build_array(jsonb_build_object('id',c->>'id','revision',next_revision));
 end loop;
 if exists(select 1 from public.inbox_items child where child.user_id=auth.uid() and child.parent_id is not null and (child.is_topic or not exists(select 1 from public.inbox_items parent where parent.id=child.parent_id and parent.user_id=auth.uid() and parent.is_topic and not parent.is_archived and parent.parent_id is null))) then
  raise exception using errcode='23514',message='RELATION_CONFLICT';
 end if;
 response:=jsonb_build_object('ok',true,'revisions',revisions);
 insert into public.diurna_sync_receipts values(auth.uid(),attempt_id,'inbox_items',changes,response);
 return response;
exception when check_violation then
 return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_object('message','Relationship or field constraint changed'));
end; $$;
revoke all on function public.diurna_sync_inbox_v2(uuid,jsonb) from public,anon;
grant execute on function public.diurna_sync_inbox_v2(uuid,jsonb) to authenticated;
create or replace function public.diurna_sync_calendar_v2(attempt_id uuid, changes jsonb) returns jsonb
language plpgsql security invoker set search_path = pg_catalog, public as $$
declare c jsonb; p jsonb; current_row jsonb; current_revision bigint; next_revision bigint;
 receipt public.diurna_sync_receipts%rowtype; revisions jsonb := '[]'::jsonb; response jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if attempt_id is null or jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes)=0 then raise exception 'VALIDATION'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into receipt from public.diurna_sync_receipts where user_id=auth.uid() and diurna_sync_receipts.attempt_id=diurna_sync_calendar_v2.attempt_id;
 if found then
  if receipt.entity_type <> 'calendar_events' or receipt.request <> changes then raise exception 'REQUEST_ID_REUSED'; end if;
  return receipt.response;
 end if;
 if (select count(*) from jsonb_array_elements(changes)) <> (select count(distinct x->>'id') from jsonb_array_elements(changes) x) then raise exception 'DUPLICATE_ID'; end if;
 for c in select value from jsonb_array_elements(changes) loop
  if exists(select 1 from jsonb_object_keys(c) k where k not in ('id','operation','payload','expected_revision')) or not(c ?& array['id','operation','payload','expected_revision']) or jsonb_typeof(c->'expected_revision') <> 'number' or c->>'operation' is null or c->>'operation' not in ('upsert','delete') then raise exception 'VALIDATION'; end if;
  select to_jsonb(r) into current_row from public.calendar_events r where r.id=(c->>'id')::uuid and r.user_id=auth.uid() for update;
  current_revision := (current_row->>'revision')::bigint;
  if current_row is null then
   select revision into current_revision from public.diurna_sync_tombstones where user_id=auth.uid() and entity_type='calendar_events' and entity_id=(c->>'id')::uuid;
   -- Any tombstone prevents recreation under the same ID.
   if found or (c->>'expected_revision')::bigint <> 0 then
    return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(jsonb_build_object('id',c->>'id','deleted',true)));
   end if;
  elsif current_revision is distinct from (c->>'expected_revision')::bigint then
   return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(current_row));
  end if;
  if c->>'operation'='upsert' then
   p:=c->'payload';
   if jsonb_typeof(p) is distinct from 'object' then raise exception 'VALIDATION'; end if;
   if p->>'user_id' is distinct from auth.uid()::text or p->>'id' is distinct from c->>'id' then raise exception 'IDENTITY_MISMATCH'; end if;
   if exists(select 1 from jsonb_object_keys(p) k where k not in ('id','user_id','title','event_date','is_completed','note','remind_at','created_at','updated_at')) then raise exception 'UNKNOWN_FIELD'; end if;
  end if;
 end loop;
 perform set_config('diurna.sync_protocol','2',true);
 for c in select value from jsonb_array_elements(changes) order by case when value->'payload'->>'is_topic'='true' then 0 else 1 end loop
  select revision+1 into next_revision from public.calendar_events where id=(c->>'id')::uuid and user_id=auth.uid();
  next_revision:=coalesce(next_revision,1);
  if c->>'operation'='delete' then
   delete from public.calendar_events where id=(c->>'id')::uuid and user_id=auth.uid();
   insert into public.diurna_sync_tombstones values(auth.uid(),'calendar_events',(c->>'id')::uuid,next_revision);
  else
   p:=c->'payload';
   insert into public.calendar_events(id,user_id,title,event_date,is_completed,note,remind_at,created_at,updated_at,revision)
   values((c->>'id')::uuid,auth.uid(),(p->>'title')::text,(p->>'event_date')::date,(p->>'is_completed')::boolean,(p->>'note')::text,(p->>'remind_at')::timestamptz,(p->>'created_at')::timestamptz,clock_timestamp(),next_revision)
   on conflict(id) do update set title=excluded.title,event_date=excluded.event_date,is_completed=excluded.is_completed,note=excluded.note,remind_at=excluded.remind_at,updated_at=excluded.updated_at,revision=excluded.revision
   where calendar_events.user_id=auth.uid();
   if not found then raise exception 'NOT_FOUND'; end if;
  end if;
  revisions:=revisions || jsonb_build_array(jsonb_build_object('id',c->>'id','revision',next_revision));
 end loop;
 response:=jsonb_build_object('ok',true,'revisions',revisions);
 insert into public.diurna_sync_receipts values(auth.uid(),attempt_id,'calendar_events',changes,response);
 return response;
end; $$;
revoke all on function public.diurna_sync_calendar_v2(uuid,jsonb) from public,anon;
grant execute on function public.diurna_sync_calendar_v2(uuid,jsonb) to authenticated;
create or replace function public.diurna_sync_diary_v2(attempt_id uuid, changes jsonb) returns jsonb
language plpgsql security invoker set search_path = pg_catalog, public as $$
declare c jsonb; p jsonb; current_row jsonb; current_revision bigint; next_revision bigint;
 receipt public.diurna_sync_receipts%rowtype; revisions jsonb := '[]'::jsonb; response jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if attempt_id is null or jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes)=0 then raise exception 'VALIDATION'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into receipt from public.diurna_sync_receipts where user_id=auth.uid() and diurna_sync_receipts.attempt_id=diurna_sync_diary_v2.attempt_id;
 if found then
  if receipt.entity_type <> 'diary_entries' or receipt.request <> changes then raise exception 'REQUEST_ID_REUSED'; end if;
  return receipt.response;
 end if;
 if (select count(*) from jsonb_array_elements(changes)) <> (select count(distinct x->>'id') from jsonb_array_elements(changes) x) then raise exception 'DUPLICATE_ID'; end if;
 for c in select value from jsonb_array_elements(changes) loop
  if exists(select 1 from jsonb_object_keys(c) k where k not in ('id','operation','payload','expected_revision')) or not(c ?& array['id','operation','payload','expected_revision']) or jsonb_typeof(c->'expected_revision') <> 'number' or c->>'operation' is null or c->>'operation' not in ('upsert','delete') then raise exception 'VALIDATION'; end if;
  select to_jsonb(r) into current_row from public.diary_entries r where r.id=(c->>'id')::uuid and r.user_id=auth.uid() for update;
  current_revision := (current_row->>'revision')::bigint;
  if current_row is null then
   select revision into current_revision from public.diurna_sync_tombstones where user_id=auth.uid() and entity_type='diary_entries' and entity_id=(c->>'id')::uuid;
   -- Any tombstone prevents recreation under the same ID.
   if found or (c->>'expected_revision')::bigint <> 0 then
    return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(jsonb_build_object('id',c->>'id','deleted',true)));
   end if;
  elsif current_revision is distinct from (c->>'expected_revision')::bigint then
   return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(current_row));
  end if;
  if c->>'operation'='upsert' then
   p:=c->'payload';
   if jsonb_typeof(p) is distinct from 'object' then raise exception 'VALIDATION'; end if;
   if p->>'user_id' is distinct from auth.uid()::text or p->>'id' is distinct from c->>'id' then raise exception 'IDENTITY_MISMATCH'; end if;
   if exists(select 1 from jsonb_object_keys(p) k where k not in ('id','user_id','entry_date','title','content','mood','tags','created_at','updated_at')) then raise exception 'UNKNOWN_FIELD'; end if;
  end if;
 end loop;
 perform set_config('diurna.sync_protocol','2',true);
 for c in select value from jsonb_array_elements(changes) order by case when value->'payload'->>'is_topic'='true' then 0 else 1 end loop
  select revision+1 into next_revision from public.diary_entries where id=(c->>'id')::uuid and user_id=auth.uid();
  next_revision:=coalesce(next_revision,1);
  if c->>'operation'='delete' then
   delete from public.diary_entries where id=(c->>'id')::uuid and user_id=auth.uid();
   insert into public.diurna_sync_tombstones values(auth.uid(),'diary_entries',(c->>'id')::uuid,next_revision);
  else
   p:=c->'payload';
   insert into public.diary_entries(id,user_id,entry_date,title,content,mood,tags,created_at,updated_at,revision)
   values((c->>'id')::uuid,auth.uid(),(p->>'entry_date')::date,(p->>'title')::text,(p->>'content')::text,(p->>'mood')::text,ARRAY(select jsonb_array_elements_text(coalesce(p->'tags','[]'::jsonb))),(p->>'created_at')::timestamptz,clock_timestamp(),next_revision)
   on conflict(id) do update set entry_date=excluded.entry_date,title=excluded.title,content=excluded.content,mood=excluded.mood,tags=excluded.tags,updated_at=excluded.updated_at,revision=excluded.revision
   where diary_entries.user_id=auth.uid();
   if not found then raise exception 'NOT_FOUND'; end if;
  end if;
  revisions:=revisions || jsonb_build_array(jsonb_build_object('id',c->>'id','revision',next_revision));
 end loop;
 response:=jsonb_build_object('ok',true,'revisions',revisions);
 insert into public.diurna_sync_receipts values(auth.uid(),attempt_id,'diary_entries',changes,response);
 return response;
end; $$;
revoke all on function public.diurna_sync_diary_v2(uuid,jsonb) from public,anon;
grant execute on function public.diurna_sync_diary_v2(uuid,jsonb) to authenticated;
create or replace function public.diurna_sync_memos_v2(attempt_id uuid, changes jsonb) returns jsonb
language plpgsql security invoker set search_path = pg_catalog, public as $$
declare c jsonb; p jsonb; current_row jsonb; current_revision bigint; next_revision bigint;
 receipt public.diurna_sync_receipts%rowtype; revisions jsonb := '[]'::jsonb; response jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if attempt_id is null or jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes)=0 then raise exception 'VALIDATION'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into receipt from public.diurna_sync_receipts where user_id=auth.uid() and diurna_sync_receipts.attempt_id=diurna_sync_memos_v2.attempt_id;
 if found then
  if receipt.entity_type <> 'memos' or receipt.request <> changes then raise exception 'REQUEST_ID_REUSED'; end if;
  return receipt.response;
 end if;
 if (select count(*) from jsonb_array_elements(changes)) <> (select count(distinct x->>'id') from jsonb_array_elements(changes) x) then raise exception 'DUPLICATE_ID'; end if;
 for c in select value from jsonb_array_elements(changes) loop
  if exists(select 1 from jsonb_object_keys(c) k where k not in ('id','operation','payload','expected_revision')) or not(c ?& array['id','operation','payload','expected_revision']) or jsonb_typeof(c->'expected_revision') <> 'number' or c->>'operation' is null or c->>'operation' not in ('upsert','delete') then raise exception 'VALIDATION'; end if;
  select to_jsonb(r) into current_row from public.memos r where r.id=(c->>'id')::uuid and r.user_id=auth.uid() for update;
  current_revision := (current_row->>'revision')::bigint;
  if current_row is null then
   select revision into current_revision from public.diurna_sync_tombstones where user_id=auth.uid() and entity_type='memos' and entity_id=(c->>'id')::uuid;
   -- Any tombstone prevents recreation under the same ID.
   if found or (c->>'expected_revision')::bigint <> 0 then
    return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(jsonb_build_object('id',c->>'id','deleted',true)));
   end if;
  elsif current_revision is distinct from (c->>'expected_revision')::bigint then
   return jsonb_build_object('ok',false,'code','CONFLICT','remote',jsonb_build_array(current_row));
  end if;
  if c->>'operation'='upsert' then
   p:=c->'payload';
   if jsonb_typeof(p) is distinct from 'object' then raise exception 'VALIDATION'; end if;
   if p->>'user_id' is distinct from auth.uid()::text or p->>'id' is distinct from c->>'id' then raise exception 'IDENTITY_MISMATCH'; end if;
   if exists(select 1 from jsonb_object_keys(p) k where k not in ('id','user_id','title','content','position','created_at','updated_at')) then raise exception 'UNKNOWN_FIELD'; end if;
  end if;
 end loop;
 perform set_config('diurna.sync_protocol','2',true);
 for c in select value from jsonb_array_elements(changes) order by case when value->'payload'->>'is_topic'='true' then 0 else 1 end loop
  select revision+1 into next_revision from public.memos where id=(c->>'id')::uuid and user_id=auth.uid();
  next_revision:=coalesce(next_revision,1);
  if c->>'operation'='delete' then
   delete from public.memos where id=(c->>'id')::uuid and user_id=auth.uid();
   insert into public.diurna_sync_tombstones values(auth.uid(),'memos',(c->>'id')::uuid,next_revision);
  else
   p:=c->'payload';
   insert into public.memos(id,user_id,title,content,position,created_at,updated_at,revision)
   values((c->>'id')::uuid,auth.uid(),(p->>'title')::text,(p->>'content')::text,(p->>'position')::double precision,(p->>'created_at')::timestamptz,clock_timestamp(),next_revision)
   on conflict(id) do update set title=excluded.title,content=excluded.content,position=excluded.position,updated_at=excluded.updated_at,revision=excluded.revision
   where memos.user_id=auth.uid();
   if not found then raise exception 'NOT_FOUND'; end if;
  end if;
  revisions:=revisions || jsonb_build_array(jsonb_build_object('id',c->>'id','revision',next_revision));
 end loop;
 response:=jsonb_build_object('ok',true,'revisions',revisions);
 insert into public.diurna_sync_receipts values(auth.uid(),attempt_id,'memos',changes,response);
 return response;
end; $$;
revoke all on function public.diurna_sync_memos_v2(uuid,jsonb) from public,anon;
grant execute on function public.diurna_sync_memos_v2(uuid,jsonb) to authenticated;
commit;
