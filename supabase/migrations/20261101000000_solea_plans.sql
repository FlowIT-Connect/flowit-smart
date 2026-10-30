-- =============================================================================
-- Solea — offre gratuite limitée à 5 appareils par logement, déblocage après paiement
--
--   home_plans          : déblocage payé d'un logement (absent = offre gratuite).
--                         paid_until null = sans date de fin. Après la date de fin, les
--                         appareils déjà présents continuent de marcher ; seul l'ajout
--                         de nouveaux appareils se bloque.
--   devices (trigger)   : au-delà de la limite, la base refuse le nouvel appareil
--                         (message commençant par « LIMITE_APPAREILS »). La passerelle le
--                         compte comme « en attente » et le crée tout seul au prochain
--                         inventaire, dès que le logement est débloqué.
--   upgrade_requests    : demandes de déblocage envoyées par le propriétaire.
--   platform_admins     : comptes de l'exploitant Solea (page « Paiements »).
--   get_home_plan()     : compteur affiché dans l'application.
--   admin_*()           : liste et décision des demandes, réservées à l'exploitant.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Exploitant de la plateforme
-- -----------------------------------------------------------------------------
create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.platform_admins a where a.user_id = auth.uid())
$$;
revoke execute on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- -----------------------------------------------------------------------------
-- Déblocage payé d'un logement
-- -----------------------------------------------------------------------------
create table if not exists public.home_plans (
  home_id         uuid primary key references public.homes (id) on delete cascade,
  device_limit    integer not null check (device_limit between 1 and 1000),
  paid_until      timestamptz,
  waiting_devices integer not null default 0 check (waiting_devices >= 0), -- tenu par la passerelle
  updated_at      timestamptz not null default now()
);
alter table public.home_plans enable row level security;
revoke all on public.home_plans from anon, authenticated;
drop trigger if exists home_plans_updated_at on public.home_plans;
create trigger home_plans_updated_at before update on public.home_plans
  for each row execute function public.set_updated_at();

-- Limite actuelle : 5 sans déblocage valide.
create or replace function public.home_device_limit(p_home_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select greatest(p.device_limit, 5) from public.home_plans p
      where p.home_id = p_home_id and (p.paid_until is null or p.paid_until > now())),
    5)
$$;
revoke execute on function public.home_device_limit(uuid) from public, anon, authenticated;

create or replace function public.check_device_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_limit integer;
begin
  -- Deux ajouts simultanés dans le même logement ne doivent pas dépasser la limite.
  perform pg_advisory_xact_lock(hashtext('device_limit:' || new.home_id::text));
  v_limit := public.home_device_limit(new.home_id);
  if (select count(*) from public.devices d where d.home_id = new.home_id) >= v_limit then
    raise exception 'LIMITE_APPAREILS : % appareils au plus pour ce logement', v_limit
      using errcode = 'P0001', hint = 'device_limit';
  end if;
  return new;
end $$;
drop trigger if exists devices_limit_check on public.devices;
create trigger devices_limit_check before insert on public.devices
  for each row execute function public.check_device_limit();

