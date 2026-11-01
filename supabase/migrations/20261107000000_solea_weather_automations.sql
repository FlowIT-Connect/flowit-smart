-- =============================================================================
-- Solea — automatisations météo, soleil, présence (exécutées par la passerelle)
--
--   homes.latitude / longitude / location_name : position du logement, pour
--       la météo et les heures de lever / coucher du soleil.
--   automations.exceptions : « SAUF SI » (aucune ne doit être vraie)
--   automations.follow_up  : « PUIS » {after_minutes, actions, conditions,
--       restart_on_trigger} : actions différées (rouvrir les volets quand le vent
--       est retombé, éteindre la lumière quand plus personne n'est détecté…)
--   automations.priority   : 'security' = évaluée et exécutée en premier
--   automation_runs        : historique d'exécution (lecture par les membres)
--   weather_readings       : relevés météo de la passerelle (7 jours gardés)
--
-- Déclencheurs ajoutés (JSON) :
--   {"type":"weather","metric":"wind_speed","op":"gt","value":80,"for_minutes":2}
--     metric : wind_speed | wind_gust | precipitation | temperature (extérieure)
--   {"type":"sun","event":"sunset","offset_minutes":-15}
-- Conditions ajoutées :
--   {"type":"weather","metric":…,"op":…,"value":…}   {"type":"sun","is":"night"}
-- =============================================================================

alter table public.homes
  add column if not exists latitude numeric(8, 5) check (latitude is null or latitude between -90 and 90),
  add column if not exists longitude numeric(8, 5) check (longitude is null or longitude between -180 and 180),
  add column if not exists location_name text check (location_name is null or length(location_name) <= 120);

alter table public.automations
  add column if not exists exceptions jsonb not null default '[]'::jsonb,
  add column if not exists follow_up jsonb,
  add column if not exists priority text not null default 'normal';

do $$ begin
  alter table public.automations add constraint automations_exceptions_array
    check (jsonb_typeof(exceptions) = 'array' and jsonb_array_length(exceptions) <= 10);
exception when duplicate_object then null;
end $$;
do $$ begin
  alter table public.automations add constraint automations_follow_up_shape
    check (follow_up is null or (
      jsonb_typeof(follow_up) = 'object'
      and jsonb_typeof(follow_up -> 'after_minutes') = 'number'
      and (follow_up ->> 'after_minutes')::numeric between 0 and 1440
      and jsonb_typeof(follow_up -> 'actions') = 'array'
      and jsonb_array_length(follow_up -> 'actions') between 1 and 20
      and (not follow_up ? 'conditions' or jsonb_typeof(follow_up -> 'conditions') = 'array')));
exception when duplicate_object then null;
end $$;
do $$ begin
  alter table public.automations add constraint automations_priority_check check (priority in ('normal', 'security'));
exception when duplicate_object then null;
end $$;
do $$ begin
  alter table public.automations add constraint automations_trigger_type
    check (trigger ->> 'type' in ('manual', 'time', 'device_state', 'weather', 'sun', 'mode'));
exception when duplicate_object then null;
end $$;

-- -----------------------------------------------------------------------------
-- Historique d'exécution
-- -----------------------------------------------------------------------------
create table if not exists public.automation_runs (
  id            bigint generated always as identity primary key,
  home_id       uuid not null references public.homes (id) on delete cascade,
  automation_id uuid references public.automations (id) on delete set null,
  name          text not null default '',
  phase         text not null default 'main' check (phase in ('main', 'follow_up')),
  status        text not null check (status in ('success', 'partial', 'failed', 'skipped')),
  reason        text not null default '' check (length(reason) <= 200),
  details       jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object' and pg_column_size(details) <= 4096),
  created_at    timestamptz not null default now()
);
create index if not exists automation_runs_home_idx on public.automation_runs (home_id, created_at desc);
create index if not exists automation_runs_automation_idx on public.automation_runs (automation_id, created_at desc);
alter table public.automation_runs enable row level security;
drop policy if exists automation_runs_select on public.automation_runs;
create policy automation_runs_select on public.automation_runs for select to authenticated
  using (public.is_home_member(home_id));
revoke insert, update, delete on public.automation_runs from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Relevés météo (écrits par la passerelle)
-- -----------------------------------------------------------------------------
create table if not exists public.weather_readings (
  id            bigint generated always as identity primary key,
  home_id       uuid not null references public.homes (id) on delete cascade,
  observed_at   timestamptz not null default now(),
  wind_speed    numeric,   -- km/h
  wind_gust     numeric,   -- km/h
  precipitation numeric,   -- mm
  temperature   numeric,   -- °C extérieur
  is_day        boolean,
  sunrise       timestamptz,
  sunset        timestamptz,
  source        text not null default 'open-meteo' check (length(source) <= 40)
);
create index if not exists weather_readings_home_idx on public.weather_readings (home_id, observed_at desc);
alter table public.weather_readings enable row level security;
drop policy if exists weather_readings_select on public.weather_readings;
create policy weather_readings_select on public.weather_readings for select to authenticated
  using (public.is_home_member(home_id));
revoke insert, update, delete on public.weather_readings from anon, authenticated;

create or replace function public.purge_weather_readings(p_days integer default 7)
returns integer language sql security definer set search_path = '' as $$
  with d as (
    delete from public.weather_readings where observed_at < now() - make_interval(days => p_days) returning 1)
  select count(*)::integer from d
$$;
revoke execute on function public.purge_weather_readings(integer) from public, anon, authenticated;

create or replace function public.purge_automation_runs(p_days integer default 90)
returns integer language sql security definer set search_path = '' as $$
  with d as (
    delete from public.automation_runs where created_at < now() - make_interval(days => p_days) returning 1)
  select count(*)::integer from d
$$;
revoke execute on function public.purge_automation_runs(integer) from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'automation_runs') then
    alter publication supabase_realtime add table public.automation_runs;
  end if;
end $$;
