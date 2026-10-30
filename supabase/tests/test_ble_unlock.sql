\set ON_ERROR_STOP 1
\set QUIET 1
-- Ouverture Bluetooth : clé de la serrure (migration 20261030010000_solea_ble_unlock.sql)
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', u, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  execute 'set role authenticated';
end $$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'ÉCHEC: %', label; end if;
  raise notice 'OK: %', label;
end $$;
-- Renvoie la clé, ou le message de refus.
create or replace function pg_temp.try_key(p_device uuid) returns text language plpgsql as $$
begin
  return public.get_ble_key(p_device);
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- Propriétaire O, administrateur A, membre M
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000e1','o@y.dz'),
 ('00000000-0000-0000-0000-0000000000e2','a@y.dz'),
 ('00000000-0000-0000-0000-0000000000e3','m@y.dz');
insert into public.homes (id, owner_id, name) values
 ('e0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000e1','Maison E');
insert into public.home_members (home_id, user_id, role) values
 ('e0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000e2','admin'),
 ('e0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000e3','member');
insert into public.devices (id, home_id, name, protocol, is_sensitive) values
 ('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','Barrière','ble', true);
insert into public.device_capabilities (device_id, capability_key, type, metadata) values
 ('e1000000-0000-0000-0000-000000000001','access_code','string','{"kind":"access_code"}');
insert into public.device_ble_keys (device_id, home_id, lock_data) values
 ('e1000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','LOCKDATA');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
do $$ begin
  perform 1 from public.device_ble_keys;
  raise exception 'ÉCHEC: table des clés lisible directement';
exception when insufficient_privilege then raise notice 'OK: la table des clés Bluetooth ne se lit pas directement';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
select pg_temp.check(pg_temp.try_key('e1000000-0000-0000-0000-000000000001') = 'Commande bloquée : appareil sensible non validé', 'clé refusée tant que la serrure n''est pas activée');
select public.set_device_security('e1000000-0000-0000-0000-000000000001', true);
select pg_temp.check(pg_temp.try_key('e1000000-0000-0000-0000-000000000001') = 'LOCKDATA', 'propriétaire : clé Bluetooth reçue');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
select pg_temp.check(pg_temp.try_key('e1000000-0000-0000-0000-000000000001') = 'LOCKDATA', 'administrateur : clé Bluetooth reçue');
select public.log_ble_action('e1000000-0000-0000-0000-000000000001', 'unlock', true);

select pg_temp.as_user('00000000-0000-0000-0000-0000000000e3');
select pg_temp.check(pg_temp.try_key('e1000000-0000-0000-0000-000000000001') = 'Réservé au propriétaire ou à un administrateur', 'membre : clé refusée');
do $$ begin
  perform public.log_ble_action('e1000000-0000-0000-0000-000000000001', 'unlock', true);
  raise exception 'ÉCHEC: un membre écrit au journal';
exception when raise_exception then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: un membre ne journalise pas d''ouverture';
end $$;

reset role;
select pg_temp.check((select count(*) from public.event_logs where device_id = 'e1000000-0000-0000-0000-000000000001' and event_type = 'ble_key_read') = 2, 'chaque lecture de clé est journalisée');
select pg_temp.check((select details->>'channel' from public.event_logs where device_id = 'e1000000-0000-0000-0000-000000000001' and event_type = 'command') = 'bluetooth', 'ouverture Bluetooth journalisée');
-- Nettoyage : les tests suivants comptent les comptes existants.
delete from public.homes where id = 'e0000000-0000-0000-0000-000000000001';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000e_';
