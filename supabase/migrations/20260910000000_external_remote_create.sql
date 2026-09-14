-- Remote identity and discovery state are private, contain no provider body/token.
create table if not exists integrations.remote_object_status (
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  external_id text not null,
  reason text,
  metadata_pending boolean not null default false,
  initial_patch_hash text,
  initial_revision bigint,
  updated_at timestamptz not null default now(),
  primary key(connection_id, external_id)
);
create table if not exists integrations.remote_discovery_state (
  connection_id uuid not null references public.integration_connections(id) on delete cascade,
  source_id text not null,
  cursor text,
  completed boolean not null default false,
  started_at timestamptz not null default now(),
  primary key(connection_id, source_id)
);
alter table integrations.remote_object_status enable row level security;
alter table integrations.remote_discovery_state enable row level security;
revoke all on integrations.remote_object_status, integrations.remote_discovery_state from public, anon, authenticated;
grant all on integrations.remote_object_status, integrations.remote_discovery_state to postgres, service_role;

-- No client/remote supplied user_id, revision, arbitrary table or SQL is accepted.
create or replace function integrations.reconcile_external_object(
  p_connection_id uuid, p_provider text, p_container_id text,
  p_entity_type text, p_external_id text, p_candidate_id uuid,
  p_patch jsonb, p_remote_snapshot jsonb, p_provider_etag text,
  p_provider_updated_at timestamptz, p_unsupported_reason text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, integrations
as $$
declare
  conn public.integration_connections%rowtype;
  link public.external_sync_links%rowtype;
  current_row jsonb;
  v_entity_id uuid;
  rev bigint := 1;
  k text;
  expected_container text;
  outcome jsonb;
  recovered boolean := false;
  pos double precision;
begin
  if p_provider is null or p_provider not in ('notion','google')
     or p_entity_type is null or p_entity_type not in ('inbox_items','memos','diary_entries','calendar_events')
     or nullif(p_external_id,'') is null or nullif(p_container_id,'') is null
     or p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'VALIDATION';
  end if;
  for k in select jsonb_object_keys(p_patch) loop
    if not k = any(integrations._allowed_patch_keys(p_entity_type)) then raise exception 'UNKNOWN_FIELD'; end if;
  end loop;
  select * into conn from public.integration_connections where id=p_connection_id for update;
  if not found or conn.status <> 'connected' then
    return jsonb_build_object('result','ignored','reason','not_connected');
  end if;
  if conn.inbound_status not in ('active','degraded','bootstrapping') then
    return jsonb_build_object('result','ignored','reason','inbound_disabled');
  end if;
  expected_container := case
    when p_provider='google' and p_entity_type='calendar_events' then conn.container->>'calendar_id'
    when p_provider='notion' and p_entity_type='inbox_items' then conn.container->>'inbox_ds'
    when p_provider='notion' and p_entity_type='memos' then conn.container->>'memo_ds'
    when p_provider='notion' and p_entity_type='diary_entries' then conn.container->>'diary_ds'
  end;
  if conn.provider <> p_provider or expected_container is null
     or (case when p_provider='notion' then lower(replace(expected_container,'-','')) <> lower(replace(p_container_id,'-',''))
              else expected_container <> p_container_id end) then
    return jsonb_build_object('result','ignored','reason','container_mismatch');
  end if;
  if p_provider='notion' and (select count(*) from jsonb_each_text(conn.container) e
    where e.key in ('inbox_ds','memo_ds','diary_ds')
      and lower(replace(e.value,'-',''))=lower(replace(p_container_id,'-',''))) <> 1 then
    return jsonb_build_object('result','ignored','reason','ambiguous_container');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text,0));
  perform set_config('diurna.sync_protocol','2',true);
  select * into link from public.external_sync_links
    where connection_id=conn.id and external_id=p_external_id for update;
  if found then
    if link.entity_type <> p_entity_type or link.provider <> p_provider or link.user_id <> conn.user_id then
      return jsonb_build_object('result','ignored','reason','identity_mismatch');
    end if;
    return jsonb_build_object('result','existing','entity_id',link.entity_id,'revision',link.last_synced_revision);
  end if;
  if p_candidate_id is not null then
    if exists(select 1 from public.diurna_sync_tombstones
      where user_id=conn.user_id and entity_type=p_entity_type and entity_id=p_candidate_id) then
      return jsonb_build_object('result','ignored','reason','tombstone');
    end if;
    execute format('select to_jsonb(r) from public.%I r where id=$1 and user_id=$2 for update',p_entity_type)
      into current_row using p_candidate_id,conn.user_id;
    if current_row is not null then
      if exists(select 1 from public.external_sync_links where connection_id=conn.id
        and entity_type=p_entity_type and entity_id=p_candidate_id) then
        return jsonb_build_object('result','ignored','reason','entity_already_linked');
      end if;
      recovered := true;
      v_entity_id := p_candidate_id;
      rev := (current_row->>'revision')::bigint;
    end if;
  end if;
  if not recovered then
    if p_unsupported_reason is not null then
      return jsonb_build_object('result','ignored','reason','unsupported_content');
    end if;
    -- Match repository required fields. Incomplete remote drafts remain retryable.
    if (p_entity_type='inbox_items' and nullif(btrim(p_patch->>'content'),'') is null)
       or (p_entity_type in ('memos','diary_entries','calendar_events') and nullif(btrim(p_patch->>'title'),'') is null)
       or (p_entity_type='diary_entries' and (nullif(btrim(p_patch->>'content'),'') is null or nullif(p_patch->>'entry_date','') is null))
       or (p_entity_type='calendar_events' and nullif(p_patch->>'event_date','') is null) then
      return jsonb_build_object('result','ignored','reason','missing_required_fields');
    end if;
    if p_entity_type='inbox_items' and coalesce((p_patch->>'is_completed')::boolean,false)
       and (p_patch->>'item_type') is distinct from 'action' then
      return jsonb_build_object('result','ignored','reason','invalid_inbox_completion');
    end if;
    v_entity_id := gen_random_uuid();
    if p_entity_type='calendar_events' then
      insert into public.calendar_events(id,user_id,title,event_date,note,revision)
        values(v_entity_id,conn.user_id,p_patch->>'title',(p_patch->>'event_date')::date,p_patch->>'note',1);
    elsif p_entity_type='memos' then
      select coalesce(min(position),0)-1 into pos from public.memos where user_id=conn.user_id;
      insert into public.memos(id,user_id,title,content,position,revision)
        values(v_entity_id,conn.user_id,p_patch->>'title',coalesce(p_patch->>'content',''),pos,1);
    elsif p_entity_type='diary_entries' then
      insert into public.diary_entries(id,user_id,title,content,entry_date,mood,revision)
        values(v_entity_id,conn.user_id,p_patch->>'title',p_patch->>'content',(p_patch->>'entry_date')::date,p_patch->>'mood',1);
    else
      select coalesce(min(position),0)-1 into pos from public.inbox_items where user_id=conn.user_id
        and inbox_column=coalesce(p_patch->>'inbox_column','pending') and not is_archived;
      insert into public.inbox_items(id,user_id,content,item_type,inbox_column,position,is_completed,is_pinned,is_archived,is_topic,revision)
        values(v_entity_id,conn.user_id,p_patch->>'content',p_patch->>'item_type',coalesce(p_patch->>'inbox_column','pending'),pos,
          case when p_patch->>'item_type'='action' then coalesce((p_patch->>'is_completed')::boolean,false) else false end,
          coalesce((p_patch->>'is_pinned')::boolean,false),coalesce((p_patch->>'is_archived')::boolean,false),
          coalesce((p_patch->>'is_topic')::boolean,false),1);
    end if;
  end if;
  insert into public.external_sync_links(user_id,connection_id,provider,entity_type,entity_id,external_id,
    external_container_id,last_synced_revision,sync_status,inbound_state,external_etag,external_updated_at,
    last_synced_at,last_remote_event_at,outbound_hold)
    values(conn.user_id,conn.id,p_provider,p_entity_type,v_entity_id,p_external_id,expected_container,rev,'synced','ready',
      p_provider_etag,p_provider_updated_at,now(),now(),false);
  if recovered then
    if p_unsupported_reason is not null then
      outcome := integrations.freeze_link_conflict(conn.id,p_entity_type,v_entity_id,p_external_id,
        'unsupported_content',coalesce(p_remote_snapshot,'{}'::jsonb),p_provider_etag,p_provider_updated_at);
      return outcome || jsonb_build_object('entity_id',v_entity_id,'revision',rev);
    end if;
    outcome := integrations.bootstrap_link_version(conn.id,p_entity_type,v_entity_id,p_external_id,
      p_provider_etag,p_provider_updated_at,not integrations._patch_equals_row(current_row,p_patch),
      'bootstrap_remote_drift',current_row,coalesce(p_remote_snapshot,'{}'::jsonb));
    if outcome->>'result'='conflict' then
      return outcome || jsonb_build_object('entity_id',v_entity_id,'revision',rev);
    end if;
  end if;
  if p_provider='notion' and not recovered then
    insert into integrations.remote_object_status(connection_id,external_id,metadata_pending,initial_patch_hash,initial_revision)
      values(conn.id,p_external_id,true,encode(sha256(convert_to(p_patch::text,'UTF8')),'hex'),rev)
      on conflict(connection_id,external_id) do update set reason=null,metadata_pending=true,
        initial_patch_hash=excluded.initial_patch_hash,initial_revision=excluded.initial_revision,updated_at=now();
  end if;
  return jsonb_build_object('result',case when recovered then 'recovered' else 'created' end,'entity_id',v_entity_id,'revision',rev);