-- -----------------------------------------------------------------------------
-- Demandes de déblocage
-- -----------------------------------------------------------------------------
create table if not exists public.upgrade_requests (
  id           uuid primary key default gen_random_uuid(),
  home_id      uuid not null references public.homes (id) on delete cascade,
  requested_by uuid references public.profiles (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  note         text check (note is null or char_length(note) <= 300),
  device_limit integer,
  paid_until   timestamptz,
  decided_by   uuid references public.profiles (id) on delete set null,
  decided_at   timestamptz,
  created_at   timestamptz not null default now()
);
create unique index if not exists upgrade_requests_one_pending on public.upgrade_requests (home_id) where status = 'pending';
alter table public.upgrade_requests enable row level security;
revoke all on public.upgrade_requests from anon, authenticated;

-- Le propriétaire (ou un administrateur du logement) demande le déblocage.
create or replace function public.request_upgrade(p_home_id uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_note text := nullif(trim(p_note), '');
begin
  if not public.is_home_manager(p_home_id) then
    raise exception 'Réservé au propriétaire ou à un administrateur';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'Message trop long (300 caractères au plus)';
  end if;
  select id into v_id from public.upgrade_requests where home_id = p_home_id and status = 'pending';
  if v_id is not null then
    return v_id; -- une seule demande en attente par logement
  end if;
  insert into public.upgrade_requests (home_id, requested_by, note)
  values (p_home_id, auth.uid(), v_note)
  returning id into v_id;
  perform public.log_event(p_home_id, 'config_changed', null, v_id, 'upgrade_requested', '{}'::jsonb);
  return v_id;
end $$;
revoke execute on function public.request_upgrade(uuid, text) from public, anon;
grant execute on function public.request_upgrade(uuid, text) to authenticated;

-- Compteur du logement, pour tous ses membres.
create or replace function public.get_home_plan(p_home_id uuid)
returns table (device_count integer, device_limit integer, paid_until timestamptz,
               waiting_devices integer, pending_request boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_home_member(p_home_id) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return query select
    (select count(*)::integer from public.devices d where d.home_id = p_home_id),
    public.home_device_limit(p_home_id),
    (select p.paid_until from public.home_plans p
      where p.home_id = p_home_id and (p.paid_until is null or p.paid_until > now())),
    coalesce((select p.waiting_devices from public.home_plans p where p.home_id = p_home_id), 0),
    exists (select 1 from public.upgrade_requests r where r.home_id = p_home_id and r.status = 'pending');
end $$;
revoke execute on function public.get_home_plan(uuid) from public, anon;
grant execute on function public.get_home_plan(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Exploitant : liste des logements et décision
-- -----------------------------------------------------------------------------
create or replace function public.admin_list_upgrades()
returns table (request_id uuid, home_id uuid, home_name text, owner_email text, owner_name text,
               status text, note text, device_count integer, device_limit integer,
               paid_until timestamptz, waiting_devices integer, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  -- Demandes en attente d'abord, puis les 100 dernières décisions.
  return query
  select r.id, h.id, h.name, u.email::text, pr.display_name, r.status, r.note,
         (select count(*)::integer from public.devices d where d.home_id = h.id),
         public.home_device_limit(h.id),
         (select p.paid_until from public.home_plans p where p.home_id = h.id),
         coalesce((select p.waiting_devices from public.home_plans p where p.home_id = h.id), 0),
         r.created_at
    from public.upgrade_requests r
    join public.homes h on h.id = r.home_id
    left join auth.users u on u.id = h.owner_id
    left join public.profiles pr on pr.id = h.owner_id
   where r.status = 'pending'
      or r.id in (select x.id from public.upgrade_requests x where x.status <> 'pending' order by x.decided_at desc nulls last limit 100)
   order by (r.status = 'pending') desc, coalesce(r.decided_at, r.created_at) desc;
end $$;
revoke execute on function public.admin_list_upgrades() from public, anon;
grant execute on function public.admin_list_upgrades() to authenticated;

-- Paiement reçu (p_approve) : p_device_limit appareils, pendant p_months mois (null = sans fin).
-- Un renouvellement prolonge à partir de la date de fin encore valide.
create or replace function public.admin_decide_upgrade(
  p_request_id uuid, p_approve boolean, p_device_limit integer default null, p_months integer default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.upgrade_requests;
  v_until timestamptz;
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  select * into r from public.upgrade_requests where id = p_request_id for update;
  if r.id is null or r.status <> 'pending' then
    raise exception 'Demande introuvable ou déjà traitée';
  end if;
  if not p_approve then
    update public.upgrade_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now() where id = r.id;
    perform public.log_event(r.home_id, 'config_changed', null, r.id, 'upgrade_rejected', '{}'::jsonb);
    return;
  end if;
  if p_device_limit is null or p_device_limit not between 6 and 1000 then
    raise exception 'Nombre d''appareils : entre 6 et 1000';
  end if;
  if p_months is not null and p_months not between 1 and 120 then
    raise exception 'Durée : entre 1 et 120 mois';
  end if;
  if p_months is not null then
    select greatest(coalesce(p.paid_until, now()), now()) + make_interval(months => p_months) into v_until
      from public.home_plans p where p.home_id = r.home_id and p.paid_until is not null;
    v_until := coalesce(v_until, now() + make_interval(months => p_months));
  end if;
  insert into public.home_plans (home_id, device_limit, paid_until)
  values (r.home_id, p_device_limit, v_until)
  on conflict (home_id) do update set device_limit = excluded.device_limit, paid_until = excluded.paid_until;
  update public.upgrade_requests
     set status = 'approved', device_limit = p_device_limit, paid_until = v_until, decided_by = auth.uid(), decided_at = now()
   where id = r.id;
  perform public.log_event(r.home_id, 'config_changed', null, r.id, 'upgrade_approved',
    jsonb_build_object('device_limit', p_device_limit, 'paid_until', v_until));
end $$;
revoke execute on function public.admin_decide_upgrade(uuid, boolean, integer, integer) from public, anon;
grant execute on function public.admin_decide_upgrade(uuid, boolean, integer, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- Ajout depuis l'application : refus immédiat quand la limite est atteinte,
-- plutôt qu'après 5 minutes de recherche par la passerelle.
-- -----------------------------------------------------------------------------
create or replace function public.request_pairing(
  p_home_id uuid, p_kind text, p_name text default null, p_room_id uuid default null, p_lock_data text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_name text := nullif(trim(p_name), '');
  v_limit integer;
begin
  if not public.is_home_manager(p_home_id) then
    raise exception 'Réservé au propriétaire ou à un administrateur';
  end if;
  if p_kind not in ('ttlock_lock', 'scan') then
    raise exception 'Type d''ajout inconnu';
  end if;
  v_limit := public.home_device_limit(p_home_id);
  if (select count(*) from public.devices d where d.home_id = p_home_id) >= v_limit then
    raise exception 'LIMITE_APPAREILS : % appareils au plus pour ce logement', v_limit
      using hint = 'device_limit';
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
