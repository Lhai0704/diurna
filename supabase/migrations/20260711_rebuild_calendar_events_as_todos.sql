-- Calendar data is currently test-only, so rebuild it with the date-based
-- todo shape. This deletes every existing calendar event.
drop table if exists public.calendar_events;

create table public.calendar_events (
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

alter table public.calendar_events enable row level security;

grant select, insert, update, delete
on table public.calendar_events
to authenticated;

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