end $$;
revoke all on function integrations.reconcile_external_object(uuid,text,text,text,text,uuid,jsonb,jsonb,text,timestamptz,text) from public,anon,authenticated;
grant execute on function integrations.reconcile_external_object(uuid,text,text,text,text,uuid,jsonb,jsonb,text,timestamptz,text) to postgres,service_role;

-- A metadata-only webhook must not manufacture a conflict with a newer local
-- revision. Compare the original mapped fingerprint, never acknowledge local edits.
create or replace function integrations.ack_remote_create_echo(
  p_connection_id uuid,p_external_id text,p_patch jsonb,p_updated_at timestamptz
) returns boolean language plpgsql security definer
set search_path=pg_catalog,public,integrations
as $$
declare conn public.integration_connections%rowtype; link public.external_sync_links%rowtype;
begin
  select * into conn from public.integration_connections where id=p_connection_id for update;
  if not found or conn.provider<>'notion' or conn.status<>'connected'
    or conn.inbound_status not in ('active','degraded','bootstrapping') then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended(conn.user_id::text,0));
  select * into link from public.external_sync_links where connection_id=conn.id and external_id=p_external_id for update;
  if not found or link.inbound_state<>'ready' or link.user_id<>conn.user_id then return false; end if;
  if not exists(select 1 from integrations.remote_object_status s where s.connection_id=conn.id and s.external_id=p_external_id
    and s.initial_revision=link.last_synced_revision and s.initial_patch_hash=encode(sha256(convert_to(p_patch::text,'UTF8')),'hex')) then
    return false;
  end if;
  update public.external_sync_links set external_updated_at=greatest(external_updated_at,p_updated_at),last_remote_event_at=now()
    where id=link.id;
  return true;
end $$;
revoke all on function integrations.ack_remote_create_echo(uuid,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function integrations.ack_remote_create_echo(uuid,text,jsonb,timestamptz) to postgres,service_role;
