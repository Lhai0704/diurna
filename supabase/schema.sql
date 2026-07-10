create extension if not exists "pgcrypto";

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  note text,
  due_date date,
  priority integer not null default 2 check (priority between 1 and 3),
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Upgrade the original todo table in place so existing tasks stay available.
-- Existing rows receive the action type when the column is first added; new
-- inbox captures default to no type in the application.
alter table public.tasks
  add column if not exists item_type text default 'action';
alter table public.tasks alter column item_type drop default;
alter table public.tasks
  add column if not exists inbox_column text not null default 'pending';
alter table public.tasks
  add column if not exists sort_order double precision;
alter table public.tasks
  add column if not exists is_archived boolean not null default false;
alter table public.tasks
  add column if not exists is_pinned boolean not null default false;
alter table public.tasks
  add column if not exists is_topic boolean not null default false;
alter table public.tasks
  add column if not exists parent_id uuid references public.tasks(id) on delete set null;
alter table public.tasks alter column priority drop not null;

with ranked_tasks as (
  select id, row_number() over (
    partition by user_id, inbox_column order by created_at desc
  )::double precision as initial_order
  from public.tasks
  where sort_order is null
)
update public.tasks as tasks
set sort_order = ranked_tasks.initial_order
from ranked_tasks
where tasks.id = ranked_tasks.id;

alter table public.tasks alter column sort_order set default 0;
alter table public.tasks alter column sort_order set not null;

-- The old todo UI stored its secondary text in note. Inbox cards use one
-- multi-line content field, so fold that text in without discarding it.
update public.tasks
set title = concat_ws(E'\n\n', title, note), note = null
where note is not null and btrim(note) <> '';

alter table public.tasks drop constraint if exists tasks_item_type_check;
alter table public.tasks add constraint tasks_item_type_check
  check (item_type is null or item_type in ('idea', 'action', 'research', 'resource'));
alter table public.tasks drop constraint if exists tasks_inbox_column_check;
alter table public.tasks add constraint tasks_inbox_column_check
  check (inbox_column in ('focus', 'pending'));

create index if not exists tasks_inbox_order_idx
  on public.tasks (user_id, is_archived, inbox_column, sort_order);
create index if not exists tasks_parent_idx on public.tasks (parent_id);

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
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  note text,
  remind_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

alter table public.tasks enable row level security;
alter table public.diary_entries enable row level security;
alter table public.calendar_events enable row level security;

grant select, insert, update, delete on table public.tasks to authenticated;
grant select, insert, update, delete on table public.diary_entries to authenticated;
grant select, insert, update, delete on table public.calendar_events to authenticated;

drop policy if exists "tasks_select_own" on public.tasks;
drop policy if exists "tasks_insert_own" on public.tasks;
drop policy if exists "tasks_update_own" on public.tasks;
drop policy if exists "tasks_delete_own" on public.tasks;

create policy "tasks_select_own"
on public.tasks for select
using (auth.uid() = user_id);

create policy "tasks_insert_own"
on public.tasks for insert
with check (auth.uid() = user_id);

create policy "tasks_update_own"
on public.tasks for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "tasks_delete_own"
on public.tasks for delete
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
