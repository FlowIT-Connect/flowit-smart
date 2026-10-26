-- =============================================================================
-- FlowIT Smart — schéma initial Supabase (MVP)
-- Source : Cahier des charges FlowIT Smart v1.0, §4 (rôles), §5 (exigences),
--          §7 (modèle de données), §9 (sécurité).
--
-- Principes :
--   * Identité gérée par Supabase Auth (auth.users) ; profil applicatif dans public.profiles.
--   * Isolation stricte par maison via RLS : aucune lecture/commande d'une maison étrangère,
--     même en modifiant un identifiant dans la requête (§5.2, §11).
--   * Les secrets d'intégration (Tuya, Home Assistant…) ne sont JAMAIS lisibles par le client :
--     table integration_secrets accessible uniquement au service_role (§5.3, §6.2, §9).
--   * Le client crée une commande "pending" ; seul le backend (Edge Function / API FlowIT,
--     service_role) la relaie au moteur Home Assistant et écrit le résultat réel (§5.4, §6.1).
--   * Le journal d'événements est en lecture seule pour les clients (§5.10).
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.home_role as enum ('owner', 'admin', 'member', 'installer');
create type public.device_protocol as enum ('wifi', 'tuya', 'zigbee', 'ble', 'mqtt', 'matter', 'other');
create type public.connection_source as enum ('local', 'gateway', 'cloud', 'ble_direct', 'mixed');
create type public.availability as enum ('available', 'unavailable', 'unknown');
create type public.command_status as enum ('pending', 'sent', 'confirmed', 'failed', 'timeout', 'rejected');
create type public.integration_provider as enum ('home_assistant', 'tuya', 'zigbee2mqtt', 'mqtt', 'ble', 'other');
create type public.integration_status as enum ('pending', 'connected', 'error', 'disabled');
create type public.failure_policy as enum ('continue', 'stop');

