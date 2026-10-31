-- =============================================================================
-- Solea Smart Intercom & Video Security — phase A : sites, caméras ONVIF / RTSP, vidéo WebRTC
--
--   sites, site_entrances, site_members : villa ou immeuble (résidence, bâtiment, entrées),
--     gestionnaire et agent de sécurité. Une villa peut rester sans site.
--   homes.site_id / unit_label : logement rattaché à un immeuble (« Bât. B · Apt 12 »).
--   video_sources : caméras et visiophones déclarés pour un logement, lus par le boîtier
--     vidéo installé sur place (passerelle Solea + MediaMTX). Visibles des gestionnaires
--     du logement seulement (adresse IP, diagnostic).
--   video_source_secrets : identifiants des appareils. Aucune policy : jamais lisibles par
--     l'application, seulement par le boîtier (service_role).
--   video_scans : recherche ONVIF sur le réseau local, demandée depuis l'application.
--   video_sessions : signalisation WebRTC. L'application dépose son offre SDP, le boîtier
--     répond avec celle de MediaMTX. Aucun port n'est ouvert chez le client et l'adresse
--     RTSP ne quitte jamais le boîtier.
--   media_gateways : état du boîtier vidéo et serveurs STUN/TURN (identifiants TURN
--     temporaires) pour les membres du logement.
--
-- Les parties communes d'un immeuble (entrée, parking) se déclarent dans un logement
-- « Parties communes » du site ; le routage des appels vers chaque appartement viendra
-- avec la phase B (SIP).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Sites : villa ou immeuble
-- -----------------------------------------------------------------------------
do $$ begin
  create type public.site_kind as enum ('villa', 'building');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.site_role as enum ('manager', 'security', 'installer');
exception when duplicate_object then null; end $$;

create table if not exists public.sites (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(btrim(name)) between 1 and 80),
  kind        public.site_kind not null default 'building',
  address     text check (address is null or length(address) <= 200),
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

create table if not exists public.site_entrances (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.sites (id) on delete cascade,
  name        text not null check (length(btrim(name)) between 1 and 60),
  kind        text not null default 'pedestrian' check (kind in ('pedestrian', 'vehicle', 'service', 'other')),
  created_at  timestamptz not null default now()
);
create index if not exists site_entrances_site_idx on public.site_entrances (site_id);

