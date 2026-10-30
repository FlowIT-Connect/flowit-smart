-- =============================================================================
-- Solea — contrôle d'accès (serrures TTLock et autres appareils sensibles)
--
-- Les fonctions de sécurité physique restent bloquées par défaut (§9). Le propriétaire
-- de la maison peut les activer appareil par appareil (« validation dédiée ») :
--   devices.security_validated_at / _by : posés par set_device_security(), jamais par
--                                         l'application directement ni par la passerelle.
-- Une fois l'appareil validé, seuls le propriétaire et les administrateurs peuvent le
-- commander, et seulement à la main : scènes et automatisations restent refusées.
--
--   access_codes : codes d'accès créés par la passerelle (code au clavier de la serrure),
--                  lisibles par le propriétaire et les administrateurs seulement.
-- =============================================================================

alter table public.devices
  add column if not exists security_validated_at timestamptz,
  add column if not exists security_validated_by uuid references public.profiles (id) on delete set null;

-- Validation dédiée d'un appareil sensible : propriétaire uniquement, journalisée.
create or replace function public.set_device_security(p_device_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
begin
  select * into d from public.devices where id = p_device_id;
  if not found or public.home_role_of(d.home_id) is distinct from 'owner' then
    raise exception 'Réservé au propriétaire de la maison';
  end if;
  -- Seuls les contrôles d'accès pris en charge (codes au clavier TTLock) ; les autres
  -- appareils sensibles (serrures Home Assistant, alarmes…) restent bloqués.
  if not d.is_sensitive or not exists (
    select 1 from public.device_capabilities c
    where c.device_id = d.id and c.metadata ->> 'kind' = 'access_code'
  ) then
    raise exception 'Cet appareil ne peut pas être activé depuis Solea';
  end if;
  update public.devices
    set security_validated_at = case when p_enabled then now() end,
        security_validated_by = case when p_enabled then auth.uid() end
    where id = d.id;
  perform public.log_event(d.home_id, 'config_changed', d.id, null,
    case when p_enabled then 'security_enabled' else 'security_disabled' end, '{}'::jsonb);
end $$;
revoke execute on function public.set_device_security(uuid, boolean) from public, anon;
grant execute on function public.set_device_security(uuid, boolean) to authenticated;

-- Commandes : un appareil sensible n'accepte que les demandes manuelles d'un
-- propriétaire ou administrateur, après validation dédiée.
create or replace function public.validate_device_command()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
begin
  select * into d from public.devices where id = new.device_id;
  if not found or d.home_id <> new.home_id then
    raise exception 'Appareil introuvable';
  end if;
  if d.is_sensitive then
    if d.security_validated_at is null then
      raise exception 'Commande bloquée : appareil sensible non validé';
    end if;
    if auth.role() is distinct from 'authenticated' or new.scene_run_id is not null or new.automation_id is not null then
      raise exception 'Commande bloquée : un appareil de sécurité se commande uniquement à la main';
    end if;
    if public.home_role_of(d.home_id) not in ('owner', 'admin') then
      raise exception 'Réservé au propriétaire ou à un administrateur';
    end if;
  end if;
  if not exists (
    select 1 from public.device_capabilities c
    where c.device_id = new.device_id and c.capability_key = new.capability_key and c.writable
  ) then
    raise exception 'Capacité non prise en charge par cet appareil';
  end if;
  if auth.role() = 'authenticated' then
    new.requested_by := auth.uid();
    new.status := 'pending';
    new.error := null;
    new.completed_at := null;
  end if;
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Codes d'accès (écrits par la passerelle, service_role)
-- -----------------------------------------------------------------------------
create table if not exists public.access_codes (
  id          uuid primary key default gen_random_uuid(),
  home_id     uuid not null references public.homes (id) on delete cascade,
  device_id   uuid not null references public.devices (id) on delete cascade,
  command_id  uuid unique references public.device_commands (id) on delete set null,
  kind        text not null check (kind in ('one_time', 'period', 'permanent')),
  name        text check (name is null or length(name) <= 40),
  code        text not null check (code ~ '^[0-9]{4,12}$'),
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists access_codes_device_idx on public.access_codes (device_id, created_at desc);

alter table public.access_codes enable row level security;
create policy access_codes_select on public.access_codes for select to authenticated
  using (public.is_home_manager(home_id) and public.can_use_device(device_id));
revoke insert, update, delete on public.access_codes from anon, authenticated;
