begin;

create extension if not exists "pgcrypto";

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

alter table public.memos enable row level security;

grant select, insert, update, delete
on table public.memos
to authenticated;

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

commit;
