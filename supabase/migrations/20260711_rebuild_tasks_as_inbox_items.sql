-- Inbox data is test-only. Replace the legacy tasks table with the final
-- inbox_items shape instead of carrying forward compatibility columns.
begin;

create extension if not exists "pgcrypto";

drop table if exists public.inbox_items;
drop table if exists public.tasks;

create table public.inbox_items (
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

create index inbox_items_order_idx
  on public.inbox_items (user_id, is_archived, inbox_column, position);
create index inbox_items_parent_idx
  on public.inbox_items (parent_id);

alter table public.inbox_items enable row level security;

grant select, insert, update, delete
on table public.inbox_items
to authenticated;

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

commit;
