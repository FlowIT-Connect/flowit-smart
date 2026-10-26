-- =============================================================================
-- FlowIT Smart — fonctions applicatives (complète 20261026000000_flowit_smart_init.sql)
--
--   * Exécution de scène côté serveur : contrôle des droits, une commande par action,
--     délais (not_before), politique d'échec, agrégation des résultats dans scene_runs (§5.9).
--   * Création de maison (create_home) et d'intégration par owner/admin (les secrets restent dans la passerelle locale).
--   * Invitations reçues, transfert de propriété, suppression de compte (§5.1, §5.2).
--   * Journalisation des changements de configuration et des appareils indisponibles (§5.10).
--   * Purge du journal selon une durée de conservation (§5.10).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Commandes : rattachement à une exécution de scène / automatisation, exécution différée
-- (colonnes non accordées au client : seules les fonctions serveur les renseignent)
-- -----------------------------------------------------------------------------
alter table public.device_commands
  add column scene_run_id  uuid references public.scene_runs (id) on delete set null,
  add column automation_id uuid references public.automations (id) on delete set null,
  add column not_before    timestamptz not null default now();
create index device_commands_scene_run_idx on public.device_commands (scene_run_id) where scene_run_id is not null;

alter table public.scene_runs
  add constraint scene_runs_automation_fk foreign key (automation_id)
  references public.automations (id) on delete set null;

create or replace function public.is_service_role()
returns boolean language sql stable as $$
  select coalesce(auth.role(), '') = 'service_role'
$$;

