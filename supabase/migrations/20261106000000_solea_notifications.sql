-- =============================================================================
-- Solea — centre de notifications
--
--   notifications : une ligne par destinataire (lue / non lue, catégorie,
--                   priorité). Créées côté serveur uniquement : par les
--                   déclencheurs ci-dessous quand la passerelle écrit l'état
--                   réel d'un appareil, ou par la passerelle elle-même
--                   (notify_home : vents forts, volets fermés automatiquement).
--   Réglages      : profiles.preferences -> 'notifications'
--                   {"off": ["motion", …], "temp_max": 35, "temp_min": 5}
--   push_tokens   : jetons des téléphones pour les notifications push
--                   (application fermée), utilisés par l'envoi push.
--
-- Les 12 types : motion, door_open, door_closed, window_open, water_leak,
-- smoke, camera_offline, device_offline, temperature_abnormal,
-- automation_run, high_wind, shutters_auto_closed.
-- =============================================================================

create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  home_id    uuid not null references public.homes (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       text not null check (type in ('motion', 'door_open', 'door_closed', 'window_open', 'water_leak', 'smoke',
                                           'camera_offline', 'device_offline', 'temperature_abnormal', 'automation_run',
                                           'high_wind', 'shutters_auto_closed')),
  category   text not null check (category in ('security', 'alarm', 'devices', 'climate', 'automation')),
  priority   text not null check (priority in ('low', 'normal', 'high', 'critical')),
  device_id  uuid references public.devices (id) on delete set null,
  ref        text not null default '',   -- regroupement anti-doublon (appareil, automatisation…)
  title      text not null check (length(title) <= 120),
  body       text not null default '' check (length(body) <= 300),
  data       jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 2048),
  read_at    timestamptz,
  pushed_at  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
create index if not exists notifications_dedupe_idx on public.notifications (user_id, type, ref, created_at desc);
create index if not exists notifications_unread_idx on public.notifications (user_id) where read_at is null;

alter table public.notifications enable row level security;
drop policy if exists notifications_select on public.notifications;
drop policy if exists notifications_update on public.notifications;
drop policy if exists notifications_delete on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_delete on public.notifications for delete to authenticated
  using (user_id = auth.uid());
