-- Authenticated clients may manage only their own schedule and installation.
-- The queue contains public presentation metadata, never summary narration.
create table if not exists public.companion_preferences (
  firebase_uid text primary key references public.app_accounts(firebase_uid) on delete cascade,
  daily_enabled boolean not null default true,
  urgent_enabled boolean not null default false,
  hour integer not null default 8 check (hour between 0 and 23),
  minute integer not null default 0 check (minute between 0 and 59),
  time_zone text not null default 'UTC' check (length(time_zone) between 1 and 100),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);
create table if not exists public.companion_devices (
  installation_id uuid primary key,
  firebase_uid text not null references public.app_accounts(firebase_uid) on delete cascade,
  device_token text, start_token text, activity_token text, activity_id text,
  environment text not null check (environment in ('sandbox','production')),
  routine_enabled boolean not null default true,
  urgent_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (installation_id, firebase_uid),
  check (device_token is null or (length(device_token) between 32 and 512 and device_token ~ '^[0-9a-f]+$')),
  check (start_token is null or (length(start_token) between 32 and 512 and start_token ~ '^[0-9a-f]+$')),
  check (activity_token is null or (length(activity_token) between 32 and 512 and activity_token ~ '^[0-9a-f]+$')),
  check (activity_id is null or length(activity_id) between 1 and 128)
);
create table if not exists public.companion_delivery_jobs (
  id bigint generated always as identity primary key,
  firebase_uid text not null,
  installation_id uuid not null,
  event_key text not null check (length(event_key) <= 200),
  kind text not null check (kind in ('routine','urgent','end')),
  generated_at timestamptz not null,
  expires_at timestamptz not null,
  available_at timestamptz not null default now(),
  attempts integer not null default 0,
  state text not null default 'pending' check (state in ('pending','sending','sent','failed')),
  lease_id uuid,
  last_error text check (length(last_error) <= 100),
  created_at timestamptz not null default now(),
  foreign key (installation_id, firebase_uid) references public.companion_devices(installation_id, firebase_uid) on delete cascade,
  unique (installation_id, event_key)
);
create index if not exists companion_delivery_due on public.companion_delivery_jobs(available_at) where state in ('pending','sending');
alter table public.companion_preferences enable row level security;
alter table public.companion_devices enable row level security;
alter table public.companion_delivery_jobs enable row level security;
revoke all on public.companion_preferences, public.companion_devices, public.companion_delivery_jobs from public, anon, authenticated;
grant select on public.companion_preferences to anon, authenticated;
grant all on public.companion_preferences, public.companion_devices, public.companion_delivery_jobs to service_role;
grant usage, select on sequence public.companion_delivery_jobs_id_seq to service_role;

create or replace function public.companion_authenticated_uid() returns text
language plpgsql stable set search_path = public, pg_temp as $$
declare uid text := auth.jwt()->>'sub';
begin
  if uid is null or auth.jwt()->>'iss' is distinct from 'https://securetoken.google.com/suzzme-e70f2'
     or auth.jwt()->>'aud' is distinct from 'suzzme-e70f2' then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  return uid;
end $$;
revoke all on function public.companion_authenticated_uid() from public;
grant execute on function public.companion_authenticated_uid() to anon, authenticated;
drop policy if exists "Own companion preferences" on public.companion_preferences;
create policy "Own companion preferences" on public.companion_preferences for select to anon, authenticated
using (firebase_uid = public.companion_authenticated_uid());

create or replace function public.save_companion_preferences(p_daily boolean, p_urgent boolean,
  p_hour integer, p_minute integer, p_time_zone text, p_expected_revision bigint)
returns public.companion_preferences language plpgsql security definer set search_path = public, pg_temp as $$
declare uid text := public.companion_authenticated_uid(); current_revision bigint; result public.companion_preferences;
begin
  if p_hour not between 0 and 23 or p_minute not between 0 and 59 or
     not exists(select 1 from pg_timezone_names where name = p_time_zone) then
    raise exception 'Invalid schedule' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid, 816));
  select revision into current_revision from public.companion_preferences where firebase_uid = uid for update;
  if coalesce(current_revision,0) is distinct from p_expected_revision then
    raise exception 'Schedule changed on another device. Refresh before saving.' using errcode = '40001';
  end if;
  insert into public.companion_preferences(firebase_uid,daily_enabled,urgent_enabled,hour,minute,time_zone,revision)
  values(uid,p_daily,p_urgent,p_hour,p_minute,p_time_zone,1)
  on conflict(firebase_uid) do update set daily_enabled=p_daily, urgent_enabled=p_urgent,
    hour=p_hour, minute=p_minute, time_zone=p_time_zone, revision=companion_preferences.revision+1, updated_at=now()
  returning * into result;
  -- Disabling delivery cancels outstanding jobs immediately.
  delete from public.companion_delivery_jobs where firebase_uid=uid and state in ('pending','sending')
    and ((kind='routine' and not p_daily) or (kind='urgent' and not p_urgent));
  return result;
end $$;

