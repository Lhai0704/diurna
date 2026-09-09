-- Extend a live processing lease so reclaim cannot steal waiting/long workers.
begin;

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

revoke all on function integrations.heartbeat_inbound_work(uuid, interval) from public, anon, authenticated;
grant execute on function integrations.heartbeat_inbound_work(uuid, interval) to postgres, service_role;

commit;
