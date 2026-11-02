-- =============================================================================
-- Solea — chauffage et climatisation par pièce (phase 2)
--
--   climate_settings : réglage du logement. Températures des ambiances
--     (Confort, Éco, Nuit, Absence, Hors-gel) en chauffage et en climatisation,
--     et ambiance imposée à toute la maison (« Absence jusqu'à dimanche »).
--   climate_zones : une zone par pièce. Appareils pilotés (clims, radiateurs,
--     vannes, thermostats), programme de la semaine, dérogation de la pièce.
--     La passerelle y écrit l'ambiance en cours (active_*).
--
--   La passerelle applique : dérogation de la pièce > ambiance de la maison >
--   Vacances (Absence) > programme. Hiver = chauffage, Été = climatisation.
--   set_climate_preset() : tout membre du logement peut choisir une ambiance
--   (bouton Confort / Nuit / Absence), seuls les gestionnaires règlent le reste.
-- =============================================================================

create table if not exists public.climate_settings (
  home_id           uuid primary key references public.homes (id) on delete cascade,
  enabled           boolean not null default true,
  presets           jsonb not null default '{
    "comfort": {"heat": 21, "cool": 24},
    "eco":     {"heat": 19, "cool": 27},
    "sleep":   {"heat": 18, "cool": 26},
    "away":    {"heat": 16, "cool": 29},
    "frost":   {"heat": 7,  "cool": null}
  }'::jsonb,
  home_preset       text check (home_preset in ('comfort', 'eco', 'sleep', 'away', 'frost')),
  home_preset_until timestamptz,
  updated_by        uuid references public.profiles (id) on delete set null,
  updated_at        timestamptz not null default now()
);

create table if not exists public.climate_zones (
  id               uuid primary key default gen_random_uuid(),
  home_id          uuid not null references public.homes (id) on delete cascade,
  room_id          uuid not null unique references public.rooms (id) on delete cascade,
  enabled          boolean not null default true,
  devices          jsonb not null default '[]'::jsonb
    check (jsonb_typeof(devices) = 'array' and jsonb_array_length(devices) <= 20),
  -- Programme : [{"days":[1,2,3,4,5],"at":"06:30","preset":"comfort"}, …] (1 = lundi).
  schedule         jsonb not null default '[]'::jsonb
    check (jsonb_typeof(schedule) = 'array' and jsonb_array_length(schedule) <= 48),
  preset_override  text check (preset_override in ('comfort', 'eco', 'sleep', 'away', 'frost')),
  override_until   timestamptz,
  -- Écrit par la passerelle : ambiance et consigne appliquées, et pourquoi.
  active_preset    text,
  active_target    numeric,
  active_source    text,
  active_since     timestamptz,
  updated_at       timestamptz not null default now()
);
create index if not exists climate_zones_home on public.climate_zones (home_id);

drop trigger if exists climate_settings_updated_at on public.climate_settings;
create trigger climate_settings_updated_at before update on public.climate_settings
  for each row execute function public.set_updated_at();
drop trigger if exists climate_zones_updated_at on public.climate_zones;
create trigger climate_zones_updated_at before update on public.climate_zones
  for each row execute function public.set_updated_at();

-- Températures des ambiances : nombres entre 5 et 35 °C (ou null : pas de clim en Hors-gel).
create or replace function public.check_climate_settings()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  p text;
  m text;
  v jsonb;
begin
  if jsonb_typeof(new.presets) <> 'object' then raise exception 'Ambiances invalides'; end if;
  for p in select jsonb_object_keys(new.presets) loop
    if p not in ('comfort', 'eco', 'sleep', 'away', 'frost') then raise exception 'Ambiance inconnue : %', p; end if;
    for m in select unnest(array['heat', 'cool']) loop
      v := new.presets -> p -> m;
      if v is not null and jsonb_typeof(v) <> 'null' and
         (jsonb_typeof(v) <> 'number' or (v::text)::numeric < 5 or (v::text)::numeric > 35) then
        raise exception 'Température hors limites (5 à 35 °C) : % / %', p, m;
      end if;
    end loop;
  end loop;
  if auth.uid() is not null then new.updated_by := auth.uid(); end if;
  return new;
end $$;
drop trigger if exists climate_settings_check on public.climate_settings;
create trigger climate_settings_check before insert or update on public.climate_settings
  for each row execute function public.check_climate_settings();

