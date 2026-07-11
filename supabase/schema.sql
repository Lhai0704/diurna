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

alter table public.inbox_items enable row level security;
alter table public.diary_entries enable row level security;
alter table public.calendar_events enable row level security;

grant select, insert, update, delete on table public.inbox_items to authenticated;
grant select, insert, update, delete on table public.diary_entries to authenticated;
grant select, insert, update, delete on table public.calendar_events to authenticated;

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
