-- =============================================================================
-- Solea : organisation des appareils, suppression individuelle et ajout par QR code
--
--   device_layouts      ordre d'affichage propre à chaque utilisateur et à chaque logement
--                       (favoris, liste des appareils, chaque pièce, scènes).
--   devices.removed_at  « Retirer de ma résidence » : l'appareil disparaît de l'application,
--                       sa liaison avec la passerelle est gardée (rien n'est recréé) et il
--                       peut être remis. L'historique (event_logs) est conservé.
--   device_exclusions   « Dissocier définitivement » : l'appareil est supprimé (capacités,
--                       commandes, clé Bluetooth, codes) et la passerelle ne le recrée plus.
--   devices.serial_number / qr_code_type : identité lue sur le QR code (doublons).
--   device_qr_scans     QR codes lus (sans secret) : reconnus, non pris en charge, signalés
--                       à l'administrateur Solea.
--
-- Permissions : l'ordre est personnel (chaque membre range son écran). Retirer ou dissocier
-- est réservé au propriétaire et à l'administrateur du logement ; un appareil fourni par
-- l'installateur Solea (platform_devices) ne peut être dissocié que par l'exploitant.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Appareils : retrait réversible et identité lue sur le QR code
-- -----------------------------------------------------------------------------
alter table public.devices
  add column if not exists removed_at    timestamptz,
  add column if not exists removed_by    uuid references public.profiles (id) on delete set null,
  add column if not exists serial_number text check (serial_number is null or length(serial_number) between 3 and 80),
  add column if not exists qr_code_type  text check (qr_code_type is null or qr_code_type ~ '^[a-z_]{2,30}$');
create index if not exists devices_home_serial_idx on public.devices (home_id, upper(serial_number)) where serial_number is not null;

grant update (serial_number, qr_code_type) on public.devices to authenticated;

-- Un appareil retiré n'est plus visible ni commandable par les membres (lecture, capacités,
-- commandes passent toutes par cette fonction). La passerelle (service_role) n'est pas concernée.
create or replace function public.can_use_device(p_device_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.devices d
    join public.home_members m on m.home_id = d.home_id and m.user_id = auth.uid()
    where d.id = p_device_id
      and d.removed_at is null
      and (m.expires_at is null or m.expires_at > now())
      and (
        m.role in ('owner', 'admin', 'installer')
        or not (m.permissions ? 'devices')
        or m.permissions -> 'devices' ? p_device_id::text
      )
  )
$$;

-- Les appareils retirés ne comptent plus dans la limite de l'offre.
create or replace function public.check_device_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_limit integer;
begin
  -- Deux ajouts simultanés dans le même logement ne doivent pas dépasser la limite.
  perform pg_advisory_xact_lock(hashtext('device_limit:' || new.home_id::text));
  v_limit := public.home_device_limit(new.home_id);
  if (select count(*) from public.devices d where d.home_id = new.home_id and d.removed_at is null) >= v_limit then
    raise exception 'LIMITE_APPAREILS : % appareils au plus pour ce logement', v_limit
      using errcode = 'P0001', hint = 'device_limit';
  end if;
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Ordre d'affichage par utilisateur et par logement
--   section : 'favorites', 'devices', 'room:<uuid>', 'room:none', 'scenes'
-- -----------------------------------------------------------------------------
create table if not exists public.device_layouts (
  user_id    uuid not null references auth.users (id) on delete cascade,
  home_id    uuid not null references public.homes (id) on delete cascade,
  section    text not null check (section ~ '^(favorites|devices|scenes|room:(none|[0-9a-f-]{36}))$'),
  item_ids   uuid[] not null default '{}' check (cardinality(item_ids) <= 500),
  updated_at timestamptz not null default now(),
  primary key (user_id, home_id, section)
);
alter table public.device_layouts enable row level security;
revoke all on public.device_layouts from anon, authenticated;
grant select, insert, update, delete on public.device_layouts to authenticated;

drop policy if exists device_layouts_own on public.device_layouts;
create policy device_layouts_own on public.device_layouts for all to authenticated
  using (user_id = auth.uid() and public.is_home_member(home_id))
  with check (user_id = auth.uid() and public.is_home_member(home_id));

drop trigger if exists device_layouts_updated_at on public.device_layouts;
create trigger device_layouts_updated_at before update on public.device_layouts
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Appareils dissociés : la passerelle ne les recrée pas
-- -----------------------------------------------------------------------------
create table if not exists public.device_exclusions (
  id             uuid primary key default gen_random_uuid(),
  home_id        uuid not null references public.homes (id) on delete cascade,
  integration_id uuid not null references public.integrations (id) on delete cascade,
  external_id    text not null,
  device_name    text not null,
  vendor         text,
  model          text,
  excluded_by    uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (integration_id, external_id)
);
create index if not exists device_exclusions_home_idx on public.device_exclusions (home_id);
alter table public.device_exclusions enable row level security;
revoke all on public.device_exclusions from anon, authenticated;
-- external_id n'est jamais lu par l'application.
grant select (id, home_id, device_name, vendor, model, created_at) on public.device_exclusions to authenticated;

