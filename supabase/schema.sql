create extension if not exists "pgcrypto";

create table if not exists public.inbox_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  item_type text check (
    item_type is null or
    item_type in ('idea', 'action', 'research', 'resource')
  ),
  inbox_column text not null default 'pending' check (
    inbox_column in ('focus', 'pending')
  ),
  position double precision not null default 0,
  is_archived boolean not null default false,
  is_pinned boolean not null default false,
  is_topic boolean not null default false,
  parent_id uuid references public.inbox_items(id) on delete set null,
  due_date date,
  priority integer check (priority between 1 and 3),
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists inbox_items_order_idx
  on public.inbox_items (user_id, is_archived, inbox_column, position);
create index if not exists inbox_items_parent_idx
  on public.inbox_items (parent_id);

create table if not exists public.diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  title text not null,
  content text not null,
  mood text,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  event_date date not null,
  is_completed boolean not null default false,
  note text,
  remind_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  content text not null default '',
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists memos_order_idx
  on public.memos (user_id, position);

alter table public.inbox_items enable row level security;
alter table public.diary_entries enable row level security;
alter table public.calendar_events enable row level security;
alter table public.memos enable row level security;

grant select, insert, update, delete on table public.inbox_items to authenticated;
grant select, insert, update, delete on table public.diary_entries to authenticated;
grant select, insert, update, delete on table public.calendar_events to authenticated;
grant select, insert, update, delete on table public.memos to authenticated;

drop policy if exists "inbox_items_select_own" on public.inbox_items;
drop policy if exists "inbox_items_insert_own" on public.inbox_items;
drop policy if exists "inbox_items_update_own" on public.inbox_items;
drop policy if exists "inbox_items_delete_own" on public.inbox_items;

create policy "inbox_items_select_own"
on public.inbox_items for select
using (auth.uid() = user_id);

create policy "inbox_items_insert_own"
on public.inbox_items for insert
with check (auth.uid() = user_id);

create policy "inbox_items_update_own"
on public.inbox_items for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "inbox_items_delete_own"
on public.inbox_items for delete
using (auth.uid() = user_id);

drop policy if exists "diary_select_own" on public.diary_entries;
drop policy if exists "diary_insert_own" on public.diary_entries;
drop policy if exists "diary_update_own" on public.diary_entries;
drop policy if exists "diary_delete_own" on public.diary_entries;

create policy "diary_select_own"
on public.diary_entries for select
using (auth.uid() = user_id);

create policy "diary_insert_own"
on public.diary_entries for insert
with check (auth.uid() = user_id);

create policy "diary_update_own"
on public.diary_entries for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "diary_delete_own"
on public.diary_entries for delete
using (auth.uid() = user_id);

drop policy if exists "events_select_own" on public.calendar_events;
drop policy if exists "events_insert_own" on public.calendar_events;
drop policy if exists "events_update_own" on public.calendar_events;
drop policy if exists "events_delete_own" on public.calendar_events;

create policy "events_select_own"
on public.calendar_events for select
using (auth.uid() = user_id);

create policy "events_insert_own"
on public.calendar_events for insert
with check (auth.uid() = user_id);

create policy "events_update_own"
on public.calendar_events for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "events_delete_own"
on public.calendar_events for delete
using (auth.uid() = user_id);

drop policy if exists "memos_select_own" on public.memos;
drop policy if exists "memos_insert_own" on public.memos;
drop policy if exists "memos_update_own" on public.memos;
drop policy if exists "memos_delete_own" on public.memos;

create policy "memos_select_own"
on public.memos for select
using (auth.uid() = user_id);

create policy "memos_insert_own"
on public.memos for insert
with check (auth.uid() = user_id);

create policy "memos_update_own"
on public.memos for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "memos_delete_own"
on public.memos for delete
using (auth.uid() = user_id);

-- Machine interface protocol v2
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

begin;
create or replace function public.diurna_signal_change() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 insert into public.diurna_sync_signals(user_id,generation) values(coalesce(new.user_id,old.user_id),1)
 on conflict(user_id) do update set generation=diurna_sync_signals.generation+1;
 return coalesce(new,old);
end; $$;
drop trigger if exists diurna_signal on public.inbox_items;
create trigger diurna_signal after insert or update or delete on public.inbox_items for each row execute function public.diurna_signal_change();
drop trigger if exists diurna_signal on public.calendar_events;
create trigger diurna_signal after insert or update or delete on public.calendar_events for each row execute function public.diurna_signal_change();
drop trigger if exists diurna_signal on public.diary_entries;
create trigger diurna_signal after insert or update or delete on public.diary_entries for each row execute function public.diurna_signal_change();
drop trigger if exists diurna_signal on public.memos;
create trigger diurna_signal after insert or update or delete on public.memos for each row execute function public.diurna_signal_change();
do $$ begin
 if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
  raise exception 'supabase_realtime publication is required';
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='diurna_sync_signals') then
  alter publication supabase_realtime add table public.diurna_sync_signals;
 end if;
end $$;
commit;

-- Activate only after upgraded clients are available. Old writes remain queued locally.
begin;
create or replace function public.diurna_require_v2() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if current_setting('diurna.sync_protocol',true) is distinct from '2' then
  raise exception 'UPGRADE_REQUIRED: Diurna sync protocol v2 required';
 end if;
 return coalesce(new,old);
