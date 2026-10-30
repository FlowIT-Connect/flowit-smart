-- =============================================================================
-- Solea — une seule passerelle pour tous les logements, appareils posés par l'installateur
--
-- L'installateur couple chaque appareil Wi-Fi dans SON compte Smart Life (ou TTLock). La
-- passerelle de la plateforme voit donc tous les appareils et les inscrit ici. L'exploitant
-- choisit ensuite, dans Solea, le logement de chacun. Le résident ne voit jamais Tuya.
--
--   platform_devices          : inventaire du compte installateur et logement attribué.
--   platform_sync_devices()   : passerelle (service_role) : inscrit l'inventaire et renvoie
--                               les attributions. Un appareil déjà présent dans un logement
--                               (ancienne passerelle) y est rattaché d'office.
--   admin_list_platform_devices(), admin_search_homes(), admin_assign_device() : exploitant.
--   get_home_plan() renvoie aussi « managed » : logement équipé par l'installateur (plateforme
--                               en service et aucune passerelle propre au logement). La
--                               passerelle marque ses intégrations external_reference = 'solea-platform'.
-- =============================================================================

create table if not exists public.platform_devices (
  external_id   text primary key,          -- ex. tuya:bf12…, ttlock:123
  name          text not null,
  vendor        text,
  model         text,
  protocol      text,
  image_url     text,
  home_id       uuid references public.homes (id) on delete set null,
  assigned_at   timestamptz,
  assigned_by   uuid references public.profiles (id) on delete set null,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);