drop policy if exists device_exclusions_select on public.device_exclusions;
create policy device_exclusions_select on public.device_exclusions for select to authenticated
  using (public.is_home_manager(home_id));

-- Filet de sécurité pour les passerelles qui ne lisent pas encore device_exclusions : un
-- appareil dissocié recréé par une ancienne passerelle est aussitôt retiré.
create or replace function public.trg_binding_excluded()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.device_exclusions x
              where x.integration_id = new.integration_id and x.external_id = new.external_id) then
    update public.devices set removed_at = now(), is_pinned = false where id = new.device_id;
  end if;
  return new;
end $$;
drop trigger if exists device_bindings_excluded on public.device_bindings;
create trigger device_bindings_excluded after insert on public.device_bindings
  for each row execute function public.trg_binding_excluded();

-- -----------------------------------------------------------------------------
-- Suppression d'un appareil
--   p_mode 'home'   : retirer de ma résidence (réversible)
--   p_mode 'unlink' : dissocier définitivement
-- Renvoie les nettoyages faits : scènes, zones climat, automatisations mises en pause.
-- -----------------------------------------------------------------------------
create or replace function public.remove_device(p_device_id uuid, p_mode text default 'home')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
  v_external text;
  v_integration uuid;
  v_scenes integer := 0;
  v_zones integer := 0;
  v_automations integer := 0;
begin
  if p_mode not in ('home', 'unlink') then
    raise exception 'Mode de suppression inconnu' using errcode = '22023';
  end if;
  select * into d from public.devices where id = p_device_id for update;
  if not found or not public.is_home_manager(d.home_id) then
    raise exception 'Réservé au propriétaire ou à l''administrateur du logement' using errcode = '42501';
  end if;
  select b.external_id, b.integration_id into v_external, v_integration
    from public.device_bindings b where b.device_id = d.id;

  if p_mode = 'unlink' and v_external is not null and not public.is_platform_admin() and exists (
    select 1 from public.platform_devices p where p.external_id = v_external and p.home_id = d.home_id
  ) then
    raise exception 'Appareil fourni par l''installateur Solea : seul l''exploitant peut le dissocier'
      using errcode = '42501', hint = 'platform_device';
  end if;

  -- Associations : scènes, zones climat, ordre d'affichage, favoris.
  with x as (delete from public.scene_actions where device_id = d.id returning 1)
  select count(*) into v_scenes from x;

  with x as (
    update public.climate_zones z
       set devices = coalesce((select jsonb_agg(e) from jsonb_array_elements(z.devices) e where e <> to_jsonb(d.id::text)), '[]'::jsonb)
     where z.home_id = d.home_id and z.devices ? d.id::text
    returning 1)
  select count(*) into v_zones from x;

  -- Automatisations qui citent l'appareil : mises en pause (à corriger par l'utilisateur).
  with x as (
    update public.automations a set enabled = false
     where a.home_id = d.home_id and a.enabled
       and (a.trigger::text || a.conditions::text || a.actions::text) like '%' || d.id::text || '%'
    returning 1)
  select count(*) into v_automations from x;

  update public.device_layouts l set item_ids = array_remove(l.item_ids, d.id)
   where l.home_id = d.home_id and d.id = any (l.item_ids);

  if p_mode = 'home' then
    update public.devices set removed_at = now(), removed_by = auth.uid(), is_pinned = false where id = d.id;
    perform public.log_event(d.home_id, 'device_removed', d.id, null, 'home', jsonb_build_object('name', d.name));
  else
    if v_external is not null then
      insert into public.device_exclusions (home_id, integration_id, external_id, device_name, vendor, model, excluded_by)
      values (d.home_id, v_integration, v_external, d.name, d.vendor, d.model, auth.uid())
      on conflict (integration_id, external_id) do update
        set device_name = excluded.device_name, excluded_by = excluded.excluded_by, created_at = now();
    end if;
    -- Journal gardé (device_id passe à null) ; clé Bluetooth, codes, capacités supprimés en cascade.
    perform public.log_event(d.home_id, 'device_unlinked', null, null, 'unlink',
      jsonb_build_object('name', d.name, 'vendor', d.vendor, 'model', d.model));
    delete from public.devices where id = d.id;
  end if;

  return jsonb_build_object('scenes', v_scenes, 'climate_zones', v_zones, 'automations_paused', v_automations);
end $$;
revoke execute on function public.remove_device(uuid, text) from public, anon;
grant execute on function public.remove_device(uuid, text) to authenticated;