-- Le client ne peut que marquer comme lu (ou supprimer) : jamais créer ni réécrire.
revoke insert, update on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create table if not exists public.push_tokens (
  token      text primary key check (length(token) between 20 and 4096),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios', 'web')),
  locale     text check (locale is null or locale ~ '^[a-z]{2}$'),
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Catalogue : catégorie, priorité, délai anti-doublon et textes par défaut
-- -----------------------------------------------------------------------------
create or replace function public.notification_meta(p_type text,
  out category text, out priority text, out quiet interval, out title text)
language sql immutable set search_path = '' as $$
  select m.category, m.priority, m.quiet, m.title from (values
    ('motion',               'security',   'high',     interval '10 minutes', 'Mouvement détecté'),
    ('door_open',            'security',   'high',     interval '2 minutes',  'Porte ouverte'),
    ('door_closed',          'security',   'low',      interval '2 minutes',  'Porte fermée'),
    ('window_open',          'security',   'normal',   interval '2 minutes',  'Fenêtre ouverte'),
    ('water_leak',           'alarm',      'critical', interval '15 minutes', 'Fuite d''eau'),
    ('smoke',                'alarm',      'critical', interval '5 minutes',  'Fumée détectée'),
    ('camera_offline',       'devices',    'high',     interval '30 minutes', 'Caméra hors ligne'),
    ('device_offline',       'devices',    'normal',   interval '30 minutes', 'Appareil déconnecté'),
    ('temperature_abnormal', 'climate',    'high',     interval '60 minutes', 'Température anormale'),
    ('automation_run',       'automation', 'low',      interval '1 minute',   'Automatisation exécutée'),
    ('high_wind',            'climate',    'high',     interval '30 minutes', 'Vents forts détectés'),
    ('shutters_auto_closed', 'automation', 'normal',   interval '5 minutes',  'Volets fermés automatiquement')
  ) as m(type, category, priority, quiet, title)
  where m.type = p_type
$$;

-- -----------------------------------------------------------------------------
-- Envoi à tous les membres d'une maison, selon les réglages de chacun.
-- p_temp : température mesurée (temperature_abnormal), comparée aux seuils
-- propres à chaque membre.
-- -----------------------------------------------------------------------------
create or replace function public.notify_home(
  p_home_id uuid, p_type text, p_device_id uuid default null, p_body text default '',
  p_data jsonb default '{}'::jsonb, p_ref text default null, p_temp numeric default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  m record;
  meta record;
  v_ref text := coalesce(p_ref, p_device_id::text, '');
  v_count integer := 0;
  v_prefs jsonb;
  v_max numeric;
  v_min numeric;
begin
  select * into meta from public.notification_meta(p_type);
  if meta.category is null then
    raise exception 'Type de notification inconnu : %', p_type;
  end if;
  for m in
    select hm.user_id, hm.role, hm.permissions, p.preferences
    from public.home_members hm join public.profiles p on p.id = hm.user_id
    where hm.home_id = p_home_id and (hm.expires_at is null or hm.expires_at > now())
  loop
    v_prefs := coalesce(m.preferences -> 'notifications', '{}'::jsonb);
    continue when jsonb_typeof(v_prefs -> 'off') = 'array' and (v_prefs -> 'off') ? p_type;
    -- Membre limité à certains appareils : seulement les siens.
    continue when p_device_id is not null and m.role = 'member' and m.permissions ? 'devices'
                  and not (m.permissions -> 'devices' ? p_device_id::text);
    if p_type = 'temperature_abnormal' then
      v_max := case when jsonb_typeof(v_prefs -> 'temp_max') = 'number' then (v_prefs ->> 'temp_max')::numeric else 35 end;
      v_min := case when jsonb_typeof(v_prefs -> 'temp_min') = 'number' then (v_prefs ->> 'temp_min')::numeric else 5 end;
      continue when p_temp is null or (p_temp < v_max and p_temp > v_min);
    end if;
    continue when exists (
      select 1 from public.notifications n
      where n.user_id = m.user_id and n.type = p_type and n.ref = v_ref and n.created_at > now() - meta.quiet);
    insert into public.notifications (home_id, user_id, type, category, priority, device_id, ref, title, body, data)
    values (p_home_id, m.user_id, p_type, meta.category, meta.priority, p_device_id, v_ref,
            meta.title, left(coalesce(p_body, ''), 300), coalesce(p_data, '{}'::jsonb));
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke execute on function public.notify_home(uuid, text, uuid, text, jsonb, text, numeric) from public, anon, authenticated;
grant execute on function public.notify_home(uuid, text, uuid, text, jsonb, text, numeric) to service_role;

-- -----------------------------------------------------------------------------
-- État réel des appareils (écrit par la passerelle) -> notifications
-- -----------------------------------------------------------------------------
create or replace function public.trg_device_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_room text;
  v_body text;
  v_data jsonb;
  v_is_camera boolean;
  v_is_window boolean;
  k text;
  v_old jsonb := coalesce(old.state, '{}'::jsonb);
  v_new jsonb := coalesce(new.state, '{}'::jsonb);
  v_temp numeric;
  v_old_temp numeric;
begin
  select name into v_room from public.rooms where id = new.room_id;
  v_body := new.name || coalesce(' · ' || v_room, '');
  v_data := jsonb_build_object('device', new.name, 'room', v_room);

  -- Passage hors ligne
  if old.availability = 'available' and new.availability = 'unavailable' then
    v_is_camera := v_new ? 'camera' or exists (
      select 1 from public.device_capabilities c where c.device_id = new.id and c.capability_key in ('camera', 'snapshot', 'stream'));
    perform public.notify_home(new.home_id, case when v_is_camera then 'camera_offline' else 'device_offline' end,
                               new.id, v_body, v_data);
    return new;
  end if;
  if new.availability <> 'available' or v_old = v_new then
    return new;
  end if;

  if v_new -> 'motion' = 'true'::jsonb and v_old -> 'motion' is distinct from 'true'::jsonb then
    perform public.notify_home(new.home_id, 'motion', new.id, v_body, v_data);
  end if;

  -- Convention Solea : contact = true quand c'est fermé.
  if v_new ? 'contact' and v_new -> 'contact' is distinct from v_old -> 'contact' then
    v_is_window := new.name ~* '(fen[eê]tre|window|baie|velux|نافذة|شباك)'
      or exists (select 1 from public.device_capabilities c
                 where c.device_id = new.id and c.capability_key = 'contact' and c.metadata ->> 'device_class' = 'window');
    if v_new -> 'contact' = 'false'::jsonb then
      perform public.notify_home(new.home_id, case when v_is_window then 'window_open' else 'door_open' end, new.id, v_body, v_data);
    elsif v_new -> 'contact' = 'true'::jsonb and v_old -> 'contact' = 'false'::jsonb and not v_is_window then
      perform public.notify_home(new.home_id, 'door_closed', new.id, v_body, v_data);
    end if;
  end if;

  if v_new -> 'smoke' = 'true'::jsonb and v_old -> 'smoke' is distinct from 'true'::jsonb then
    perform public.notify_home(new.home_id, 'smoke', new.id, v_body, v_data);
  end if;

  foreach k in array array['water_leak', 'leak', 'moisture'] loop
    if v_new -> k = 'true'::jsonb and v_old -> k is distinct from 'true'::jsonb then
      perform public.notify_home(new.home_id, 'water_leak', new.id, v_body, v_data);
      exit;
    end if;
  end loop;

  -- Température : seuils propres à chaque membre (notify_home), rappel au plus une fois par heure.
  if jsonb_typeof(v_new -> 'temperature') = 'number' then
    v_temp := (v_new ->> 'temperature')::numeric;
    v_old_temp := case when jsonb_typeof(v_old -> 'temperature') = 'number' then (v_old ->> 'temperature')::numeric end;
    if v_old_temp is distinct from v_temp then
      perform public.notify_home(new.home_id, 'temperature_abnormal', new.id,
                                 v_body || ' · ' || trim(to_char(v_temp, 'FM990.0')) || ' °C',
                                 v_data || jsonb_build_object('temperature', v_temp), null, v_temp);
    end if;
  end if;
  return new;
exception when others then
  -- Une notification ratée ne doit jamais bloquer l'écriture de l'état réel.
  raise warning 'notification ignorée : %', sqlerrm;
  return new;
end $$;

drop trigger if exists devices_notifications on public.devices;
create trigger devices_notifications after update of state, availability on public.devices
  for each row execute function public.trg_device_notifications();

-- Automatisation exécutée (la passerelle met à jour last_run_at)
create or replace function public.trg_automation_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.last_run_at is distinct from old.last_run_at and new.last_run_at is not null then
    perform public.notify_home(new.home_id, 'automation_run', null, new.name,
                               jsonb_build_object('automation', new.name, 'automation_id', new.id), new.id::text);
  end if;
  return new;
exception when others then
  -- Une notification ratée ne doit jamais bloquer l'écriture de l'état réel.
  raise warning 'notification ignorée : %', sqlerrm;
  return new;
end $$;
drop trigger if exists automations_notifications on public.automations;
create trigger automations_notifications after update of last_run_at on public.automations
  for each row execute function public.trg_automation_notifications();

-- Caméra ou interphone qui passe hors ligne
create or replace function public.trg_video_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'online' and new.status in ('offline', 'error') then
    perform public.notify_home(new.home_id, 'camera_offline', new.device_id, new.name,
                               jsonb_build_object('device', new.name), coalesce(new.device_id::text, new.id::text));
  end if;
  return new;
exception when others then
  -- Une notification ratée ne doit jamais bloquer l'écriture de l'état réel.
  raise warning 'notification ignorée : %', sqlerrm;
  return new;
end $$;
drop trigger if exists video_sources_notifications on public.video_sources;
create trigger video_sources_notifications after update of status on public.video_sources
  for each row execute function public.trg_video_notifications();

-- -----------------------------------------------------------------------------
-- Raccourcis du client
-- -----------------------------------------------------------------------------
create or replace function public.mark_notifications_read(p_home_id uuid default null)
returns integer language sql security invoker set search_path = '' as $$
  with u as (
    update public.notifications set read_at = now()
    where user_id = auth.uid() and read_at is null and (p_home_id is null or home_id = p_home_id)
    returning 1)
  select count(*)::integer from u
$$;
grant execute on function public.mark_notifications_read(uuid) to authenticated;

create or replace function public.purge_notifications(p_days integer default 90)
returns integer language sql security definer set search_path = '' as $$
  with d as (delete from public.notifications where created_at < now() - make_interval(days => p_days) returning 1)
  select count(*)::integer from d
$$;
revoke execute on function public.purge_notifications(integer) from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