-- -----------------------------------------------------------------------------
-- Utilitaire updated_at
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Profils (User, §7)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  locale      text not null default 'fr' check (locale in ('fr', 'en', 'ar')),
  status      text not null default 'active' check (status in ('active', 'suspended', 'deleted')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Création automatique du profil à l'inscription
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Maisons et membres (Home, Membership, §5.2)
-- -----------------------------------------------------------------------------
create table public.homes (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles (id) on delete restrict,
  name       text not null check (length(trim(name)) between 1 and 100),
  timezone   text not null default 'Africa/Algiers',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index homes_owner_idx on public.homes (owner_id);
create trigger homes_updated_at before update on public.homes
  for each row execute function public.set_updated_at();

create table public.home_members (
  home_id     uuid not null references public.homes (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        public.home_role not null default 'member',
  -- Permissions fines optionnelles, ex. {"devices": ["<uuid>", ...], "can_manage_scenes": true}
  permissions jsonb not null default '{}'::jsonb,
  expires_at  timestamptz,           -- accès temporaire (installateur, §4)
  invited_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (home_id, user_id)     -- contrainte unique utilisateur/maison (§7)
);
create index home_members_user_idx on public.home_members (user_id);

-- Invitations par e-mail
create table public.home_invitations (
  id          uuid primary key default gen_random_uuid(),
  home_id     uuid not null references public.homes (id) on delete cascade,
  email       text not null,
  role        public.home_role not null default 'member' check (role <> 'owner'),
  token       text not null unique default encode(gen_random_bytes(24), 'hex'),
  invited_by  uuid not null references public.profiles (id) on delete cascade,
  expires_at  timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  created_at  timestamptz not null default now()
);
create index home_invitations_home_idx on public.home_invitations (home_id);

-- -----------------------------------------------------------------------------
-- Fonctions d'autorisation (security definer : évite la récursion RLS)
-- -----------------------------------------------------------------------------
create or replace function public.home_role_of(p_home_id uuid)
returns public.home_role
language sql stable security definer set search_path = '' as $$
  select m.role
  from public.home_members m
  where m.home_id = p_home_id
    and m.user_id = auth.uid()
    and (m.expires_at is null or m.expires_at > now())
$$;

create or replace function public.is_home_member(p_home_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.home_role_of(p_home_id) is not null
$$;

create or replace function public.is_home_manager(p_home_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.home_role_of(p_home_id) in ('owner', 'admin'), false)
$$;

-- Le propriétaire devient automatiquement membre "owner"
create or replace function public.handle_new_home()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.home_members (home_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end $$;

create trigger on_home_created after insert on public.homes
  for each row execute function public.handle_new_home();

-- Accepter une invitation (appelé par le client via rpc)
create or replace function public.accept_home_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  inv public.home_invitations;
begin
  select * into inv from public.home_invitations
  where token = p_token and accepted_at is null and expires_at > now()
  for update;
  if not found then
    raise exception 'Invitation invalide ou expirée';
  end if;
  if lower(inv.email) <> lower((select email from auth.users where id = auth.uid())) then
    raise exception 'Invitation invalide ou expirée';  -- message non révélateur (§5.1)
  end if;
  insert into public.home_members (home_id, user_id, role, invited_by)
  values (inv.home_id, auth.uid(), inv.role, inv.invited_by)
  on conflict (home_id, user_id) do nothing;
  update public.home_invitations set accepted_at = now() where id = inv.id;
  return inv.home_id;
end $$;

-- -----------------------------------------------------------------------------
-- Pièces (Room)
-- -----------------------------------------------------------------------------
create table public.rooms (
  id         uuid primary key default gen_random_uuid(),
  home_id    uuid not null references public.homes (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 100),
  icon       text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rooms_home_idx on public.rooms (home_id, sort_order);
create trigger rooms_updated_at before update on public.rooms
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Intégrations (Integration) — métadonnées visibles, secrets isolés
-- -----------------------------------------------------------------------------
create table public.integrations (
  id                 uuid primary key default gen_random_uuid(),
  home_id            uuid not null references public.homes (id) on delete cascade,
  provider           public.integration_provider not null,
  status             public.integration_status not null default 'pending',
  label              text,
  external_reference text,  -- référence non secrète (ex. id d'instance HA)
  last_sync_at       timestamptz,
  last_error         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index integrations_home_idx on public.integrations (home_id);
create trigger integrations_updated_at before update on public.integrations
  for each row execute function public.set_updated_at();

-- Secrets : aucune policy => inaccessibles à anon/authenticated. Service_role uniquement.
-- Recommandé : stocker la valeur dans Supabase Vault et ne garder ici que l'id du secret.
create table public.integration_secrets (
  integration_id  uuid primary key references public.integrations (id) on delete cascade,
  vault_secret_id uuid,          -- id dans vault.secrets
  rotated_at      timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Appareils et capacités (Device, Capability, §5.3)
-- -----------------------------------------------------------------------------
create table public.devices (
  id                uuid primary key default gen_random_uuid(),
  home_id           uuid not null references public.homes (id) on delete cascade,
  room_id           uuid references public.rooms (id) on delete set null,
  integration_id    uuid references public.integrations (id) on delete set null,
  name              text not null,
  vendor            text,
  model             text,
  protocol          public.device_protocol not null,
  connection_source public.connection_source not null default 'gateway',
  availability      public.availability not null default 'unknown',
  state             jsonb not null default '{}'::jsonb,  -- dernier état connu
  last_seen_at      timestamptz,
  is_pinned         boolean not null default false,
  is_hidden         boolean not null default false,
  is_sensitive      boolean not null default false,  -- serrures/sécurité : bloqué par défaut (§9)
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index devices_home_idx on public.devices (home_id);
create index devices_room_idx on public.devices (room_id);
create trigger devices_updated_at before update on public.devices
  for each row execute function public.set_updated_at();

-- La pièce d'un appareil doit appartenir à la même maison
create or replace function public.check_device_room()
returns trigger language plpgsql as $$
begin
  if new.room_id is not null and not exists (
    select 1 from public.rooms r where r.id = new.room_id and r.home_id = new.home_id
  ) then
    raise exception 'La pièce n''appartient pas à cette maison';
  end if;
  return new;
end $$;
create trigger devices_room_check before insert or update of room_id, home_id on public.devices
  for each row execute function public.check_device_room();

-- Un membre "member" peut être restreint à une liste d'appareils (permissions.devices)
create or replace function public.can_use_device(p_device_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.devices d
    join public.home_members m on m.home_id = d.home_id and m.user_id = auth.uid()
    where d.id = p_device_id
      and (m.expires_at is null or m.expires_at > now())
      and (
        m.role in ('owner', 'admin', 'installer')
        or not (m.permissions ? 'devices')
        or m.permissions -> 'devices' ? p_device_id::text
      )
  )
$$;

-- Liaison avec l'identifiant fournisseur (HA entity_id, Tuya devId, adresse IEEE Zigbee…).
-- Table séparée sans policy : jamais exposée au client, utilisée par le backend uniquement.
create table public.device_bindings (
  device_id      uuid primary key references public.devices (id) on delete cascade,
  integration_id uuid not null references public.integrations (id) on delete cascade,
  external_id    text not null,
  unique (integration_id, external_id)
);

create table public.device_capabilities (
  device_id      uuid not null references public.devices (id) on delete cascade,
  capability_key text not null,  -- ex. 'switch', 'brightness', 'color', 'temperature', 'cover_position'
  type           text not null check (type in ('boolean', 'number', 'enum', 'color', 'string', 'sensor')),
  writable       boolean not null default true,
  metadata       jsonb not null default '{}'::jsonb,  -- min/max/step/unit/options
  primary key (device_id, capability_key)
);

-- -----------------------------------------------------------------------------
-- Commandes (§5.4, §6.1) — le client crée, le backend exécute et confirme
-- -----------------------------------------------------------------------------
create table public.device_commands (
  id              uuid primary key default gen_random_uuid(),  -- = identifiant de requête corrélé
  home_id         uuid not null references public.homes (id) on delete cascade,
  device_id       uuid not null references public.devices (id) on delete cascade,
  requested_by    uuid references public.profiles (id) on delete set null,
  capability_key  text not null,
  value           jsonb not null,
  idempotency_key text not null,
  status          public.command_status not null default 'pending',
  error           text,
  created_at      timestamptz not null default now(),
  completed_at    timestamptz,
  unique (requested_by, idempotency_key)  -- évite les doubles commandes
);
create index device_commands_device_idx on public.device_commands (device_id, created_at desc);
create index device_commands_pending_idx on public.device_commands (status) where status in ('pending', 'sent');

-- Validation à l'insertion : maison cohérente, capacité existante et modifiable,
-- appareil sensible bloqué, statut forcé à 'pending'.
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
    raise exception 'Commande bloquée : appareil sensible non validé';
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
create trigger device_commands_validate before insert on public.device_commands
  for each row execute function public.validate_device_command();

-- -----------------------------------------------------------------------------
-- Scènes (Scene, SceneAction, §5.9)
-- -----------------------------------------------------------------------------
create table public.scenes (
  id             uuid primary key default gen_random_uuid(),
  home_id        uuid not null references public.homes (id) on delete cascade,
  name           text not null,
  icon           text,
  enabled        boolean not null default true,
  failure_policy public.failure_policy not null default 'continue',
  created_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index scenes_home_idx on public.scenes (home_id);
create trigger scenes_updated_at before update on public.scenes
  for each row execute function public.set_updated_at();

create table public.scene_actions (
  id             uuid primary key default gen_random_uuid(),
  scene_id       uuid not null references public.scenes (id) on delete cascade,
  device_id      uuid not null references public.devices (id) on delete cascade,
  capability_key text not null,
  value          jsonb not null,
  position       integer not null default 0,
  delay_ms       integer not null default 0 check (delay_ms between 0 and 600000)
);
create index scene_actions_scene_idx on public.scene_actions (scene_id, position);

create or replace function public.check_scene_action()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.scenes s join public.devices d on d.home_id = s.home_id
    where s.id = new.scene_id and d.id = new.device_id
  ) then
    raise exception 'L''appareil n''appartient pas à la maison de la scène';
  end if;
  return new;
end $$;
create trigger scene_actions_check before insert or update on public.scene_actions
  for each row execute function public.check_scene_action();

create table public.scene_runs (
  id           uuid primary key default gen_random_uuid(),
  scene_id     uuid not null references public.scenes (id) on delete cascade,
  home_id      uuid not null references public.homes (id) on delete cascade,
  triggered_by uuid references public.profiles (id) on delete set null,
  automation_id uuid,
  status       text not null default 'running' check (status in ('running', 'success', 'partial', 'failed')),
  results      jsonb not null default '[]'::jsonb,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index scene_runs_scene_idx on public.scene_runs (scene_id, started_at desc);

-- -----------------------------------------------------------------------------
-- Automatisations (Automation, §5.9)
--   trigger    : {"type":"manual"} | {"type":"time","at":"07:30","days":[1,2,3]}
--                | {"type":"device_state","device_id":"…","capability_key":"…","op":"eq","value":…}
--   conditions : [{"type":"device_state",…} | {"type":"time_range","from":"22:00","to":"06:00"}]
--   actions    : [{"device_id":"…","capability_key":"…","value":…} | {"scene_id":"…"}]
-- -----------------------------------------------------------------------------
create table public.automations (
  id          uuid primary key default gen_random_uuid(),
  home_id     uuid not null references public.homes (id) on delete cascade,
  name        text not null,
  enabled     boolean not null default true,
  trigger     jsonb not null check (trigger ? 'type'),
  conditions  jsonb not null default '[]'::jsonb check (jsonb_typeof(conditions) = 'array'),
  actions     jsonb not null check (jsonb_typeof(actions) = 'array' and jsonb_array_length(actions) > 0),
  run_locally boolean not null default true,  -- exécution locale privilégiée (HA)
  last_run_at timestamptz,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index automations_home_idx on public.automations (home_id);
create trigger automations_updated_at before update on public.automations
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Journal d'événements (EventLog, §5.10) — écrit par le backend/triggers uniquement
-- -----------------------------------------------------------------------------
create table public.event_logs (
  id         bigint generated always as identity primary key,
  home_id    uuid not null references public.homes (id) on delete cascade,
  actor_id   uuid references public.profiles (id) on delete set null,
  event_type text not null,  -- command, command_failed, device_unavailable, config_changed, member_changed…
  device_id  uuid references public.devices (id) on delete set null,
  request_id uuid,           -- corrélation avec device_commands.id
  result     text,
  details    jsonb not null default '{}'::jsonb,  -- jamais de secrets
  created_at timestamptz not null default now()
);
create index event_logs_home_idx on public.event_logs (home_id, created_at desc);

create or replace function public.log_event(
  p_home_id uuid, p_event_type text, p_device_id uuid default null,
  p_request_id uuid default null, p_result text default null, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.event_logs (home_id, actor_id, event_type, device_id, request_id, result, details)
  values (p_home_id, auth.uid(), p_event_type, p_device_id, p_request_id, p_result, p_details)
$$;
revoke execute on function public.log_event(uuid, text, uuid, uuid, text, jsonb) from public, anon, authenticated;

-- Journalisation automatique : commandes et changements de membres
create or replace function public.trg_log_command()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_event(new.home_id, 'command', new.device_id, new.id, 'pending',
      jsonb_build_object('capability_key', new.capability_key));
  elsif new.status is distinct from old.status and new.status <> 'sent' then
    perform public.log_event(new.home_id,
      case when new.status = 'confirmed' then 'command' else 'command_failed' end,
      new.device_id, new.id, new.status::text, jsonb_build_object('error', new.error));
  end if;
  return new;
end $$;
create trigger device_commands_log after insert or update of status on public.device_commands
  for each row execute function public.trg_log_command();

create or replace function public.trg_log_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record := coalesce(new, old);
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.homes where id = old.home_id) then
    return old;  -- maison supprimée en cascade
  end if;
  perform public.log_event(r.home_id, 'member_changed', null, null, lower(tg_op),
    jsonb_build_object('user_id', r.user_id, 'role', r.role));
  return r;
end $$;
create trigger home_members_log after insert or update or delete on public.home_members
  for each row execute function public.trg_log_membership();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.homes               enable row level security;
alter table public.home_members        enable row level security;
alter table public.home_invitations    enable row level security;
alter table public.rooms               enable row level security;
alter table public.integrations        enable row level security;
alter table public.integration_secrets enable row level security;
alter table public.devices             enable row level security;
alter table public.device_bindings     enable row level security;
alter table public.device_capabilities enable row level security;
alter table public.device_commands     enable row level security;
alter table public.scenes              enable row level security;
alter table public.scene_actions       enable row level security;
alter table public.scene_runs          enable row level security;
alter table public.automations         enable row level security;
alter table public.event_logs          enable row level security;

-- Profils : soi-même + co-membres d'une maison (nom affiché)
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or exists (
    select 1 from public.home_members a join public.home_members b on a.home_id = b.home_id
    where a.user_id = auth.uid() and b.user_id = profiles.id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Maisons
create policy homes_select on public.homes for select to authenticated
  using (public.is_home_member(id));
create policy homes_insert on public.homes for insert to authenticated
  with check (owner_id = auth.uid());
create policy homes_update on public.homes for update to authenticated
  using (public.is_home_manager(id)) with check (public.is_home_manager(id));
create policy homes_delete on public.homes for delete to authenticated
  using (owner_id = auth.uid());

-- Membres : lecture par les membres ; gestion par owner/admin ; on peut se retirer soi-même.
-- Le rôle 'owner' ne peut être attribué que par le propriétaire (transfert contrôlé).
create policy members_select on public.home_members for select to authenticated
  using (public.is_home_member(home_id));
create policy members_insert on public.home_members for insert to authenticated
  with check (public.is_home_manager(home_id)
              and (role <> 'owner' or public.home_role_of(home_id) = 'owner'));
create policy members_update on public.home_members for update to authenticated
  using (public.is_home_manager(home_id) and role <> 'owner')
  with check (public.is_home_manager(home_id)
              and (role <> 'owner' or public.home_role_of(home_id) = 'owner'));
create policy members_delete on public.home_members for delete to authenticated
  using ((public.is_home_manager(home_id) and role <> 'owner')
         or (user_id = auth.uid() and role <> 'owner'));

-- Invitations
create policy invitations_manage on public.home_invitations for all to authenticated
  using (public.is_home_manager(home_id))
  with check (public.is_home_manager(home_id) and invited_by = auth.uid());

-- Pièces
create policy rooms_select on public.rooms for select to authenticated
  using (public.is_home_member(home_id));
create policy rooms_write on public.rooms for all to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));

-- Intégrations : métadonnées lisibles par owner/admin ; création via backend (flux sécurisé §8)
create policy integrations_select on public.integrations for select to authenticated
  using (public.is_home_manager(home_id));
-- integration_secrets, device_bindings : aucune policy => refus total côté client.

-- Appareils : lecture selon droits ; owner/admin/installateur peuvent renommer/déplacer/épingler.
-- Création/suppression réservées au backend de synchronisation (service_role).
create policy devices_select on public.devices for select to authenticated
  using (public.can_use_device(id));
create policy devices_update on public.devices for update to authenticated
  using (public.home_role_of(home_id) in ('owner', 'admin', 'installer'))
  with check (public.home_role_of(home_id) in ('owner', 'admin', 'installer'));

create policy capabilities_select on public.device_capabilities for select to authenticated
  using (public.can_use_device(device_id));

-- Commandes : un membre autorisé crée une commande sur un appareil qu'il peut utiliser
create policy commands_select on public.device_commands for select to authenticated
  using (public.is_home_member(home_id) and public.can_use_device(device_id));
create policy commands_insert on public.device_commands for insert to authenticated
  with check (public.can_use_device(device_id));

-- Scènes / automatisations : lecture par les membres, gestion par owner/admin
create policy scenes_select on public.scenes for select to authenticated
  using (public.is_home_member(home_id));
create policy scenes_write on public.scenes for all to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));

create policy scene_actions_select on public.scene_actions for select to authenticated
  using (exists (select 1 from public.scenes s where s.id = scene_id and public.is_home_member(s.home_id)));
create policy scene_actions_write on public.scene_actions for all to authenticated
  using (exists (select 1 from public.scenes s where s.id = scene_id and public.is_home_manager(s.home_id)))
  with check (exists (select 1 from public.scenes s where s.id = scene_id and public.is_home_manager(s.home_id)));

create policy scene_runs_select on public.scene_runs for select to authenticated
  using (public.is_home_member(home_id));

create policy automations_select on public.automations for select to authenticated
  using (public.is_home_member(home_id));
create policy automations_write on public.automations for all to authenticated
  using (public.is_home_manager(home_id)) with check (public.is_home_manager(home_id));

-- Journal : lecture seule
create policy event_logs_select on public.event_logs for select to authenticated
  using (public.is_home_member(home_id));

-- -----------------------------------------------------------------------------
-- Privilèges : secrets et liaisons fermés ; seules les colonnes "présentation"
-- des appareils sont modifiables par le client.
-- -----------------------------------------------------------------------------
revoke all on public.integration_secrets, public.device_bindings from anon, authenticated;
revoke insert, update, delete on public.devices from anon, authenticated;
grant update (name, room_id, is_pinned, is_hidden) on public.devices to authenticated;

revoke all on public.device_commands from anon, authenticated;
grant select on public.device_commands to authenticated;
grant insert (home_id, device_id, capability_key, value, idempotency_key) on public.device_commands to authenticated;

revoke insert, update, delete on public.event_logs, public.scene_runs, public.device_capabilities,
  public.integrations from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Temps réel (§10) : états des appareils et résultats des commandes
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.devices, public.device_commands, public.scene_runs;
  end if;
end $$;
