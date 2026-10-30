\set ON_ERROR_STOP 1
\set QUIET 1
-- Contrôle d'accès : validation dédiée et codes d'accès (migration 20261030000000_solea_access_control.sql)
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', u, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  execute 'set role authenticated';
end $$;
create or replace function pg_temp.as_service() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'service_role', false);
  execute 'set role service_role';
end $$;
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'ÉCHEC: %', label; end if;
  raise notice 'OK: %', label;
end $$;
-- Insère une commande ; renvoie null si acceptée, sinon le message de refus.
create or replace function pg_temp.try_command(p_device uuid, p_key text) returns text language plpgsql as $$
begin
  insert into public.device_commands (home_id, device_id, capability_key, value, idempotency_key)
  values ('f0000000-0000-0000-0000-000000000001', p_device, p_key, '{"type":"one_time"}', gen_random_uuid()::text);
  return null;
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- Propriétaire O, administrateur A, membre M
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000f1','o@x.dz'),
 ('00000000-0000-0000-0000-0000000000f2','a@x.dz'),
 ('00000000-0000-0000-0000-0000000000f3','m@x.dz');
insert into public.homes (id, owner_id, name) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f1','Maison F');
insert into public.home_members (home_id, user_id, role) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f2','admin'),
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f3','member');
insert into public.devices (id, home_id, name, protocol, is_sensitive) values
 ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','Boîtier entrée','ble', true),
 ('f1000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000001','Lampe','wifi', false),
 ('f1000000-0000-0000-0000-000000000003','f0000000-0000-0000-0000-000000000001','Serrure HA','zigbee', true);
insert into public.device_capabilities (device_id, capability_key, type, metadata) values
 ('f1000000-0000-0000-0000-000000000001','access_code','string','{"kind":"access_code"}'),
 ('f1000000-0000-0000-0000-000000000002','switch','boolean','{}'),
 ('f1000000-0000-0000-0000-000000000003','lock','boolean','{}');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') = 'Commande bloquée : appareil sensible non validé', 'serrure : bloquée par défaut, même pour le propriétaire');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
do $$ begin
  perform public.set_device_security('f1000000-0000-0000-0000-000000000001', true);
  raise exception 'ÉCHEC: un administrateur valide un appareil de sécurité';
exception when raise_exception then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: seule la ou le propriétaire valide un appareil de sécurité';
end $$;
do $$ begin
  update public.devices set security_validated_at = now() where id = 'f1000000-0000-0000-0000-000000000001';
  raise exception 'ÉCHEC: validation écrite directement';
exception when insufficient_privilege then raise notice 'OK: la validation ne s''écrit pas directement';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin
  perform public.set_device_security('f1000000-0000-0000-0000-000000000002', true);
  raise exception 'ÉCHEC: validation d''un appareil ordinaire';
exception when raise_exception then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: validation réservée aux appareils de sécurité';
end $$;
do $$ begin
  perform public.set_device_security('f1000000-0000-0000-0000-000000000003', true);
  raise exception 'ÉCHEC: serrure sans codes d''accès activée';
exception when raise_exception then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: les autres appareils sensibles restent bloqués';
end $$;
select public.set_device_security('f1000000-0000-0000-0000-000000000001', true);
select pg_temp.check((select security_validated_by = '00000000-0000-0000-0000-0000000000f1' from public.devices where id = 'f1000000-0000-0000-0000-000000000001'), 'validation : auteur enregistré');
select pg_temp.check(exists (select 1 from public.event_logs where result = 'security_enabled' and actor_id = '00000000-0000-0000-0000-0000000000f1'), 'validation : journalisée avec l''acteur');
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') is null, 'serrure validée : le propriétaire commande');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') is null, 'serrure validée : l''administrateur commande');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') = 'Réservé au propriétaire ou à un administrateur', 'serrure validée : un simple membre est refusé');
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000002','switch') is null, 'appareil ordinaire : le membre commande toujours');

select pg_temp.as_service();
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') like '%uniquement à la main', 'serrure : automatisation (service) refusée');

-- La passerelle enregistre un code créé
insert into public.access_codes (home_id, device_id, kind, name, code, starts_at, created_by) values
 ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','one_time','Livreur','12345678', now(),'00000000-0000-0000-0000-0000000000f1');
do $$ begin
  insert into public.access_codes (home_id, device_id, kind, code, starts_at) values
   ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','one_time','12ab', now());
  raise exception 'ÉCHEC: code non numérique accepté';
exception when check_violation then raise notice 'OK: code d''accès numérique uniquement';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check((select count(*) = 1 from public.access_codes), 'codes : visibles par l''administrateur');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check((select count(*) = 0 from public.access_codes), 'codes : invisibles pour un simple membre');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin
  insert into public.access_codes (home_id, device_id, kind, code, starts_at) values
   ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','permanent','11112222', now());
  raise exception 'ÉCHEC: code écrit par l''application';
exception when insufficient_privilege then raise notice 'OK: seules les passerelles écrivent les codes';
end $$;

select public.set_device_security('f1000000-0000-0000-0000-000000000001', false);
select pg_temp.check(pg_temp.try_command('f1000000-0000-0000-0000-000000000001','access_code') = 'Commande bloquée : appareil sensible non validé', 'désactivation : la serrure est de nouveau bloquée');
reset role;
-- Nettoyage : les tests suivants comptent les comptes existants.
delete from public.homes where id = 'f0000000-0000-0000-0000-000000000001';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000f_';
