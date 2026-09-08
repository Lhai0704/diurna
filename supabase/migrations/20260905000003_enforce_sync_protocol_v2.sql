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