create table if not exists public.site_members (
  site_id     uuid not null references public.sites (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        public.site_role not null,
  created_at  timestamptz not null default now(),
  primary key (site_id, user_id)
);

alter table public.homes
  add column if not exists site_id uuid references public.sites (id) on delete set null,
  add column if not exists unit_label text check (unit_label is null or length(unit_label) <= 40);
create index if not exists homes_site_idx on public.homes (site_id);

create or replace function public.site_role_of(p_site_id uuid)
returns public.site_role language sql stable security definer set search_path = '' as $$
  select m.role from public.site_members m where m.site_id = p_site_id and m.user_id = auth.uid()
$$;

create or replace function public.can_manage_site(p_site_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_platform_admin() or coalesce(public.site_role_of(p_site_id) = 'manager', false)
$$;

-- Voir un site : exploitant, personnel du site, ou membre d'un logement du site.
create or replace function public.can_view_site(p_site_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_platform_admin()
      or public.site_role_of(p_site_id) is not null
      or exists (select 1 from public.homes h where h.site_id = p_site_id and public.is_home_member(h.id))
$$;

revoke execute on function public.site_role_of(uuid) from public, anon;
revoke execute on function public.can_manage_site(uuid) from public, anon;
revoke execute on function public.can_view_site(uuid) from public, anon;
grant execute on function public.site_role_of(uuid) to authenticated;
grant execute on function public.can_manage_site(uuid) to authenticated;
grant execute on function public.can_view_site(uuid) to authenticated;

alter table public.sites enable row level security;
alter table public.site_entrances enable row level security;
alter table public.site_members enable row level security;

drop policy if exists sites_select on public.sites;
create policy sites_select on public.sites for select to authenticated using (public.can_view_site(id));
drop policy if exists site_entrances_select on public.site_entrances;
create policy site_entrances_select on public.site_entrances for select to authenticated using (public.can_view_site(site_id));
-- Le personnel du site se voit entre lui ; les résidents ne voient pas la liste du personnel.
drop policy if exists site_members_select on public.site_members;
create policy site_members_select on public.site_members for select to authenticated
  using (public.is_platform_admin() or public.site_role_of(site_id) is not null);
-- Écritures : uniquement par les fonctions ci-dessous.
revoke insert, update, delete on public.sites, public.site_entrances, public.site_members from anon, authenticated;

-- Le rattachement d'un logement à un site passe par set_home_site (un propriétaire ne peut pas
-- s'inviter seul dans un immeuble).
create or replace function public.trg_homes_site_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.site_id is distinct from old.site_id or new.unit_label is distinct from old.unit_label then
    if auth.uid() is not null and current_setting('solea.site_change', true) is distinct from 'on' then
      raise exception 'SITE_PROTEGE : utilisez set_home_site' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists homes_site_guard on public.homes;
create trigger homes_site_guard before update of site_id, unit_label on public.homes
  for each row execute function public.trg_homes_site_guard();

create or replace function public.create_site(p_name text, p_kind public.site_kind default 'building', p_address text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Réservé à l''exploitant Solea' using errcode = '42501';
  end if;
  insert into public.sites (name, kind, address, created_by)
  values (btrim(p_name), p_kind, nullif(btrim(coalesce(p_address, '')), ''), auth.uid())
  returning id into v_id;
  insert into public.site_members (site_id, user_id, role) values (v_id, auth.uid(), 'manager');
  return v_id;
end $$;

create or replace function public.add_site_entrance(p_site_id uuid, p_name text, p_kind text default 'pedestrian')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.can_manage_site(p_site_id) then
    raise exception 'Réservé au gestionnaire du site' using errcode = '42501';
  end if;
  insert into public.site_entrances (site_id, name, kind) values (p_site_id, btrim(p_name), p_kind) returning id into v_id;
  return v_id;
end $$;

-- Ajoute ou retire (p_role null) un membre du personnel d'un site.
create or replace function public.set_site_member(p_site_id uuid, p_user_id uuid, p_role public.site_role)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_manage_site(p_site_id) then
    raise exception 'Réservé au gestionnaire du site' using errcode = '42501';
  end if;
  if p_role is null then
    if p_user_id = auth.uid() and not public.is_platform_admin() then
      raise exception 'Un gestionnaire ne peut pas se retirer lui-même' using errcode = '42501';
    end if;
    delete from public.site_members where site_id = p_site_id and user_id = p_user_id;
  else
    insert into public.site_members (site_id, user_id, role) values (p_site_id, p_user_id, p_role)
    on conflict (site_id, user_id) do update set role = excluded.role;
  end if;
end $$;

-- Rattache un logement à un site (ou le détache avec p_site_id null).
create or replace function public.set_home_site(p_home_id uuid, p_site_id uuid, p_unit_label text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_current uuid;
begin
  select site_id into v_current from public.homes where id = p_home_id;
  if not found then raise exception 'Logement introuvable' using errcode = 'P0002'; end if;
  if (p_site_id is not null and not public.can_manage_site(p_site_id))
     or (v_current is not null and not public.can_manage_site(v_current))
     or (p_site_id is null and v_current is null and not public.is_platform_admin()) then
    raise exception 'Réservé au gestionnaire du site' using errcode = '42501';
  end if;
  perform set_config('solea.site_change', 'on', true);
  update public.homes
     set site_id = p_site_id,
         unit_label = case when p_site_id is null then null else nullif(btrim(coalesce(p_unit_label, '')), '') end
   where id = p_home_id;
  perform set_config('solea.site_change', 'off', true);
end $$;

revoke execute on function public.create_site(text, public.site_kind, text) from public, anon;
revoke execute on function public.add_site_entrance(uuid, text, text) from public, anon;
revoke execute on function public.set_site_member(uuid, uuid, public.site_role) from public, anon;
revoke execute on function public.set_home_site(uuid, uuid, text) from public, anon;
grant execute on function public.create_site(text, public.site_kind, text) to authenticated;
grant execute on function public.add_site_entrance(uuid, text, text) to authenticated;
grant execute on function public.set_site_member(uuid, uuid, public.site_role) to authenticated;
grant execute on function public.set_home_site(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Équipements vidéo (UDI)
-- -----------------------------------------------------------------------------
create table if not exists public.video_sources (
  id                     uuid primary key default gen_random_uuid(),
  home_id                uuid not null references public.homes (id) on delete cascade,
  device_id              uuid references public.devices (id) on delete set null,
  entrance_id            uuid references public.site_entrances (id) on delete set null,
  name                   text not null check (length(btrim(name)) between 1 and 60),
  category               text not null default 'camera' check (category in ('camera', 'intercom', 'access', 'monitor', 'sensor')),
  driver                 text not null check (driver in ('onvif', 'rtsp')),
  host                   text check (host is null or host ~ '^[A-Za-z0-9.:-]{1,253}$'),
  port                   integer check (port is null or port between 1 and 65535),
  -- Jamais d'identifiants dans les adresses : ils vont dans video_source_secrets.
  rtsp_url               text check (rtsp_url is null or (rtsp_url ~ '^rtsps?://' and rtsp_url !~ '^rtsps?://[^/]*@' and length(rtsp_url) <= 500)),
  rtsp_sub_url           text check (rtsp_sub_url is null or (rtsp_sub_url ~ '^rtsps?://' and rtsp_sub_url !~ '^rtsps?://[^/]*@' and length(rtsp_sub_url) <= 500)),
  snapshot_url           text check (snapshot_url is null or (snapshot_url ~ '^https?://' and snapshot_url !~ '^https?://[^/]*@' and length(snapshot_url) <= 500)),
  manufacturer           text check (manufacturer is null or length(manufacturer) <= 80),
  model                  text check (model is null or length(model) <= 80),
  firmware               text check (firmware is null or length(firmware) <= 80),
  location               text check (location is null or length(location) <= 80),
  enabled                boolean not null default true,
  status                 text not null default 'pending' check (status in ('pending', 'connecting', 'online', 'offline', 'auth_error', 'error')),
  last_error             text,
  capabilities           jsonb not null default '{}'::jsonb,
  diagnostic             jsonb,
  diagnosed_at           timestamptz,
  test_requested_at      timestamptz,
  credentials_updated_at timestamptz,
  last_seen_at           timestamptz,
  created_by             uuid references auth.users (id) on delete set null default auth.uid(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check ((driver = 'onvif' and host is not null) or (driver = 'rtsp' and rtsp_url is not null))
);
create index if not exists video_sources_home_idx on public.video_sources (home_id);
drop trigger if exists video_sources_updated_at on public.video_sources;
create trigger video_sources_updated_at before update on public.video_sources
  for each row execute function public.set_updated_at();

create table if not exists public.video_source_secrets (
  source_id   uuid primary key references public.video_sources (id) on delete cascade,
  username    text check (username is null or length(username) <= 100),
  password    text check (password is null or length(password) <= 200),
  updated_at  timestamptz not null default now()
);

alter table public.video_sources enable row level security;
alter table public.video_source_secrets enable row level security;
revoke all on public.video_source_secrets from anon, authenticated;
revoke insert, update, delete on public.video_sources from anon, authenticated;

-- Détails techniques (adresse IP, diagnostic) : propriétaire, administrateur et installateur du logement.
drop policy if exists video_sources_select on public.video_sources;
create policy video_sources_select on public.video_sources for select to authenticated
  using (public.home_role_of(home_id) in ('owner', 'admin', 'installer'));

create or replace function public.can_manage_video(p_home_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.home_role_of(p_home_id) in ('owner', 'admin', 'installer'), false)
$$;
revoke execute on function public.can_manage_video(uuid) from public, anon;
grant execute on function public.can_manage_video(uuid) to authenticated;

create or replace function public.add_video_source(
  p_home_id      uuid,
  p_name         text,
  p_driver       text,
  p_category     text default 'camera',
  p_host         text default null,
  p_port         integer default null,
  p_rtsp_url     text default null,
  p_rtsp_sub_url text default null,
  p_snapshot_url text default null,
  p_username     text default null,
  p_password     text default null,
  p_manufacturer text default null,
  p_model        text default null,
  p_location     text default null,
  p_entrance_id  uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.can_manage_video(p_home_id) then
    raise exception 'Réservé au propriétaire, à l''administrateur ou à l''installateur' using errcode = '42501';
  end if;
  if coalesce(p_rtsp_url, '') ~ '^rtsps?://[^/]*@' or coalesce(p_rtsp_sub_url, '') ~ '^rtsps?://[^/]*@'
     or coalesce(p_snapshot_url, '') ~ '^https?://[^/]*@' then
    raise exception 'IDENTIFIANTS_DANS_URL : saisissez l''identifiant et le mot de passe à part' using errcode = '22023';
  end if;
  if p_entrance_id is not null and not exists (
    select 1 from public.site_entrances e join public.homes h on h.site_id = e.site_id
    where e.id = p_entrance_id and h.id = p_home_id
  ) then
    raise exception 'Cette entrée n''appartient pas au site du logement' using errcode = '22023';
  end if;
  insert into public.video_sources (home_id, name, category, driver, host, port, rtsp_url, rtsp_sub_url, snapshot_url,
                                    manufacturer, model, location, entrance_id, credentials_updated_at)
  values (p_home_id, btrim(p_name), p_category, p_driver, nullif(btrim(coalesce(p_host, '')), ''),
          case when p_driver = 'onvif' then coalesce(p_port, 80) else p_port end,
          nullif(btrim(coalesce(p_rtsp_url, '')), ''), nullif(btrim(coalesce(p_rtsp_sub_url, '')), ''),
          nullif(btrim(coalesce(p_snapshot_url, '')), ''), nullif(btrim(coalesce(p_manufacturer, '')), ''),
          nullif(btrim(coalesce(p_model, '')), ''), nullif(btrim(coalesce(p_location, '')), ''), p_entrance_id, now())
  returning id into v_id;
  insert into public.video_source_secrets (source_id, username, password)
  values (v_id, nullif(p_username, ''), nullif(p_password, ''));
  return v_id;
end $$;

create or replace function public.set_video_source_credentials(p_source_id uuid, p_username text, p_password text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_home uuid;
begin
  select home_id into v_home from public.video_sources where id = p_source_id;
  if not found or not public.can_manage_video(v_home) then
    raise exception 'Équipement introuvable' using errcode = '42501';
  end if;
  insert into public.video_source_secrets (source_id, username, password, updated_at)
  values (p_source_id, nullif(p_username, ''), nullif(p_password, ''), now())
  on conflict (source_id) do update set username = excluded.username, password = excluded.password, updated_at = now();
  update public.video_sources set credentials_updated_at = now(), test_requested_at = now(), status = 'pending'
   where id = p_source_id;
end $$;

-- Relance le diagnostic (le boîtier le voit en temps réel).
create or replace function public.request_video_source_test(p_source_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_home uuid;
begin
  select home_id into v_home from public.video_sources where id = p_source_id;
  if not found or not public.can_manage_video(v_home) then
    raise exception 'Équipement introuvable' using errcode = '42501';
  end if;
  update public.video_sources set test_requested_at = now() where id = p_source_id;
end $$;

-- Supprime l'équipement et l'appareil Solea qui le représente.
create or replace function public.delete_video_source(p_source_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_home uuid; v_device uuid;
begin
  select home_id, device_id into v_home, v_device from public.video_sources where id = p_source_id;
  if not found or not public.can_manage_video(v_home) then
    raise exception 'Équipement introuvable' using errcode = '42501';
  end if;
  delete from public.video_sources where id = p_source_id;
  if v_device is not null then delete from public.devices where id = v_device and home_id = v_home; end if;
end $$;

revoke execute on function public.add_video_source(uuid, text, text, text, text, integer, text, text, text, text, text, text, text, text, uuid) from public, anon;
revoke execute on function public.set_video_source_credentials(uuid, text, text) from public, anon;
revoke execute on function public.request_video_source_test(uuid) from public, anon;
revoke execute on function public.delete_video_source(uuid) from public, anon;
grant execute on function public.add_video_source(uuid, text, text, text, text, integer, text, text, text, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.set_video_source_credentials(uuid, text, text) to authenticated;
grant execute on function public.request_video_source_test(uuid) to authenticated;
grant execute on function public.delete_video_source(uuid) to authenticated;

-- Lien équipement → appareil Solea, posé quand le boîtier crée l'appareil (« udi:<id> »).
create or replace function public.trg_link_video_device()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.external_id like 'udi:%' then
    update public.video_sources s
       set device_id = new.device_id
      from public.devices d
     where s.id::text = substr(new.external_id, 5)
       and d.id = new.device_id
       and d.home_id = s.home_id;
  end if;
  return new;
end $$;
drop trigger if exists device_bindings_link_video on public.device_bindings;
create trigger device_bindings_link_video after insert on public.device_bindings
  for each row execute function public.trg_link_video_device();

-- -----------------------------------------------------------------------------
-- Recherche sur le réseau local
-- -----------------------------------------------------------------------------
create table if not exists public.video_scans (
  id            uuid primary key default gen_random_uuid(),
  home_id       uuid not null references public.homes (id) on delete cascade,
  requested_by  uuid references auth.users (id) on delete set null default auth.uid(),
  status        text not null default 'pending' check (status in ('pending', 'running', 'done', 'failed')),
  results       jsonb not null default '[]'::jsonb,
  error         text,
  created_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index if not exists video_scans_home_idx on public.video_scans (home_id, created_at desc);
alter table public.video_scans enable row level security;
revoke insert, update, delete on public.video_scans from anon, authenticated;
drop policy if exists video_scans_select on public.video_scans;
create policy video_scans_select on public.video_scans for select to authenticated
  using (public.can_manage_video(home_id));

create or replace function public.request_video_scan(p_home_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.can_manage_video(p_home_id) then
    raise exception 'Réservé au propriétaire, à l''administrateur ou à l''installateur' using errcode = '42501';
  end if;
  -- Une recherche à la fois : on rend celle qui est déjà en cours.
  select id into v_id from public.video_scans
   where home_id = p_home_id and status in ('pending', 'running') and created_at > now() - interval '2 minutes'
   order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  delete from public.video_scans where home_id = p_home_id and created_at < now() - interval '7 days';
  insert into public.video_scans (home_id) values (p_home_id) returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.request_video_scan(uuid) from public, anon;
grant execute on function public.request_video_scan(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Vidéo en direct : signalisation WebRTC (WHEP relayé par le boîtier)
-- -----------------------------------------------------------------------------
create table if not exists public.video_sessions (
  id           uuid primary key default gen_random_uuid(),
  home_id      uuid not null references public.homes (id) on delete cascade,
  device_id    uuid not null references public.devices (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade default auth.uid(),
  quality      text not null default 'main' check (quality in ('main', 'sub')),
  offer        text not null check (length(offer) between 10 and 20000),
  answer       text check (answer is null or length(answer) <= 20000),
  status       text not null default 'offer' check (status in ('offer', 'answered', 'failed', 'closed')),
  error        text,
  created_at   timestamptz not null default now(),
  answered_at  timestamptz
);
create index if not exists video_sessions_home_idx on public.video_sessions (home_id, status, created_at desc);
alter table public.video_sessions enable row level security;

-- Un membre ne peut regarder qu'un appareil auquel il a accès (même règle que les images).
drop policy if exists video_sessions_insert on public.video_sessions;
create policy video_sessions_insert on public.video_sessions for insert to authenticated
  with check (
    user_id = auth.uid() and status = 'offer' and answer is null
    and public.can_use_device(device_id)
    and exists (select 1 from public.devices d where d.id = device_id and d.home_id = video_sessions.home_id)
  );
drop policy if exists video_sessions_select on public.video_sessions;
create policy video_sessions_select on public.video_sessions for select to authenticated
  using (user_id = auth.uid());
-- L'application peut seulement fermer sa propre session.
drop policy if exists video_sessions_update on public.video_sessions;
create policy video_sessions_update on public.video_sessions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status = 'closed');
revoke update on public.video_sessions from anon, authenticated;
grant update (status) on public.video_sessions to authenticated;
revoke delete on public.video_sessions from anon, authenticated;

-- Garde-fous : 10 demandes par minute et par membre, purge des sessions de plus d'un jour.
create or replace function public.trg_video_session_limits()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and (
    select count(*) from public.video_sessions where user_id = auth.uid() and created_at > now() - interval '1 minute'
  ) >= 10 then
    raise exception 'TROP_DE_DEMANDES_VIDEO : réessayez dans une minute' using errcode = '54000';
  end if;
  delete from public.video_sessions where home_id = new.home_id and created_at < now() - interval '1 day';
  return new;
end $$;
drop trigger if exists video_sessions_limits on public.video_sessions;
create trigger video_sessions_limits before insert on public.video_sessions
  for each row execute function public.trg_video_session_limits();

-- -----------------------------------------------------------------------------
-- Boîtier vidéo du logement
-- -----------------------------------------------------------------------------
create table if not exists public.media_gateways (
  home_id       uuid primary key references public.homes (id) on delete cascade,
  ice_servers   jsonb not null default '[]'::jsonb,
  relay_ok      boolean not null default false,
  discovery     boolean not null default false,
  version       text,
  last_seen_at  timestamptz
);
alter table public.media_gateways enable row level security;
revoke insert, update, delete on public.media_gateways from anon, authenticated;
drop policy if exists media_gateways_select on public.media_gateways;
create policy media_gateways_select on public.media_gateways for select to authenticated
  using (public.is_home_member(home_id));

-- -----------------------------------------------------------------------------
-- Temps réel : le boîtier réagit aux demandes, l'application suit les réponses.
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['video_sources', 'video_scans', 'video_sessions', 'media_gateways'] loop
      if not exists (
        select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