-- Appareils retirés du logement (pour les remettre).
create or replace function public.list_removed_devices(p_home_id uuid)
returns table (id uuid, name text, vendor text, model text, protocol text, removed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select d.id, d.name, d.vendor, d.model, d.protocol::text, d.removed_at
    from public.devices d
   where d.home_id = p_home_id and d.removed_at is not null and public.is_home_manager(p_home_id)
   order by d.removed_at desc
$$;
revoke execute on function public.list_removed_devices(uuid) from public, anon;
grant execute on function public.list_removed_devices(uuid) to authenticated;

create or replace function public.restore_device(p_device_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare d public.devices;
begin
  select * into d from public.devices where id = p_device_id for update;
  if not found or not public.is_home_manager(d.home_id) then
    raise exception 'Réservé au propriétaire ou à l''administrateur du logement' using errcode = '42501';
  end if;
  if d.removed_at is null then return; end if;
  -- Le retour compte de nouveau dans la limite de l'offre.
  perform pg_advisory_xact_lock(hashtext('device_limit:' || d.home_id::text));
  if (select count(*) from public.devices x where x.home_id = d.home_id and x.removed_at is null)
       >= public.home_device_limit(d.home_id) then
    raise exception 'LIMITE_APPAREILS' using errcode = 'P0001', hint = 'device_limit';
  end if;
  update public.devices set removed_at = null, removed_by = null where id = d.id;
  perform public.log_event(d.home_id, 'device_restored', d.id, null, 'ok', jsonb_build_object('name', d.name));
end $$;
revoke execute on function public.restore_device(uuid) from public, anon;
grant execute on function public.restore_device(uuid) to authenticated;

-- Autorise de nouveau un appareil dissocié : la passerelle le recrée au prochain inventaire.
create or replace function public.allow_excluded_device(p_exclusion_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare x public.device_exclusions;
begin
  select * into x from public.device_exclusions where id = p_exclusion_id;
  if not found or not public.is_home_manager(x.home_id) then
    raise exception 'Réservé au propriétaire ou à l''administrateur du logement' using errcode = '42501';
  end if;
  delete from public.device_exclusions where id = x.id;
  perform public.log_event(x.home_id, 'device_allowed', null, null, 'ok', jsonb_build_object('name', x.device_name));
end $$;
revoke execute on function public.allow_excluded_device(uuid) from public, anon;
grant execute on function public.allow_excluded_device(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- QR codes lus (jamais de mot de passe ni de code de sécurité : masqués par l'application,
-- et refusés ici par précaution)
-- -----------------------------------------------------------------------------
create table if not exists public.device_qr_scans (
  id                 uuid primary key default gen_random_uuid(),
  home_id            uuid not null references public.homes (id) on delete cascade,
  user_id            uuid references auth.users (id) on delete set null default auth.uid(),
  raw_payload        text not null check (length(raw_payload) <= 2000),
  qr_code_type       text not null check (qr_code_type ~ '^[a-z_]{2,30}$'),
  parser_type        text not null check (parser_type ~ '^[a-z_]{2,30}$'),
  manufacturer       text check (manufacturer is null or length(manufacturer) <= 80),
  product_id         text check (product_id is null or length(product_id) <= 80),
  model              text check (model is null or length(model) <= 80),
  serial_number      text check (serial_number is null or length(serial_number) <= 80),
  protocol           text check (protocol is null or length(protocol) <= 30),
  recognition_status text not null check (recognition_status in ('recognized', 'unsupported', 'unknown', 'duplicate', 'added')),
  reported_at        timestamptz,
  device_id          uuid references public.devices (id) on delete set null,
  created_at         timestamptz not null default now(),
  -- Ceinture et bretelles : aucun secret en clair (P:, SC:, mot de passe…).
  check (raw_payload !~* '(^|[;,{&?])\s*(p|sc|pwd|pass|password|passwd|key|secret)\s*[:=]\s*[^*;,}&\s]')
);
create index if not exists device_qr_scans_home_idx on public.device_qr_scans (home_id, created_at desc);
create index if not exists device_qr_scans_reported_idx on public.device_qr_scans (reported_at desc) where reported_at is not null;
alter table public.device_qr_scans enable row level security;
revoke all on public.device_qr_scans from anon, authenticated;
grant select, insert on public.device_qr_scans to authenticated;
grant update (recognition_status, reported_at, device_id) on public.device_qr_scans to authenticated;

drop policy if exists device_qr_scans_insert on public.device_qr_scans;
create policy device_qr_scans_insert on public.device_qr_scans for insert to authenticated
  with check (user_id = auth.uid() and public.home_role_of(home_id) in ('owner', 'admin', 'installer'));
drop policy if exists device_qr_scans_select on public.device_qr_scans;
create policy device_qr_scans_select on public.device_qr_scans for select to authenticated
  using (user_id = auth.uid() or public.is_platform_admin());
drop policy if exists device_qr_scans_update on public.device_qr_scans;
create policy device_qr_scans_update on public.device_qr_scans for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
