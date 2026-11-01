-- =============================================================================
-- Solea — Absence automatique par géolocalisation (optionnelle)
--
--   climate_settings.geo_enabled : Absence automatique quand tous les membres
--     qui partagent leur présence sont partis (plus loin que geo_radius mètres
--     du logement depuis 10 minutes), retour au programme dès que l'un d'eux
--     revient. geo_away est écrit par la passerelle (Absence qu'elle a mise).
--   member_presence : une ligne par membre qui partage sa présence depuis son
--     téléphone. Ni la position ni le trajet ne sont gardés : seulement « à la
--     maison » ou non, et la distance arrondie. Chacun ne voit que sa ligne et
--     peut la supprimer (arrêt du partage).
--   report_presence() : le téléphone envoie sa position, le serveur calcule la
--     distance au logement et ne garde que le résultat.
-- =============================================================================

alter table public.climate_settings
  add column if not exists geo_enabled boolean not null default false,
  add column if not exists geo_radius integer not null default 300,
  add column if not exists geo_away boolean not null default false;

do $$ begin
  alter table public.climate_settings add constraint climate_settings_geo_radius_check
    check (geo_radius between 100 and 5000);
exception when duplicate_object then null;
end $$;

create table if not exists public.member_presence (
  home_id    uuid not null references public.homes (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  at_home    boolean not null,
  distance_m integer not null check (distance_m >= 0),
  since      timestamptz not null default now(),   -- dernier départ ou retour
  updated_at timestamptz not null default now(),
  primary key (home_id, user_id)
);

alter table public.member_presence enable row level security;
drop policy if exists member_presence_select on public.member_presence;
drop policy if exists member_presence_delete on public.member_presence;
create policy member_presence_select on public.member_presence for select to authenticated
  using (user_id = auth.uid());
create policy member_presence_delete on public.member_presence for delete to authenticated
  using (user_id = auth.uid());
revoke insert, update on public.member_presence from anon, authenticated;
grant select, delete on public.member_presence to authenticated;

create or replace function public.report_presence(p_home_id uuid, p_lat double precision, p_lon double precision)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  h record;
  v_radius integer;
  v_dist double precision;
  v_home boolean;
begin
  if auth.uid() is null or not public.is_home_member(p_home_id) then raise exception 'Accès refusé'; end if;
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'Position invalide';
  end if;
  select latitude, longitude into h from public.homes where id = p_home_id;
  if h.latitude is null or h.longitude is null then raise exception 'Position du logement inconnue'; end if;
  select geo_radius into v_radius from public.climate_settings where home_id = p_home_id;
  v_radius := coalesce(v_radius, 300);
  -- Distance à vol d'oiseau (haversine), en mètres.
  v_dist := 2 * 6371000 * asin(sqrt(
    power(sin(radians(p_lat - h.latitude::double precision) / 2), 2) +
    cos(radians(h.latitude::double precision)) * cos(radians(p_lat)) *
    power(sin(radians(p_lon - h.longitude::double precision) / 2), 2)));
  v_home := v_dist <= v_radius;
  insert into public.member_presence as m (home_id, user_id, at_home, distance_m)
  values (p_home_id, auth.uid(), v_home, round(v_dist / 50) * 50)
  on conflict (home_id, user_id) do update
    set at_home = excluded.at_home,
        distance_m = excluded.distance_m,
        since = case when m.at_home = excluded.at_home then m.since else now() end,
        updated_at = now();
  return v_home;
end $$;
revoke all on function public.report_presence(uuid, double precision, double precision) from public;
grant execute on function public.report_presence(uuid, double precision, double precision) to authenticated;