create or replace function public.register_companion_device(p_installation_id uuid, p_device_token text,
  p_start_token text, p_activity_token text, p_activity_id text, p_environment text, p_routine boolean, p_urgent boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare uid text := public.companion_authenticated_uid(); existing_uid text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_installation_id::text,817));
  select firebase_uid into existing_uid from public.companion_devices where installation_id=p_installation_id;
  -- The installation's secret UUID permits rebinding on account switch. Old jobs cannot follow it.
  if existing_uid is distinct from uid then
    delete from public.companion_devices where installation_id=p_installation_id;
  end if;
  insert into public.companion_devices(installation_id,firebase_uid,device_token,start_token,activity_token,activity_id,
    environment,routine_enabled,urgent_enabled)
  values(p_installation_id,uid,p_device_token,p_start_token,p_activity_token,p_activity_id,p_environment,p_routine,p_urgent)
  on conflict(installation_id) do update set device_token=excluded.device_token, start_token=excluded.start_token,
    activity_token=excluded.activity_token, activity_id=excluded.activity_id, environment=excluded.environment,
    routine_enabled=excluded.routine_enabled, urgent_enabled=excluded.urgent_enabled, updated_at=now();
  delete from public.companion_delivery_jobs where installation_id=p_installation_id and state in ('pending','sending')
    and ((kind='routine' and not p_routine) or (kind='urgent' and not p_urgent));
end $$;

create or replace function public.unregister_companion_device(p_installation_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.companion_devices where installation_id=p_installation_id
    and firebase_uid=public.companion_authenticated_uid();
end $$;

create or replace function public.enqueue_companion_delivery() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare prefs public.companion_preferences; generated timestamptz; due timestamptz;
  update_item jsonb; event text; expiry timestamptz;
begin
  if tg_op='DELETE' then
    delete from public.companion_delivery_jobs where firebase_uid=old.firebase_uid and state in ('pending','sending');
    insert into public.companion_delivery_jobs(firebase_uid,installation_id,event_key,kind,generated_at,expires_at)
      select firebase_uid,installation_id,'end:'||gen_random_uuid()::text,'end',now(),now()+interval '1 hour'
      from public.companion_devices where firebase_uid=old.firebase_uid and activity_token is not null;
    return old;
  end if;
  select * into prefs from public.companion_preferences where firebase_uid=new.firebase_uid;
  if not found then return new; end if;
  generated := (new.payload->>'generatedAt')::timestamptz;
  -- Future, stale, or previous-day summaries never create a fresh alert.
  if generated > now()+interval '5 minutes' or generated < now()-interval '2 hours' then return new; end if;
  due := ((date_trunc('day', now() at time zone prefs.time_zone)
    + make_interval(hours=>prefs.hour, mins=>prefs.minute)) at time zone prefs.time_zone);
  if prefs.daily_enabled and generated >= due and now() >= due and
     ((new.payload->>'localDay')::timestamptz at time zone prefs.time_zone)::date = (now() at time zone prefs.time_zone)::date then
    event := 'routine:'||prefs.time_zone||':'||to_char(due at time zone 'UTC','YYYY-MM-DD"T"HH24:MI');
    insert into public.companion_delivery_jobs(firebase_uid,installation_id,event_key,kind,generated_at,expires_at)
      select firebase_uid,installation_id,event,'routine',generated,generated+interval '2 hours'
      from public.companion_devices where firebase_uid=new.firebase_uid and routine_enabled
      on conflict(installation_id,event_key) do nothing;
  end if;
  if prefs.urgent_enabled then
    for update_item in select value from jsonb_array_elements(coalesce(new.payload->'delivery'->'urgentUpdates','[]'::jsonb)) loop
      expiry := (update_item->>'expiresAt')::timestamptz;
      if length(update_item->>'id') between 1 and 64 and expiry > now()
        and (update_item->>'createdAt')::timestamptz <= now()
        and expiry <= (update_item->>'createdAt')::timestamptz+interval '15 minutes' then
        insert into public.companion_delivery_jobs(firebase_uid,installation_id,event_key,kind,generated_at,expires_at)
          select firebase_uid,installation_id,'urgent:'||(update_item->>'id'),'urgent',generated,expiry
          from public.companion_devices where firebase_uid=new.firebase_uid and urgent_enabled
          on conflict(installation_id,event_key) do nothing;
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists companion_summary_delivery on public.companion_summaries;
create trigger companion_summary_delivery after insert or update or delete on public.companion_summaries
for each row execute function public.enqueue_companion_delivery();

-- Claim leases prevent overlapping workers from sending the same batch.
create or replace function public.claim_companion_deliveries() returns setof public.companion_delivery_jobs
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.companion_delivery_jobs where created_at < now()-interval '7 days';
  update public.companion_delivery_jobs set state='failed',last_error='Expired'
    where state in ('pending','sending') and (expires_at <= now() or (attempts >= 6 and available_at <= now()));
  return query
    with due as (select id from public.companion_delivery_jobs
      where state in ('pending','sending') and available_at <= now() and expires_at > now() and attempts < 6
      order by case kind when 'urgent' then 0 else 1 end, id for update skip locked limit 10)
    update public.companion_delivery_jobs j set state='sending',lease_id=gen_random_uuid(),attempts=attempts+1,
      available_at=now()+interval '2 minutes' from due where j.id=due.id returning j.*;
end $$;
revoke all on function public.save_companion_preferences(boolean,boolean,integer,integer,text,bigint),
  public.register_companion_device(uuid,text,text,text,text,text,boolean,boolean),
  public.unregister_companion_device(uuid),public.enqueue_companion_delivery(),public.claim_companion_deliveries() from public;
grant execute on function public.save_companion_preferences(boolean,boolean,integer,integer,text,bigint),
  public.register_companion_device(uuid,text,text,text,text,text,boolean,boolean),
  public.unregister_companion_device(uuid) to anon,authenticated;
grant execute on function public.claim_companion_deliveries() to service_role;
