-- =============================================================================
-- Solea — modes Été / Hiver / Vacances
--
--   home_modes : un mode saisonnier (été, hiver ou aucun) et le mode Vacances
--   (dates de départ et de retour, simulation de présence avec les lumières
--   choisies). Lu par la passerelle : les automatisations peuvent dépendre d'un
--   mode (condition {"type":"mode","mode":"vacation"}, déclencheur
--   {"type":"mode","mode":"summer","event":"start"}) et la simulation de
--   présence tourne sur place, même téléphone éteint. Les règles de sécurité
--   continuent pendant les vacances.
-- =============================================================================

create table if not exists public.home_modes (
  home_id             uuid primary key references public.homes (id) on delete cascade,
  season              text not null default 'none' check (season in ('none', 'summer', 'winter')),
  vacation            boolean not null default false,
  vacation_from       timestamptz,
  vacation_to         timestamptz,
  presence_simulation boolean not null default false,
  simulation_devices  jsonb not null default '[]'::jsonb
    check (jsonb_typeof(simulation_devices) = 'array' and jsonb_array_length(simulation_devices) <= 20),
  updated_by          uuid references public.profiles (id) on delete set null,
  updated_at          timestamptz not null default now(),
  check (vacation_from is null or vacation_to is null or vacation_to > vacation_from)
);

drop trigger if exists home_modes_updated_at on public.home_modes;
create trigger home_modes_updated_at before update on public.home_modes
  for each row execute function public.set_updated_at();

-- Les lumières de la simulation appartiennent au logement.
create or replace function public.check_home_modes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  d text;
begin
  for d in select jsonb_array_elements_text(new.simulation_devices) loop
    if d !~ '^[0-9a-f-]{36}$' or not exists (
      select 1 from public.devices where id = d::uuid and home_id = new.home_id) then
      raise exception 'Appareil inconnu pour la simulation de présence';
    end if;
  end loop;
  if auth.uid() is not null then new.updated_by := auth.uid(); end if;
  return new;
end $$;
drop trigger if exists home_modes_check on public.home_modes;
create trigger home_modes_check before insert or update on public.home_modes
  for each row execute function public.check_home_modes();

alter table public.home_modes enable row level security;
drop policy if exists home_modes_select on public.home_modes;
drop policy if exists home_modes_insert on public.home_modes;
drop policy if exists home_modes_update on public.home_modes;
create policy home_modes_select on public.home_modes for select to authenticated
  using (public.is_home_member(home_id));
create policy home_modes_insert on public.home_modes for insert to authenticated
  with check (public.is_home_manager(home_id));
create policy home_modes_update on public.home_modes for update to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'home_modes') then
    alter publication supabase_realtime add table public.home_modes;
  end if;
end $$;