end; $$;
drop trigger if exists diurna_protocol_guard on public.inbox_items;
create trigger diurna_protocol_guard before insert or update or delete on public.inbox_items for each row execute function public.diurna_require_v2();
drop trigger if exists diurna_protocol_guard on public.calendar_events;
create trigger diurna_protocol_guard before insert or update or delete on public.calendar_events for each row execute function public.diurna_require_v2();
drop trigger if exists diurna_protocol_guard on public.diary_entries;
create trigger diurna_protocol_guard before insert or update or delete on public.diary_entries for each row execute function public.diurna_require_v2();
drop trigger if exists diurna_protocol_guard on public.memos;
create trigger diurna_protocol_guard before insert or update or delete on public.memos for each row execute function public.diurna_require_v2();
commit;

-- External integrations (Notion / Google). Not part of protocol v2 transport.
begin;
create schema if not exists integrations;
revoke all on schema integrations from public, anon, authenticated;
grant usage on schema integrations to postgres, service_role;

create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  status text not null check (status in ('pending', 'connected', 'error', 'disconnected')),
  provider_account_id text,
  display_name text,
  granted_scopes text[] not null default '{}',
  token_expires_at timestamptz,
  enabled_modules jsonb not null default '{"inbox":true,"memos":true,"diary":true}'::jsonb,
  container jsonb not null default '{}'::jsonb,
  last_sync_at timestamptz,
  last_sync_status text not null default 'never'
    check (last_sync_status in ('never', 'pending', 'success', 'partial', 'failed')),
  last_sync_summary jsonb not null default '{}'::jsonb,
  last_error text,
  last_seen_generation bigint,
  sync_start_generation bigint,
  sync_run_id uuid,
  sync_lease_until timestamptz,
  page_cursor jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create unique index if not exists integration_connections_one_active
  on public.integration_connections (user_id, provider)
  where status in ('pending', 'connected', 'error');

create index if not exists integration_connections_user_provider_idx
  on public.integration_connections (user_id, provider);

alter table public.integration_connections enable row level security;

revoke all on table public.integration_connections from public, anon, authenticated;
grant select on table public.integration_connections to authenticated;
grant select, insert, update, delete on table public.integration_connections to service_role, postgres;

drop policy if exists integration_connections_select_own on public.integration_connections;
create policy integration_connections_select_own
  on public.integration_connections
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.external_sync_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  entity_type text not null check (
    entity_type in ('inbox_items', 'memos', 'diary_entries', 'calendar_events')
  ),
  entity_id uuid not null,
  external_id text not null,
  external_container_id text,
  last_synced_revision bigint not null,
  content_hash text,
  last_synced_at timestamptz,
  sync_status text not null default 'synced'
    check (sync_status in ('synced', 'error', 'skipped')),
  last_error text,
  unique (connection_id, entity_type, entity_id),
  unique (connection_id, external_id),
  foreign key (connection_id, user_id)
    references public.integration_connections (id, user_id)
);

create index if not exists external_sync_links_user_provider_type_idx
  on public.external_sync_links (user_id, provider, entity_type);
create index if not exists external_sync_links_connection_entity_idx
  on public.external_sync_links (connection_id, entity_id);

alter table public.external_sync_links enable row level security;

revoke all on table public.external_sync_links from public, anon, authenticated;
grant select on table public.external_sync_links to authenticated;
grant select, insert, update, delete on table public.external_sync_links to service_role, postgres;

drop policy if exists external_sync_links_select_own on public.external_sync_links;
create policy external_sync_links_select_own
  on public.external_sync_links
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists integrations.credentials (
  connection_id uuid primary key
    references public.integration_connections(id) on delete cascade,
  token_bundle_cipher text not null,
  token_bundle_nonce bytea not null,
  access_expires_at timestamptz,
  token_updated_at timestamptz not null default now(),
  refresh_lock_until timestamptz
);

revoke all on table integrations.credentials from public, anon, authenticated;
grant select, insert, update, delete on table integrations.credentials to postgres, service_role;

create table if not exists integrations.oauth_states (
  state text primary key,
  user_id uuid not null,
  provider text not null check (provider in ('notion', 'google')),
  code_verifier text,
  return_to text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists oauth_states_expires_idx
  on integrations.oauth_states (expires_at);

revoke all on table integrations.oauth_states from public, anon, authenticated;
grant select, insert, update, delete on table integrations.oauth_states to postgres, service_role;
commit;

-- Inbound sync (additive; same objects as 20260909120000_add_external_inbound_sync.sql).

begin;

alter table public.integration_connections
  add column if not exists inbound_status text not null default 'disabled',
  add column if not exists last_inbound_at timestamptz,
  add column if not exists last_inbound_result text,
  add column if not exists inbound_error text,
  add column if not exists inbound_delta_hold boolean not null default false,
  add column if not exists inbound_repair_state jsonb not null default '{}'::jsonb;

alter table public.integration_connections
  drop constraint if exists integration_connections_inbound_status_check;
alter table public.integration_connections
  add constraint integration_connections_inbound_status_check
  check (inbound_status in ('disabled', 'bootstrapping', 'active', 'degraded', 'error'));

alter table public.external_sync_links
  add column if not exists inbound_state text not null default 'idle',
  add column if not exists external_etag text,
  add column if not exists external_updated_at timestamptz,
  add column if not exists last_remote_event_at timestamptz,
  add column if not exists outbound_hold boolean not null default false;

alter table public.external_sync_links
  drop constraint if exists external_sync_links_inbound_state_check;
alter table public.external_sync_links
  add constraint external_sync_links_inbound_state_check
  check (inbound_state in ('idle', 'ready', 'conflict', 'remote_deleted', 'error'));

create table if not exists public.external_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  entity_type text not null check (
    entity_type in ('inbox_items', 'memos', 'diary_entries', 'calendar_events')
  ),
  entity_id uuid not null,
  external_id text not null,
  status text not null default 'open'
    check (status in ('open', 'resolved_local', 'resolved_remote', 'dismissed')),
  reason text not null,
  local_revision bigint not null,
  last_synced_revision bigint not null,
  local_snapshot jsonb not null,
  remote_snapshot jsonb not null,
  remote_version text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (connection_id, user_id)
    references public.integration_connections (id, user_id)
);

