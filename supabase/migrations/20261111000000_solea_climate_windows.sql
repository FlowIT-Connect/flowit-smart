-- =============================================================================
-- Solea — fenêtre ouverte (phase 3)
--
--   Chaque pièce chauffée ou climatisée peut avoir des capteurs d'ouverture
--   (fenêtres, porte-fenêtre). Ouverte plus de window_delay minutes : la
--   passerelle coupe la clim ou le chauffage de la pièce et prévient ; fermée :
--   tout reprend comme avant. active_window est écrit par la passerelle.
--   Les têtes thermostatiques qui détectent elles-mêmes une fenêtre ouverte
--   (capacité window_open) comptent aussi.
-- =============================================================================

alter table public.climate_zones
  add column if not exists windows jsonb not null default '[]'::jsonb,
  add column if not exists window_delay integer not null default 2,
  add column if not exists active_window boolean not null default false;

do $$ begin
  alter table public.climate_zones add constraint climate_zones_windows_check
    check (jsonb_typeof(windows) = 'array' and jsonb_array_length(windows) <= 20);
exception when duplicate_object then null;
end $$;
do $$ begin
  alter table public.climate_zones add constraint climate_zones_window_delay_check
    check (window_delay between 0 and 30);
exception when duplicate_object then null;
end $$;

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
  if tg_op = 'UPDATE' and new.devices = old.devices and new.schedule = old.schedule and new.windows = old.windows then
    return new;
  end if;
  for d in select jsonb_array_elements_text(new.devices) loop
    if d !~ '^[0-9a-f-]{36}$' or not exists (
      select 1 from public.devices where id = d::uuid and home_id = new.home_id) then
      raise exception 'Appareil inconnu pour cette pièce';
    end if;
  end loop;
  for d in select jsonb_array_elements_text(new.windows) loop
    if d !~ '^[0-9a-f-]{36}$' or not exists (
      select 1 from public.devices where id = d::uuid and home_id = new.home_id) then
      raise exception 'Capteur de fenêtre inconnu pour ce logement';
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