-- -----------------------------------------------------------------------------
-- Exécuter une scène
-- -----------------------------------------------------------------------------
create or replace function public.execute_scene(p_scene_id uuid, p_automation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  s        public.scenes;
  a        record;
  v_run_id uuid;
  v_at     timestamptz := now();
  v_issued int := 0;
  v_results jsonb := '[]'::jsonb;
  v_reason text;
  v_service boolean := public.is_service_role();
begin
  select * into s from public.scenes where id = p_scene_id;
  if not found or (not v_service and not public.is_home_member(s.home_id)) then
    raise exception 'Scène introuvable';
  end if;
  if not s.enabled then
    raise exception 'Scène désactivée';
  end if;

  insert into public.scene_runs (scene_id, home_id, triggered_by, automation_id)
  values (s.id, s.home_id, case when v_service then null else auth.uid() end, p_automation_id)
  returning id into v_run_id;

  for a in
    select sa.*, d.is_sensitive
    from public.scene_actions sa
    join public.devices d on d.id = sa.device_id
    where sa.scene_id = s.id
    order by sa.position, sa.id
  loop
    v_at := v_at + make_interval(secs => a.delay_ms / 1000.0);
    v_reason := null;
    if a.is_sensitive then
      v_reason := 'Appareil sensible bloqué';
    elsif not v_service and not public.can_use_device(a.device_id) then
      v_reason := 'Accès refusé à cet appareil';
    elsif not exists (select 1 from public.device_capabilities c
                      where c.device_id = a.device_id and c.capability_key = a.capability_key and c.writable) then
      v_reason := 'Capacité non prise en charge';
    end if;

    if v_reason is not null then
      v_results := v_results || jsonb_build_object('action_id', a.id, 'device_id', a.device_id,
        'capability_key', a.capability_key, 'status', 'rejected', 'error', v_reason);
      exit when s.failure_policy = 'stop';
      continue;
    end if;

    insert into public.device_commands
      (home_id, device_id, capability_key, value, idempotency_key, scene_run_id, automation_id, not_before)
    values
      (s.home_id, a.device_id, a.capability_key, a.value, 'scene:' || v_run_id || ':' || a.id,
       v_run_id, p_automation_id, v_at);
    v_issued := v_issued + 1;
  end loop;

  -- Une action refusée avec politique "stop" : rien n'est envoyé
  if s.failure_policy = 'stop' and jsonb_array_length(v_results) > 0 and v_issued > 0 then
    update public.device_commands
      set status = 'rejected', error = 'Scène interrompue', completed_at = now()
      where scene_run_id = v_run_id;
  end if;

  update public.scene_runs set results = v_results || results where id = v_run_id;
  perform public.finalize_scene_run(v_run_id);

  insert into public.event_logs (home_id, actor_id, event_type, result, details)
  values (s.home_id, case when v_service then null else auth.uid() end, 'scene_started', 'running',
          jsonb_build_object('scene_id', s.id, 'scene_run_id', v_run_id, 'automation_id', p_automation_id));
  return v_run_id;
end $$;
revoke execute on function public.execute_scene(uuid, uuid) from public, anon;
grant execute on function public.execute_scene(uuid, uuid) to authenticated, service_role;

-- Clôt l'exécution quand plus aucune commande n'est en attente
create or replace function public.finalize_scene_run(p_run_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.scene_runs;
  v_total int;
  v_ok int;
begin
  select * into r from public.scene_runs where id = p_run_id and finished_at is null for update;
  if not found then return; end if;
  if exists (select 1 from public.device_commands
             where scene_run_id = p_run_id and status in ('pending', 'sent')) then
    return;
  end if;
  select count(*), count(*) filter (where e ->> 'status' = 'confirmed')
    into v_total, v_ok
    from jsonb_array_elements(r.results) e;
  update public.scene_runs
    set status = case when v_ok = v_total then 'success' when v_ok = 0 then 'failed' else 'partial' end,
        finished_at = now()
    where id = p_run_id;
  insert into public.event_logs (home_id, event_type, result, details)
  values (r.home_id, 'scene_finished',
          case when v_ok = v_total then 'success' when v_ok = 0 then 'failed' else 'partial' end,
          jsonb_build_object('scene_id', r.scene_id, 'scene_run_id', p_run_id, 'confirmed', v_ok, 'total', v_total));
end $$;
revoke execute on function public.finalize_scene_run(uuid) from public, anon, authenticated;

-- Résultat d'une commande de scène : ajout au rapport, arrêt si politique "stop"
create or replace function public.trg_scene_command_done()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_policy public.failure_policy;
begin
  if new.scene_run_id is null or new.status in ('pending', 'sent') or new.status = old.status then
    return new;
  end if;
  update public.scene_runs
    set results = results || jsonb_build_object('command_id', new.id, 'device_id', new.device_id,
          'capability_key', new.capability_key, 'status', new.status, 'error', new.error)
    where id = new.scene_run_id;
  select s.failure_policy into v_policy
    from public.scene_runs r join public.scenes s on s.id = r.scene_id
    where r.id = new.scene_run_id;
  if new.status <> 'confirmed' and v_policy = 'stop' then
    update public.device_commands
      set status = 'rejected', error = 'Scène interrompue', completed_at = now()
      where scene_run_id = new.scene_run_id and status = 'pending';
  end if;
  perform public.finalize_scene_run(new.scene_run_id);
  return new;
end $$;
create trigger device_commands_scene_done after update of status on public.device_commands
  for each row execute function public.trg_scene_command_done();

-- -----------------------------------------------------------------------------
-- Intégrations : déclarées par owner/admin. Le jeton Home Assistant reste dans la
-- passerelle locale FlowIT Bridge et ne transite jamais par l'application (§6.2).
-- -----------------------------------------------------------------------------
create or replace function public.create_integration(
  p_home_id uuid, p_provider public.integration_provider, p_label text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.is_home_manager(p_home_id) then
    raise exception 'Accès refusé';
  end if;
  insert into public.integrations (home_id, provider, label)
  values (p_home_id, p_provider, nullif(trim(p_label), ''))
  returning id into v_id;
  perform public.log_event(p_home_id, 'config_changed', null, null, 'integration_created',
    jsonb_build_object('integration_id', v_id, 'provider', p_provider));
  return v_id;
end $$;
revoke execute on function public.create_integration(uuid, public.integration_provider, text) from public, anon;
grant execute on function public.create_integration(uuid, public.integration_provider, text) to authenticated;

create or replace function public.set_integration_enabled(p_integration_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  i public.integrations;
begin
  select * into i from public.integrations where id = p_integration_id;
  if not found or not public.is_home_manager(i.home_id) then
    raise exception 'Accès refusé';
  end if;
  update public.integrations
    set status = case when p_enabled then 'pending'::public.integration_status else 'disabled' end
    where id = i.id;
  perform public.log_event(i.home_id, 'config_changed', null, null,
    case when p_enabled then 'integration_enabled' else 'integration_disabled' end,
    jsonb_build_object('integration_id', i.id));
end $$;
revoke execute on function public.set_integration_enabled(uuid, boolean) from public, anon;
grant execute on function public.set_integration_enabled(uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- Créer une maison et renvoyer son id. Un INSERT ... RETURNING direct échoue :
-- la ligne n'est visible (homes_select) qu'après le trigger qui ajoute le propriétaire.
-- -----------------------------------------------------------------------------
create or replace function public.create_home(p_name text, p_timezone text default 'Africa/Algiers')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Non authentifié';
  end if;
  insert into public.homes (owner_id, name, timezone)
  values (auth.uid(), trim(p_name), coalesce(nullif(trim(p_timezone), ''), 'Africa/Algiers'))
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.create_home(text, text) from public, anon;
grant execute on function public.create_home(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Invitations reçues par l'utilisateur connecté (par son e-mail vérifié)
-- -----------------------------------------------------------------------------
create or replace function public.list_my_invitations()
returns table (id uuid, home_id uuid, home_name text, role public.home_role, token text, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id, i.home_id, h.name, i.role, i.token, i.expires_at
  from public.home_invitations i
  join public.homes h on h.id = i.home_id
  where lower(i.email) = lower((select email from auth.users where id = auth.uid()))
    and i.accepted_at is null
    and i.expires_at > now()
  order by i.created_at desc
$$;
revoke execute on function public.list_my_invitations() from public, anon;
grant execute on function public.list_my_invitations() to authenticated;

-- -----------------------------------------------------------------------------
-- Transfert de propriété : le propriétaire actuel devient administrateur
-- -----------------------------------------------------------------------------
create or replace function public.transfer_home_ownership(p_home_id uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.home_role_of(p_home_id) is distinct from 'owner' then
    raise exception 'Seul le propriétaire peut transférer la maison';
  end if;
  if p_new_owner = auth.uid() or not exists (
    select 1 from public.home_members where home_id = p_home_id and user_id = p_new_owner
      and (expires_at is null or expires_at > now())) then
    raise exception 'Le nouveau propriétaire doit être membre de la maison';
  end if;
  update public.home_members set role = 'admin' where home_id = p_home_id and user_id = auth.uid();
  update public.home_members set role = 'owner', expires_at = null, permissions = '{}'::jsonb
    where home_id = p_home_id and user_id = p_new_owner;
  update public.homes set owner_id = p_new_owner where id = p_home_id;
end $$;
revoke execute on function public.transfer_home_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_home_ownership(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Suppression de compte (§5.1) : supprime les maisons possédées puis l'utilisateur.
-- L'application demande une confirmation explicite avant l'appel.
-- -----------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Non authentifié';
  end if;
  delete from public.homes where owner_id = v_uid;
  delete from auth.users where id = v_uid;
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- -----------------------------------------------------------------------------
-- Journalisation : changements de configuration, appareils indisponibles
-- -----------------------------------------------------------------------------
create or replace function public.trg_log_config()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.homes where id = (r ->> 'home_id')::uuid) then
    return old;  -- maison supprimée en cascade
  end if;
  perform public.log_event((r ->> 'home_id')::uuid, 'config_changed', null, null,
    tg_table_name || '_' || lower(tg_op),
    jsonb_build_object('id', r ->> 'id', 'name', r ->> 'name'));
  return coalesce(new, old);
end $$;
create trigger rooms_log after insert or update of name, icon or delete on public.rooms
  for each row execute function public.trg_log_config();
create trigger scenes_log after insert or update of name, enabled, failure_policy or delete on public.scenes
  for each row execute function public.trg_log_config();
create trigger automations_log after insert or update of name, enabled, trigger, conditions, actions or delete
  on public.automations for each row execute function public.trg_log_config();

create or replace function public.trg_log_device()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.availability is distinct from old.availability and new.availability = 'unavailable' then
    perform public.log_event(new.home_id, 'device_unavailable', new.id, null, 'unavailable', '{}'::jsonb);
  elsif new.availability is distinct from old.availability and old.availability = 'unavailable' then
    perform public.log_event(new.home_id, 'device_available', new.id, null, new.availability::text, '{}'::jsonb);
  end if;
  if (new.name, new.room_id, new.is_hidden) is distinct from (old.name, old.room_id, old.is_hidden) then
    perform public.log_event(new.home_id, 'config_changed', new.id, null, 'device_update',
      jsonb_build_object('name', new.name, 'room_id', new.room_id, 'is_hidden', new.is_hidden));
  end if;
  return new;
end $$;
create trigger devices_log after update on public.devices
  for each row execute function public.trg_log_device();

-- -----------------------------------------------------------------------------
-- Conservation du journal (§5.10) : à planifier avec pg_cron, ex.
--   select cron.schedule('purge-events', '0 3 * * *', $$select public.purge_event_logs(180)$$);
-- -----------------------------------------------------------------------------
create or replace function public.purge_event_logs(p_days integer default 180)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  delete from public.event_logs where created_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  delete from public.device_commands
    where created_at < now() - make_interval(days => p_days) and status not in ('pending', 'sent');
  return n;
end $$;
revoke execute on function public.purge_event_logs(integer) from public, anon, authenticated;

-- Temps réel : nouveaux appareils / capacités synchronisés par la passerelle
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.device_capabilities, public.event_logs;
  end if;
end $$;
