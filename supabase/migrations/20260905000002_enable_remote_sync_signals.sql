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