-- La pièce et les appareils appartiennent au logement ; programme bien formé.
create or replace function public.check_climate_zone()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  d text;
  e jsonb;
begin
  if not exists (select 1 from public.rooms where id = new.room_id and home_id = new.home_id) then
    raise exception 'Pièce inconnue pour ce logement';
  end if;
  -- Contrôlés seulement quand ils changent : un appareil supprimé plus tard ne bloque pas
  -- la mise à jour de l'ambiance en cours par la passerelle.
  if tg_op = 'UPDATE' and new.devices = old.devices and new.schedule = old.schedule then
    return new;
  end if;
  for d in select jsonb_array_elements_text(new.devices) loop
    if d !~ '^[0-9a-f-]{36}$' or not exists (
      select 1 from public.devices where id = d::uuid and home_id = new.home_id) then
      raise exception 'Appareil inconnu pour cette pièce';
    end if;
  end loop;
  for e in select jsonb_array_elements(new.schedule) loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e ->> 'at', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or coalesce(e ->> 'preset', '') not in ('comfort', 'eco', 'sleep', 'away', 'frost')
       or jsonb_typeof(e -> 'days') is distinct from 'array'
       or jsonb_array_length(e -> 'days') = 0
       or exists (select 1 from jsonb_array_elements_text(e -> 'days') x where x !~ '^[1-7]$') then
      raise exception 'Programme invalide';
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists climate_zones_check on public.climate_zones;
create trigger climate_zones_check before insert or update on public.climate_zones
  for each row execute function public.check_climate_zone();

alter table public.climate_settings enable row level security;
alter table public.climate_zones enable row level security;

drop policy if exists climate_settings_select on public.climate_settings;
drop policy if exists climate_settings_insert on public.climate_settings;
drop policy if exists climate_settings_update on public.climate_settings;
create policy climate_settings_select on public.climate_settings for select to authenticated
  using (public.is_home_member(home_id));
create policy climate_settings_insert on public.climate_settings for insert to authenticated
  with check (public.is_home_manager(home_id));
create policy climate_settings_update on public.climate_settings for update to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));

drop policy if exists climate_zones_select on public.climate_zones;
drop policy if exists climate_zones_insert on public.climate_zones;
drop policy if exists climate_zones_update on public.climate_zones;
drop policy if exists climate_zones_delete on public.climate_zones;
create policy climate_zones_select on public.climate_zones for select to authenticated
  using (public.is_home_member(home_id));
create policy climate_zones_insert on public.climate_zones for insert to authenticated
  with check (public.is_home_manager(home_id));
create policy climate_zones_update on public.climate_zones for update to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));
create policy climate_zones_delete on public.climate_zones for delete to authenticated
  using (public.is_home_manager(home_id));

-- Bouton d'ambiance : toute la maison (p_room_id null) ou une pièce, jusqu'à une date
-- (null = jusqu'au prochain changement). p_preset null = retour au programme.
create or replace function public.set_climate_preset(p_home_id uuid, p_room_id uuid, p_preset text, p_until timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_home_member(p_home_id) then raise exception 'Accès refusé'; end if;
  if p_preset is not null and p_preset not in ('comfort', 'eco', 'sleep', 'away', 'frost') then
    raise exception 'Ambiance inconnue';
  end if;
  if p_until is not null and p_until <= now() then raise exception 'Date déjà passée'; end if;
  if p_room_id is null then
    insert into public.climate_settings (home_id, home_preset, home_preset_until)
    values (p_home_id, p_preset, case when p_preset is null then null else p_until end)
    on conflict (home_id) do update
      set home_preset = excluded.home_preset, home_preset_until = excluded.home_preset_until;
  else
    update public.climate_zones
      set preset_override = p_preset, override_until = case when p_preset is null then null else p_until end
      where home_id = p_home_id and room_id = p_room_id;
    if not found then raise exception 'Cette pièce n''a pas de chauffage ni de clim réglés'; end if;
  end if;
end $$;
revoke all on function public.set_climate_preset(uuid, uuid, text, timestamptz) from public;
grant execute on function public.set_climate_preset(uuid, uuid, text, timestamptz) to authenticated;

do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['climate_settings', 'climate_zones'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
