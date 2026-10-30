-- =============================================================================
-- Solea — ajouter un appareil depuis l'application
--
-- L'application ne parle jamais directement aux clouds Tuya ou TTLock : elle dépose une
-- demande, la passerelle (service_role) la traite puis renseigne l'appareil créé.
--
--   pairing_requests : une demande d'ajout par appareil.
--     kind 'ttlock_lock' : serrure installée en Bluetooth par l'app Android ; lock_data
--                          (clé administrateur renvoyée par la serrure) est enregistrée
--                          sur le compte TTLock par la passerelle puis effacée.
--     kind 'scan'        : appareil couplé dans Smart Life ; la passerelle relit tout de
--                          suite l'inventaire et repère le premier appareil apparu depuis
--                          la demande.
--     Dans les deux cas, la passerelle donne à l'appareil le nom et la pièce choisis.
--   request_pairing() : propriétaire ou administrateur, journalisé.
--   lock_data ne se lit jamais depuis l'application (droits par colonne).
-- =============================================================================

create table if not exists public.pairing_requests (
  id           uuid primary key default gen_random_uuid(),
  home_id      uuid not null references public.homes (id) on delete cascade,
  requested_by uuid references public.profiles (id) on delete set null,
  kind         text not null check (kind in ('ttlock_lock', 'scan')),
  name         text check (name is null or char_length(name) between 1 and 60),
  room_id      uuid references public.rooms (id) on delete set null,
  lock_data    text,
  status       text not null default 'pending' check (status in ('pending', 'working', 'done', 'failed')),
  error        text,
  device_id    uuid references public.devices (id) on delete set null,
  created_at   timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists pairing_requests_open_idx on public.pairing_requests (home_id, created_at)
  where status in ('pending', 'working');

alter table public.pairing_requests enable row level security;
revoke all on public.pairing_requests from anon, authenticated;
grant select (id, home_id, kind, name, room_id, status, error, device_id, created_at, completed_at)
  on public.pairing_requests to authenticated;
drop policy if exists pairing_requests_select on public.pairing_requests;
create policy pairing_requests_select on public.pairing_requests for select to authenticated
  using (public.is_home_manager(home_id));

create or replace function public.request_pairing(
  p_home_id uuid, p_kind text, p_name text default null, p_room_id uuid default null, p_lock_data text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_name text := nullif(trim(p_name), '');
begin
  if not public.is_home_manager(p_home_id) then
    raise exception 'Réservé au propriétaire ou à un administrateur';
  end if;
  if p_kind not in ('ttlock_lock', 'scan') then
    raise exception 'Type d''ajout inconnu';
  end if;
  if p_kind = 'ttlock_lock' and (p_lock_data is null or char_length(p_lock_data) not between 16 and 20000) then
    raise exception 'Clé de la serrure manquante';
  end if;
  if v_name is not null and char_length(v_name) > 60 then
    raise exception 'Nom trop long (60 caractères au plus)';
  end if;
  if p_room_id is not null and not exists (select 1 from public.rooms r where r.id = p_room_id and r.home_id = p_home_id) then
    raise exception 'La pièce n''appartient pas à cette maison';
  end if;
  if (select count(*) from public.pairing_requests
      where home_id = p_home_id and status in ('pending', 'working') and created_at > now() - interval '15 minutes') >= 5 then
    raise exception 'Trop d''ajouts en cours : patientez quelques minutes';
  end if;
  insert into public.pairing_requests (home_id, requested_by, kind, name, room_id, lock_data)
  values (p_home_id, auth.uid(), p_kind, v_name, p_room_id, case when p_kind = 'ttlock_lock' then p_lock_data end)
  returning id into v_id;
  perform public.log_event(p_home_id, 'config_changed', null, v_id, 'pairing_requested', jsonb_build_object('kind', p_kind));
  return v_id;
end $$;
revoke execute on function public.request_pairing(uuid, text, text, uuid, text) from public, anon;
grant execute on function public.request_pairing(uuid, text, text, uuid, text) to authenticated;