create unique index if not exists external_sync_conflicts_one_open
  on public.external_sync_conflicts (connection_id, entity_type, entity_id)
  where status = 'open';

create index if not exists external_sync_conflicts_user_idx
  on public.external_sync_conflicts (user_id, status);

alter table public.external_sync_conflicts enable row level security;

revoke all on table public.external_sync_conflicts from public, anon, authenticated;
grant select on table public.external_sync_conflicts to authenticated;
grant select, insert, update, delete on table public.external_sync_conflicts to service_role, postgres;

drop policy if exists external_sync_conflicts_select_own on public.external_sync_conflicts;
create policy external_sync_conflicts_select_own
  on public.external_sync_conflicts
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists integrations.provider_watches (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('google')),
  channel_id text not null,
  resource_id text,
  channel_token text not null,
  sync_token text,
  calendar_id text,
  status text not null default 'creating'
    check (status in ('creating', 'active', 'retiring', 'expired', 'error')),
  expires_at timestamptz,
  last_message_number bigint,
  last_notification_at timestamptz,
  last_incremental_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (channel_id)
);

create index if not exists provider_watches_expiry_idx
  on integrations.provider_watches (expires_at)
  where status in ('creating', 'active');
create index if not exists provider_watches_connection_idx
  on integrations.provider_watches (connection_id, status);

revoke all on table integrations.provider_watches from public, anon, authenticated;
grant select, insert, update, delete on table integrations.provider_watches to postgres, service_role;

create table if not exists integrations.inbound_events (
  provider text not null,
  event_key text not null,
  connection_id uuid,
  result text not null,
  created_at timestamptz not null default now(),
  primary key (provider, event_key)
);

create index if not exists inbound_events_created_idx
  on integrations.inbound_events (created_at);

revoke all on table integrations.inbound_events from public, anon, authenticated;
grant select, insert, update, delete on table integrations.inbound_events to postgres, service_role;

create table if not exists integrations.inbound_work (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  provider text not null check (provider in ('notion', 'google')),
  work_type text not null check (work_type in (
    'notion_page', 'google_incremental', 'google_full',
    'google_calendar_gone', 'bootstrap_notion', 'bootstrap_google',
    'repair', 'renew_watch'
  )),
  dedup_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'error')),
  rerun_requested boolean not null default false,
  latest_event_at timestamptz not null default now(),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  locked_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists inbound_work_inflight_dedup
  on integrations.inbound_work (connection_id, work_type, dedup_key)
  where status in ('pending', 'processing');
create index if not exists inbound_work_claim_idx
  on integrations.inbound_work (available_at)
  where status = 'pending';
create index if not exists inbound_work_lock_idx
  on integrations.inbound_work (locked_until)
  where status = 'processing';

revoke all on table integrations.inbound_work from public, anon, authenticated;
grant select, insert, update, delete on table integrations.inbound_work to postgres, service_role;

create table if not exists integrations.webhook_secrets (
  provider text not null,
  kind text not null,
  cipher text not null,
  nonce bytea not null,
  revealed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, kind)
);

revoke all on table integrations.webhook_secrets from public, anon, authenticated;
grant select, insert, update, delete on table integrations.webhook_secrets to postgres, service_role;