create index if not exists platform_devices_home_idx on public.platform_devices (home_id);
alter table public.platform_devices enable row level security;
revoke all on public.platform_devices from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Passerelle de la plateforme
-- -----------------------------------------------------------------------------
create or replace function public.platform_sync_devices(p_devices jsonb)
returns table (external_id text, home_id uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_service_role() then
    raise exception 'Réservé à la passerelle' using errcode = '42501';
  end if;
  insert into public.platform_devices as p (external_id, name, vendor, model, protocol, image_url)
  select d ->> 'external_id', coalesce(nullif(d ->> 'name', ''), d ->> 'external_id'),
         d ->> 'vendor', d ->> 'model', d ->> 'protocol', d ->> 'image_url'
    from jsonb_array_elements(coalesce(p_devices, '[]'::jsonb)) d
   where d ->> 'external_id' is not null
  on conflict on constraint platform_devices_pkey do update
     set name = excluded.name, vendor = excluded.vendor, model = excluded.model,
         protocol = excluded.protocol, image_url = coalesce(excluded.image_url, p.image_url),
         last_seen_at = now();
  -- Appareil déjà installé dans un logement (passerelle d'avant) : on le garde là.
  update public.platform_devices p
     set home_id = d.home_id, assigned_at = now()
    from public.device_bindings b
    join public.devices d on d.id = b.device_id
   where p.home_id is null and p.assigned_at is null and b.external_id = p.external_id;
  return query select p.external_id, p.home_id from public.platform_devices p where p.home_id is not null;
end $$;
revoke execute on function public.platform_sync_devices(jsonb) from public, anon, authenticated;
grant execute on function public.platform_sync_devices(jsonb) to service_role;

-- -----------------------------------------------------------------------------
-- Exploitant
-- -----------------------------------------------------------------------------
create or replace function public.admin_list_platform_devices()
returns table (external_id text, name text, vendor text, model text, protocol text, image_url text,
               home_id uuid, home_name text, installed boolean, first_seen_at timestamptz, last_seen_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  return query
  select p.external_id, p.name, p.vendor, p.model, p.protocol, p.image_url, p.home_id, h.name,
         exists (select 1 from public.device_bindings b join public.devices d on d.id = b.device_id
                  where b.external_id = p.external_id and d.home_id = p.home_id),
         p.first_seen_at, p.last_seen_at
    from public.platform_devices p
    left join public.homes h on h.id = p.home_id
   order by (p.home_id is null) desc, p.last_seen_at desc;
end $$;
revoke execute on function public.admin_list_platform_devices() from public, anon;
grant execute on function public.admin_list_platform_devices() to authenticated;

create or replace function public.admin_search_homes(p_query text default null)
returns table (home_id uuid, home_name text, owner_email text, device_count integer, device_limit integer)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_q text := '%' || lower(coalesce(trim(p_query), '')) || '%';
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  return query
  select h.id, h.name, u.email::text,
         (select count(*)::integer from public.devices d where d.home_id = h.id),
         public.home_device_limit(h.id)
    from public.homes h
    left join auth.users u on u.id = h.owner_id
   where lower(h.name) like v_q or lower(coalesce(u.email, '')) like v_q
   order by h.name
   limit 50;
end $$;
revoke execute on function public.admin_search_homes(text) from public, anon;
grant execute on function public.admin_search_homes(text) to authenticated;

-- Attribue un appareil à un logement (p_home_id null : le retire). Un appareil qui change de
-- logement disparaît de l'ancien ; la passerelle le crée dans le nouveau en moins d'une minute.
create or replace function public.admin_assign_device(p_external_id text, p_home_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old uuid;
  v_limit integer;
  v_used integer;
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  select p.home_id into v_old from public.platform_devices p where p.external_id = p_external_id for update;
  if not found then
    raise exception 'Appareil inconnu';
  end if;
  if p_home_id is not distinct from v_old then
    return;
  end if;
  if p_home_id is not null then
    if not exists (select 1 from public.homes h where h.id = p_home_id) then
      raise exception 'Logement introuvable';
    end if;
    -- Appareils présents + appareils déjà attribués que la passerelle n'a pas encore créés.
    v_limit := public.home_device_limit(p_home_id);
    select (select count(*) from public.devices d where d.home_id = p_home_id)
         + (select count(*) from public.platform_devices p
             where p.home_id = p_home_id
               and not exists (select 1 from public.device_bindings b join public.devices d on d.id = b.device_id
                                where b.external_id = p.external_id and d.home_id = p_home_id))
      into v_used;
    if v_used >= v_limit then
      raise exception 'LIMITE_APPAREILS : % appareils au plus pour ce logement', v_limit using hint = 'device_limit';
    end if;
  end if;
  if v_old is not null then
    delete from public.devices d
     where d.home_id = v_old
       and d.id in (select b.device_id from public.device_bindings b where b.external_id = p_external_id);
    perform public.log_event(v_old, 'config_changed', null, null, 'device_unassigned', jsonb_build_object('external_id', p_external_id));
  end if;
  update public.platform_devices
     set home_id = p_home_id, assigned_at = now(), assigned_by = auth.uid()
   where external_id = p_external_id;
  if p_home_id is not null then
    perform public.log_event(p_home_id, 'config_changed', null, null, 'device_assigned', jsonb_build_object('external_id', p_external_id));
  end if;
end $$;
revoke execute on function public.admin_assign_device(text, uuid) from public, anon;
grant execute on function public.admin_assign_device(text, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Compteur du logement : « managed » quand l'installateur fournit les appareils
-- (l'application cache alors l'ajout par le résident).
-- -----------------------------------------------------------------------------
drop function if exists public.get_home_plan(uuid);
create function public.get_home_plan(p_home_id uuid)
returns table (device_count integer, device_limit integer, paid_until timestamptz,
               waiting_devices integer, pending_request boolean, managed boolean)
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
    exists (select 1 from public.upgrade_requests r where r.home_id = p_home_id and r.status = 'pending'),
    -- Plateforme en service et logement sans passerelle à lui.
    exists (select 1 from public.platform_devices)
      and not exists (select 1 from public.integrations i
                       where i.home_id = p_home_id and coalesce(i.external_reference, '') <> 'solea-platform');
end $$;
revoke execute on function public.get_home_plan(uuid) from public, anon;
grant execute on function public.get_home_plan(uuid) to authenticated;
