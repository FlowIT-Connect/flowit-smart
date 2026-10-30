-- =============================================================================
-- Solea — ouverture des serrures TTLock en Bluetooth depuis l'app Android
--
-- Sans passerelle TTLock (G2/G3), seule une connexion Bluetooth devant la porte peut
-- ouvrir la serrure. L'app Android a besoin pour cela de la « clé Bluetooth » de la
-- serrure (lockData TTLock), que la passerelle lit avec le compte administrateur.
--
--   device_ble_keys : clé Bluetooth par appareil, écrite par la passerelle (service_role).
--                     Aucune lecture directe : seulement via get_ble_key().
--   get_ble_key()   : propriétaire ou administrateur, appareil activé (§9), journalisé.
--   log_ble_action(): résultat de l'ouverture / fermeture Bluetooth, inscrit au journal.
-- =============================================================================

create table if not exists public.device_ble_keys (
  device_id  uuid primary key references public.devices (id) on delete cascade,
  home_id    uuid not null references public.homes (id) on delete cascade,
  lock_data  text not null,
  updated_at timestamptz not null default now()
);

alter table public.device_ble_keys enable row level security;
-- Pas de politique : ni anon ni authenticated ne lisent la table directement.
revoke all on public.device_ble_keys from anon, authenticated;

create or replace function public.get_ble_key(p_device_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
  k text;
begin
  select * into d from public.devices where id = p_device_id;
  if not found or not public.is_home_manager(d.home_id) or not public.can_use_device(d.id) then
    raise exception 'Réservé au propriétaire ou à un administrateur';
  end if;
  if d.security_validated_at is null then
    raise exception 'Commande bloquée : appareil sensible non validé';
  end if;
  select lock_data into k from public.device_ble_keys where device_id = d.id;
  if k is null then
    raise exception 'Clé Bluetooth pas encore reçue : vérifiez que la passerelle Solea tourne';
  end if;
  perform public.log_event(d.home_id, 'ble_key_read', d.id, null, 'ok', '{}'::jsonb);
  return k;
end $$;
revoke execute on function public.get_ble_key(uuid) from public, anon;
grant execute on function public.get_ble_key(uuid) to authenticated;

create or replace function public.log_ble_action(p_device_id uuid, p_action text, p_ok boolean, p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  d public.devices;
begin
  select * into d from public.devices where id = p_device_id;
  if not found or not public.is_home_manager(d.home_id) then
    raise exception 'Réservé au propriétaire ou à un administrateur';
  end if;
  if p_action not in ('unlock', 'lock') then
    raise exception 'Action inconnue';
  end if;
  perform public.log_event(d.home_id, case when p_ok then 'command' else 'command_failed' end, d.id, null,
    case when p_ok then 'confirmed' else 'failed' end,
    jsonb_build_object('capability', 'lock_action', 'value', p_action, 'channel', 'bluetooth')
      || case when p_error is null then '{}'::jsonb else jsonb_build_object('error', left(p_error, 200)) end);
end $$;
revoke execute on function public.log_ble_action(uuid, text, boolean, text) from public, anon;
grant execute on function public.log_ble_action(uuid, text, boolean, text) to authenticated;