create table if not exists integrations.webhook_handshake_arms (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'notion' check (provider in ('notion')),
  purpose text not null check (purpose in ('initial', 'rotate')),
  nonce_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

revoke all on table integrations.webhook_handshake_arms from public, anon, authenticated;
grant select, insert, update, delete on table integrations.webhook_handshake_arms to postgres, service_role;

create or replace function integrations._allowed_patch_keys(p_entity_type text)
returns text[]
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case p_entity_type
    when 'inbox_items' then array['content','item_type','inbox_column','is_completed','is_pinned','is_archived','is_topic']
    when 'memos' then array['title','content']
    when 'diary_entries' then array['title','content','entry_date','mood']
    when 'calendar_events' then array['title','event_date','note']
    else array[]::text[]
  end;
$$;

create or replace function integrations._patch_equals_row(
  p_row jsonb,
  p_patch jsonb
) returns boolean
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare k text;
begin
  if p_patch is null or p_patch = '{}'::jsonb then
    return true;
  end if;
  for k in select jsonb_object_keys(p_patch)
  loop
    if jsonb_typeof(p_patch->k) = 'null' then
      if p_row->>k is not null then
        return false;
      end if;
    elsif jsonb_typeof(p_patch->k) = 'boolean' then
      if (p_row->>k)::boolean is distinct from (p_patch->>k)::boolean then
        return false;
      end if;
    elsif (p_row->>k) is distinct from (p_patch->>k) then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create or replace function integrations._open_conflict(
  p_user_id uuid,
  p_connection_id uuid,
  p_provider text,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_reason text,
  p_local_revision bigint,
  p_last_synced_revision bigint,
  p_local_snapshot jsonb,
  p_remote_snapshot jsonb,
  p_remote_version text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  insert into public.external_sync_conflicts (
    user_id, connection_id, provider, entity_type, entity_id, external_id,
    status, reason, local_revision, last_synced_revision,
    local_snapshot, remote_snapshot, remote_version
  ) values (
    p_user_id, p_connection_id, p_provider, p_entity_type, p_entity_id, p_external_id,
    'open', p_reason, p_local_revision, p_last_synced_revision,
    coalesce(p_local_snapshot, '{}'::jsonb),
    coalesce(p_remote_snapshot, '{}'::jsonb),
    p_remote_version
  )
  on conflict (connection_id, entity_type, entity_id) where status = 'open'
  do update set
    reason = excluded.reason,
    local_revision = excluded.local_revision,
    last_synced_revision = excluded.last_synced_revision,
    local_snapshot = excluded.local_snapshot,
    remote_snapshot = excluded.remote_snapshot,
    remote_version = excluded.remote_version;
end;
$$;

create or replace function integrations.apply_external_change(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_operation text,
  p_patch jsonb,
  p_remote_snapshot jsonb,
  p_provider_etag text,
  p_provider_updated_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
  next_revision bigint;
  generation_after bigint;
  allowed text[];
  patch_key text;
  mapped_equal boolean;
  incoming_updated timestamptz;
  stored_updated timestamptz;
  result_code text;
begin
  if p_operation is null or p_operation not in ('update', 'remote_deleted') then
    raise exception 'VALIDATION';
  end if;
  if p_entity_type is null or p_entity_type not in (
    'inbox_items', 'memos', 'diary_entries', 'calendar_events'
  ) then
    raise exception 'VALIDATION';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'VALIDATION';
  end if;
  allowed := integrations._allowed_patch_keys(p_entity_type);
  for patch_key in select jsonb_object_keys(p_patch)
  loop
    if not patch_key = any(allowed) then
      raise exception 'UNKNOWN_FIELD';
    end if;
  end loop;

  perform set_config('diurna.sync_protocol', '2', true);

  select * into conn
    from public.integration_connections
   where id = p_connection_id
     for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  if conn.inbound_status not in ('active', 'bootstrapping', 'degraded') then
    return jsonb_build_object('result', 'ignored', 'reason', 'inbound_disabled');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));

  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  if link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'external_id_mismatch');
  end if;
  if link.inbound_state = 'conflict' then
    return jsonb_build_object(
      'result', 'conflict',
      'reason', 'already_conflict',
      'revision_before', null,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;

  if current_row is null then
    if exists (
      select 1 from public.diurna_sync_tombstones
       where user_id = conn.user_id
         and entity_type = p_entity_type
         and entity_id = p_entity_id
    ) then
      return jsonb_build_object('result', 'ignored', 'reason', 'tombstone');
    end if;
    return jsonb_build_object('result', 'ignored', 'reason', 'missing_entity');
  end if;

  current_revision := (current_row->>'revision')::bigint;
  incoming_updated := p_provider_updated_at;
  stored_updated := link.external_updated_at;
  mapped_equal := integrations._patch_equals_row(current_row, p_patch);

  if p_operation = 'remote_deleted' then
    if current_revision > link.last_synced_revision then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'remote_deleted_with_local_edit', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict',
             last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'remote_deleted_with_local_edit',
        'revision_before', current_revision,
        'revision_after', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    update public.external_sync_links
       set inbound_state = 'remote_deleted',
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where id = link.id;
    return jsonb_build_object(
      'result', 'remote_deleted',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if link.inbound_state = 'remote_deleted' then
    if current_revision > link.last_synced_revision then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'remote_deleted_with_local_edit', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict',
             last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'remote_deleted_with_local_edit',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    return jsonb_build_object('result', 'ignored', 'reason', 'remote_deleted');
  end if;

  if conn.provider = 'google'
     and p_provider_etag is not null
     and link.external_etag is not null
     and p_provider_etag = link.external_etag then
    return jsonb_build_object(
      'result', 'duplicate',
      'reason', 'etag',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if incoming_updated is not null and stored_updated is not null then
    if incoming_updated < stored_updated then
      return jsonb_build_object(
        'result', 'stale',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
    if incoming_updated = stored_updated and mapped_equal then
      return jsonb_build_object(
        'result', 'duplicate',
        'reason', 'same_updated_equal_mapped',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
  end if;

  if current_revision < link.last_synced_revision then
    return jsonb_build_object(
      'result', 'error',
      'reason', 'revision_invariant',
      'revision_before', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      'diverged_revision', current_revision, link.last_synced_revision,
      current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
    );
    update public.external_sync_links
       set inbound_state = 'conflict',
           last_remote_event_at = now(),
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
     where id = link.id;
    return jsonb_build_object(
      'result', 'conflict',
      'reason', 'diverged_revision',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if mapped_equal then
    update public.external_sync_links
       set inbound_state = 'ready',
           external_etag = coalesce(p_provider_etag, external_etag),
           external_updated_at = coalesce(p_provider_updated_at, external_updated_at),
           last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object(
      'result', 'duplicate',
      'reason', 'mapped_equal',
      'revision_before', current_revision,
      'revision_after', current_revision,
      'last_synced_revision', link.last_synced_revision
    );
  end if;

  if p_entity_type = 'inbox_items' then
    if (
      coalesce((p_patch->>'is_topic')::boolean, (current_row->>'is_topic')::boolean) = false
      or coalesce((p_patch->>'is_archived')::boolean, (current_row->>'is_archived')::boolean) = true
    ) and exists (
      select 1 from public.inbox_items child
       where child.user_id = conn.user_id
         and child.parent_id = p_entity_id
    ) then
      perform integrations._open_conflict(
        conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
        'inbox_relationship', current_revision, link.last_synced_revision,
        current_row, coalesce(p_remote_snapshot, '{}'::jsonb), p_provider_etag
      );
      update public.external_sync_links
         set inbound_state = 'conflict', last_remote_event_at = now()
       where id = link.id;
      return jsonb_build_object(
        'result', 'conflict',
        'reason', 'inbox_relationship',
        'revision_before', current_revision,
        'last_synced_revision', link.last_synced_revision
      );
    end if;
  end if;

  next_revision := current_revision + 1;

  if p_entity_type = 'memos' then
    update public.memos set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  elsif p_entity_type = 'diary_entries' then
    update public.diary_entries set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      content = case when p_patch ? 'content' then coalesce(p_patch->>'content', '') else content end,
      entry_date = case when p_patch ? 'entry_date' then (p_patch->>'entry_date')::date else entry_date end,
      mood = case when p_patch ? 'mood' then p_patch->>'mood' else mood end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  elsif p_entity_type = 'calendar_events' then
    update public.calendar_events set
      title = case when p_patch ? 'title' then p_patch->>'title' else title end,
      event_date = case when p_patch ? 'event_date' then (p_patch->>'event_date')::date else event_date end,
      note = case when p_patch ? 'note' then p_patch->>'note' else note end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  else
    update public.inbox_items set
      content = case when p_patch ? 'content' then p_patch->>'content' else content end,
      item_type = case when p_patch ? 'item_type' then p_patch->>'item_type' else item_type end,
      inbox_column = case when p_patch ? 'inbox_column' then p_patch->>'inbox_column' else inbox_column end,
      is_completed = case when p_patch ? 'is_completed' then (p_patch->>'is_completed')::boolean else is_completed end,
      is_pinned = case when p_patch ? 'is_pinned' then (p_patch->>'is_pinned')::boolean else is_pinned end,
      is_archived = case when p_patch ? 'is_archived' then (p_patch->>'is_archived')::boolean else is_archived end,
      is_topic = case when p_patch ? 'is_topic' then (p_patch->>'is_topic')::boolean else is_topic end,
      updated_at = clock_timestamp(),
      revision = next_revision
     where id = p_entity_id and user_id = conn.user_id;
  end if;

  update public.external_sync_links
     set last_synced_revision = next_revision,
         inbound_state = 'ready',
         sync_status = case when sync_status = 'skipped' then sync_status else 'synced' end,
         last_error = null,
         last_synced_at = now(),
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where id = link.id;

  select generation into generation_after
    from public.diurna_sync_signals
   where user_id = conn.user_id;

  return jsonb_build_object(
    'result', 'applied',
    'revision_before', current_revision,
    'revision_after', next_revision,
    'last_synced_revision', next_revision,
    'generation_after', coalesce(generation_after, 0)
  );
end;
$$;

create or replace function integrations.bootstrap_link_version(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_provider_etag text,
  p_provider_updated_at timestamptz,
  p_drift boolean,
  p_reason text,
  p_local_snapshot jsonb,
  p_remote_snapshot jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
begin
  select * into conn from public.integration_connections where id = p_connection_id for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));
  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found or link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;
  current_revision := coalesce((current_row->>'revision')::bigint, link.last_synced_revision);

  if p_drift or current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      coalesce(p_reason, 'bootstrap_remote_drift'),
      current_revision, link.last_synced_revision,
      coalesce(p_local_snapshot, current_row, '{}'::jsonb),
      coalesce(p_remote_snapshot, '{}'::jsonb),
      p_provider_etag
    );
    update public.external_sync_links
       set inbound_state = 'conflict',
           external_etag = p_provider_etag,
           external_updated_at = p_provider_updated_at,
           last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object('result', 'conflict', 'reason', coalesce(p_reason, 'bootstrap_remote_drift'));
  end if;

  update public.external_sync_links
     set inbound_state = 'ready',
         external_etag = p_provider_etag,
         external_updated_at = p_provider_updated_at,
         last_remote_event_at = now()
   where id = link.id;
  return jsonb_build_object('result', 'ready', 'revision_before', current_revision);
end;
$$;

create or replace function integrations.enqueue_inbound_work(
  p_connection_id uuid,
  p_provider text,
  p_work_type text,
  p_dedup_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  work integrations.inbound_work%rowtype;
begin
  select * into work
    from integrations.inbound_work
   where connection_id = p_connection_id
     and work_type = p_work_type
     and dedup_key = p_dedup_key
     and status in ('pending', 'processing')
     for update;

  if found and work.status = 'pending' then
    update integrations.inbound_work
       set latest_event_at = now(),
           payload = coalesce(p_payload, payload),
           updated_at = now()
     where id = work.id;
    return jsonb_build_object('enqueued', true, 'coalesced', true, 'status', 'pending', 'id', work.id);
  end if;

  if found and work.status = 'processing' then
    update integrations.inbound_work
       set rerun_requested = true,
           latest_event_at = now(),
           payload = coalesce(p_payload, payload),
           updated_at = now()
     where id = work.id;
    return jsonb_build_object(
      'enqueued', true, 'rerun_requested', true, 'status', 'processing', 'id', work.id
    );
  end if;

  insert into integrations.inbound_work (
    connection_id, provider, work_type, dedup_key, payload, status
  ) values (
    p_connection_id, p_provider, p_work_type, p_dedup_key, coalesce(p_payload, '{}'::jsonb), 'pending'
  )
  returning * into work;

  return jsonb_build_object('enqueued', true, 'created', true, 'status', 'pending', 'id', work.id);
end;
$$;

create or replace function integrations.reclaim_stale_inbound_work()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare errored integer := 0;
declare retried integer := 0;
begin
  update integrations.inbound_work
     set status = 'error',
         locked_until = null,
         last_error = 'stale_lock',
         updated_at = now()
   where status = 'processing'
     and locked_until < now()
     and attempts >= 8;
  get diagnostics errored = row_count;

  update integrations.inbound_work
     set status = 'pending',
         locked_until = null,
         last_error = 'stale_lock',
         available_at = now() + least(
           interval '30 minutes',
           (15 * power(2, greatest(attempts, 0))) * interval '1 second'
         ),
         updated_at = now()
   where status = 'processing'
     and locked_until < now()
     and attempts < 8;
  get diagnostics retried = row_count;
  return errored + retried;
end;
$$;

create or replace function integrations.claim_inbound_work()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  perform integrations.reclaim_stale_inbound_work();
  with next as (
    select id
      from integrations.inbound_work
     where status = 'pending'
       and available_at <= now()
     order by created_at
     for update skip locked
     limit 1
  )
  update integrations.inbound_work w
     set status = 'processing',
         locked_until = now() + interval '3 minutes',
         attempts = attempts + 1,
         updated_at = now()
    from next
   where w.id = next.id
   returning w.* into work;
  if not found then
    return null;
  end if;
  return to_jsonb(work);
end;
$$;

create or replace function integrations.complete_inbound_work(p_id uuid, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  select * into work from integrations.inbound_work where id = p_id for update;
  if not found then
    return jsonb_build_object('result', 'ignored', 'reason', 'missing');
  end if;
  if work.status is distinct from 'processing' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_processing', 'status', work.status);
  end if;
  if p_error is not null and work.rerun_requested is not true then
    if work.attempts >= 8 then
      update integrations.inbound_work
         set status = 'error',
             locked_until = null,
             last_error = p_error,
             updated_at = now()
       where id = p_id;
      return jsonb_build_object('status', 'error', 'id', p_id);
    end if;
    update integrations.inbound_work
       set status = 'pending',
           locked_until = null,
           last_error = p_error,
           available_at = now() + least(
             interval '30 minutes',
             (15 * power(2, attempts)) * interval '1 second'
           ),
           updated_at = now()
     where id = p_id;
    return jsonb_build_object('status', 'pending', 'retry', true, 'id', p_id);
  end if;
  if work.rerun_requested then
    update integrations.inbound_work
       set status = 'pending',
           rerun_requested = false,
           locked_until = null,
           available_at = now(),
           last_error = null,
           updated_at = now()
     where id = p_id;
    return jsonb_build_object('status', 'pending', 'rerun', true, 'id', p_id);
  end if;
  update integrations.inbound_work
     set status = 'done',
         locked_until = null,
         last_error = null,
         updated_at = now()
   where id = p_id;
  return jsonb_build_object('status', 'done', 'id', p_id);
end;
$$;

create or replace function integrations.record_inbound_event(
  p_provider text,
  p_event_key text,
  p_connection_id uuid,
  p_result text
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  insert into integrations.inbound_events (provider, event_key, connection_id, result)
  values (p_provider, p_event_key, p_connection_id, p_result)
  on conflict (provider, event_key) do nothing;
  return found;
end;
$$;

revoke all on function integrations._allowed_patch_keys(text) from public, anon, authenticated;
revoke all on function integrations._patch_equals_row(jsonb, jsonb) from public, anon, authenticated;
revoke all on function integrations._open_conflict(uuid, uuid, text, text, uuid, text, text, bigint, bigint, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function integrations.apply_external_change(uuid, text, uuid, text, text, jsonb, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function integrations.bootstrap_link_version(uuid, text, uuid, text, text, timestamptz, boolean, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function integrations.enqueue_inbound_work(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function integrations.reclaim_stale_inbound_work() from public, anon, authenticated;
revoke all on function integrations.claim_inbound_work() from public, anon, authenticated;
revoke all on function integrations.complete_inbound_work(uuid, text) from public, anon, authenticated;
revoke all on function integrations.record_inbound_event(text, text, uuid, text) from public, anon, authenticated;

grant execute on function integrations._allowed_patch_keys(text) to postgres, service_role;
grant execute on function integrations._patch_equals_row(jsonb, jsonb) to postgres, service_role;
grant execute on function integrations._open_conflict(uuid, uuid, text, text, uuid, text, text, bigint, bigint, jsonb, jsonb, text) to postgres, service_role;
grant execute on function integrations.apply_external_change(uuid, text, uuid, text, text, jsonb, jsonb, text, timestamptz) to postgres, service_role;
grant execute on function integrations.bootstrap_link_version(uuid, text, uuid, text, text, timestamptz, boolean, text, jsonb, jsonb) to postgres, service_role;
grant execute on function integrations.enqueue_inbound_work(uuid, text, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.reclaim_stale_inbound_work() to postgres, service_role;
grant execute on function integrations.claim_inbound_work() to postgres, service_role;
grant execute on function integrations.complete_inbound_work(uuid, text) to postgres, service_role;
grant execute on function integrations.record_inbound_event(text, text, uuid, text) to postgres, service_role;

commit;

-- Atomic inbound event enqueue (same objects as 20260909130000_accept_inbound_event.sql).

begin;

create or replace function integrations.accept_inbound_event(
  p_provider text,
  p_event_key text,
  p_connection_id uuid,
  p_work_type text,
  p_dedup_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work jsonb;
begin
  if p_provider is null or p_event_key is null or p_event_key = ''
     or p_connection_id is null or p_work_type is null or p_dedup_key is null then
    raise exception 'VALIDATION';
  end if;
  insert into integrations.inbound_events (provider, event_key, connection_id, result)
  values (p_provider, p_event_key, p_connection_id, 'accepted')
  on conflict (provider, event_key) do nothing;
  if not found then
    return jsonb_build_object('accepted', false, 'duplicate', true);
  end if;
  work := integrations.enqueue_inbound_work(
    p_connection_id, p_provider, p_work_type, p_dedup_key, coalesce(p_payload, '{}'::jsonb)
  );
  if p_work_type = 'notion_page' then
    update public.external_sync_links
       set outbound_hold = true,
           last_remote_event_at = now()
     where connection_id = p_connection_id
       and external_id = p_dedup_key;
  elsif p_work_type = 'google_incremental' then
    update public.integration_connections
       set inbound_delta_hold = true,
           updated_at = now()
     where id = p_connection_id;
  end if;
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
end;
$$;

create or replace function integrations.freeze_link_conflict(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text,
  p_reason text,
  p_remote_snapshot jsonb default '{}'::jsonb,
  p_provider_etag text default null,
  p_provider_updated_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
begin
  select * into conn from public.integration_connections where id = p_connection_id for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));
  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found or link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;
  current_revision := coalesce((current_row->>'revision')::bigint, link.last_synced_revision);
  perform integrations._open_conflict(
    conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
    coalesce(p_reason, 'unsupported_content'),
    current_revision, link.last_synced_revision,
    coalesce(current_row, '{}'::jsonb),
    coalesce(p_remote_snapshot, '{}'::jsonb),
    p_provider_etag
  );
  update public.external_sync_links
     set inbound_state = 'conflict',
         last_remote_event_at = now(),
         external_etag = coalesce(p_provider_etag, external_etag),
         external_updated_at = coalesce(p_provider_updated_at, external_updated_at)
   where id = link.id;
  return jsonb_build_object(
    'result', 'conflict',
    'reason', coalesce(p_reason, 'unsupported_content'),
    'revision_before', current_revision,
    'last_synced_revision', link.last_synced_revision
  );
end;
$$;

create or replace function integrations.restore_remote_deleted_link(
  p_connection_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_external_id text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  current_revision bigint;
begin
  select * into conn from public.integration_connections where id = p_connection_id for update;
  if not found or conn.status is distinct from 'connected' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_connected');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text, 0));
  select * into link
    from public.external_sync_links
   where connection_id = p_connection_id
     and entity_type = p_entity_type
     and entity_id = p_entity_id
     for update;
  if not found or link.external_id is distinct from p_external_id then
    return jsonb_build_object('result', 'ignored', 'reason', 'no_link');
  end if;
  if link.inbound_state is distinct from 'remote_deleted' then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_remote_deleted');
  end if;
  execute format(
    'select to_jsonb(r) from public.%I r where r.id = $1 and r.user_id = $2 for update',
    p_entity_type
  ) into current_row using p_entity_id, conn.user_id;
  current_revision := coalesce((current_row->>'revision')::bigint, link.last_synced_revision);
  if current_revision > link.last_synced_revision then
    perform integrations._open_conflict(
      conn.user_id, conn.id, conn.provider, p_entity_type, p_entity_id, p_external_id,
      'remote_deleted_with_local_edit',
      current_revision, link.last_synced_revision,
      coalesce(current_row, '{}'::jsonb), '{}'::jsonb, null
    );
    update public.external_sync_links
       set inbound_state = 'conflict', last_remote_event_at = now()
     where id = link.id;
    return jsonb_build_object('result', 'conflict', 'reason', 'remote_deleted_with_local_edit');
  end if;
  update public.external_sync_links
     set inbound_state = 'ready', last_remote_event_at = now()
   where id = link.id;
  return jsonb_build_object('result', 'ready', 'revision_before', current_revision);
end;
$$;

create or replace function integrations.claim_inbound_work_of(p_work_types text[])
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  perform integrations.reclaim_stale_inbound_work();
  with next as (
    select id
      from integrations.inbound_work
     where status = 'pending'
       and available_at <= now()
       and work_type = any(p_work_types)
     order by created_at
     for update skip locked
     limit 1
  )
  update integrations.inbound_work w
     set status = 'processing',
         locked_until = now() + interval '3 minutes',
         attempts = attempts + 1,
         updated_at = now()
    from next
   where w.id = next.id
   returning w.* into work;
  if not found then
    return null;
  end if;
  return to_jsonb(work);
end;
$$;

revoke all on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function integrations.freeze_link_conflict(uuid, text, uuid, text, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function integrations.restore_remote_deleted_link(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function integrations.claim_inbound_work_of(text[]) from public, anon, authenticated;
grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.freeze_link_conflict(uuid, text, uuid, text, text, jsonb, text, timestamptz) to postgres, service_role;
grant execute on function integrations.restore_remote_deleted_link(uuid, text, uuid, text) to postgres, service_role;
grant execute on function integrations.claim_inbound_work_of(text[]) to postgres, service_role;

commit;

-- Inbound maintenance (same objects as 20260909140000_inbound_maintenance.sql).

begin;

alter table integrations.inbound_work
  drop constraint if exists inbound_work_work_type_check;
alter table integrations.inbound_work
  add constraint inbound_work_work_type_check
  check (work_type in (
    'notion_page', 'google_incremental', 'google_full',
    'google_calendar_gone', 'bootstrap_notion', 'bootstrap_google',
    'repair', 'renew_watch'
  ));

create or replace function integrations.claim_inbound_work_of(p_work_types text[])
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  perform integrations.reclaim_stale_inbound_work();
  with next as (
    select id
      from integrations.inbound_work
     where status = 'pending'
       and available_at <= now()
       and work_type = any(p_work_types)
     order by
       case work_type
         when 'bootstrap_notion' then 0
         when 'bootstrap_google' then 0
         when 'notion_page' then 1
         when 'google_incremental' then 1
         when 'google_calendar_gone' then 1
         when 'renew_watch' then 2
         when 'repair' then 3
         else 4
       end,
       created_at
     for update skip locked
     limit 1
  )
  update integrations.inbound_work w
     set status = 'processing',
         locked_until = now() + interval '3 minutes',
         attempts = attempts + 1,
         updated_at = now()
    from next
   where w.id = next.id
   returning w.* into work;
  if not found then
    return null;
  end if;
  return to_jsonb(work);
end;
$$;

create or replace function integrations.accept_inbound_event(
  p_provider text,
  p_event_key text,
  p_connection_id uuid,
  p_work_type text,
  p_dedup_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work jsonb;
declare conn_status text;
begin
  if p_provider is null or p_event_key is null or p_event_key = ''
     or p_connection_id is null or p_work_type is null or p_dedup_key is null then
    raise exception 'VALIDATION';
  end if;
  select status into conn_status
    from public.integration_connections
   where id = p_connection_id
   for update;
  if not found or conn_status is distinct from 'connected' then
    return jsonb_build_object('accepted', false, 'ignored', true, 'reason', 'disconnected');
  end if;
  insert into integrations.inbound_events (provider, event_key, connection_id, result)
  values (p_provider, p_event_key, p_connection_id, 'accepted')
  on conflict (provider, event_key) do nothing;
  if not found then
    return jsonb_build_object('accepted', false, 'duplicate', true);
  end if;
  work := integrations.enqueue_inbound_work(
    p_connection_id, p_provider, p_work_type, p_dedup_key, coalesce(p_payload, '{}'::jsonb)
  );
  if p_work_type = 'notion_page' then
    update public.external_sync_links
       set outbound_hold = true,
           last_remote_event_at = now()
     where connection_id = p_connection_id
       and external_id = p_dedup_key;
  elsif p_work_type = 'google_incremental' then
    update public.integration_connections
       set inbound_delta_hold = true,
           updated_at = now()
     where id = p_connection_id;
  end if;
  return jsonb_build_object('accepted', true, 'duplicate', false) || work;
end;
$$;

create or replace function integrations.defer_inbound_work(p_id uuid, p_delay interval)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
begin
  update integrations.inbound_work
     set status = 'pending',
         locked_until = null,
         available_at = now() + coalesce(p_delay, interval '2 minutes'),
         attempts = greatest(attempts - 1, 0),
         updated_at = now()
   where id = p_id
     and status = 'processing';
  if not found then
    return jsonb_build_object('result', 'ignored');
  end if;
  return jsonb_build_object('result', 'deferred', 'id', p_id);
end;
$$;

create or replace function integrations.purge_inbound_events(p_older_than interval default interval '48 hours')
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare n integer := 0;
begin
  delete from integrations.inbound_events
   where created_at < now() - p_older_than;
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function integrations.consume_handshake_arm(
  p_nonce_hash text,
  p_has_active_token boolean
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare arm integrations.webhook_handshake_arms%rowtype;
begin
  if p_nonce_hash is null or p_nonce_hash = '' then
    return jsonb_build_object('result', 'rejected', 'reason', 'missing_nonce');
  end if;
  select * into arm
    from integrations.webhook_handshake_arms
   where nonce_hash = p_nonce_hash
   for update;
  if not found then
    return jsonb_build_object('result', 'rejected', 'reason', 'unknown_nonce');
  end if;
  if arm.consumed_at is not null then
    return jsonb_build_object('result', 'rejected', 'reason', 'consumed');
  end if;
  if arm.expires_at <= now() then
    return jsonb_build_object('result', 'rejected', 'reason', 'expired');
  end if;
  if p_has_active_token and arm.purpose is distinct from 'rotate' then
    return jsonb_build_object('result', 'rejected', 'reason', 'active_token');
  end if;
  update integrations.webhook_handshake_arms
     set consumed_at = now()
   where id = arm.id;
  return jsonb_build_object('result', 'ok', 'purpose', arm.purpose);
end;
$$;

create or replace function integrations.heartbeat_inbound_work(
  p_id uuid,
  p_extend interval default interval '3 minutes'
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, integrations
as $$
declare work integrations.inbound_work%rowtype;
begin
  update integrations.inbound_work
     set locked_until = now() + coalesce(p_extend, interval '3 minutes'),
         updated_at = now()
   where id = p_id
     and status = 'processing'
   returning * into work;
  if not found then
    return jsonb_build_object('result', 'ignored', 'reason', 'not_processing');
  end if;
  return jsonb_build_object(
    'result', 'ok',
    'id', work.id,
    'locked_until', work.locked_until
  );
end;
$$;

revoke all on function integrations.defer_inbound_work(uuid, interval) from public, anon, authenticated;
revoke all on function integrations.purge_inbound_events(interval) from public, anon, authenticated;
revoke all on function integrations.consume_handshake_arm(text, boolean) from public, anon, authenticated;
revoke all on function integrations.heartbeat_inbound_work(uuid, interval) from public, anon, authenticated;
grant execute on function integrations.claim_inbound_work_of(text[]) to postgres, service_role;
grant execute on function integrations.accept_inbound_event(text, text, uuid, text, text, jsonb) to postgres, service_role;
grant execute on function integrations.defer_inbound_work(uuid, interval) to postgres, service_role;
grant execute on function integrations.purge_inbound_events(interval) to postgres, service_role;
grant execute on function integrations.consume_handshake_arm(text, boolean) to postgres, service_role;
grant execute on function integrations.heartbeat_inbound_work(uuid, interval) to postgres, service_role;

commit;
