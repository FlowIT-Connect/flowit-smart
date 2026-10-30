\set ON_ERROR_STOP 1
\set QUIET 1
-- Passerelle unique et attribution des appareils (migration 20261102000000_solea_platform_devices.sql)
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
create or replace function pg_temp.try_sql(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- Exploitant X ; résidents R1 (logement H1, ancienne passerelle) et R2 (logement H2, neuf)
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000c1','x@solea.dz'),
 ('00000000-0000-0000-0000-0000000000c2','r1@h.dz'),
 ('00000000-0000-0000-0000-0000000000c3','r2@h.dz');
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000c1');
insert into public.homes (id, owner_id, name) values
 ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c2','Appartement A1'),
 ('c0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000c3','Appartement B2');
insert into public.integrations (id, home_id, provider, status) values
 ('c1000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','tuya','connected');
insert into public.devices (id, home_id, integration_id, name, protocol) values
 ('c2000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','Disjoncteur','tuya');
insert into public.device_bindings (device_id, integration_id, external_id) values
 ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','tuya:old');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c3');
select pg_temp.check((select not managed from public.get_home_plan('c0000000-0000-0000-0000-000000000002')), 'avant la plateforme : ajout par le résident');
select pg_temp.check(pg_temp.try_sql($q$select public.platform_sync_devices('[]')$q$) like 'permission denied%', 'un résident ne joue pas la passerelle');
select pg_temp.check(pg_temp.try_sql('select * from public.admin_list_platform_devices()') = 'Réservé à l''exploitant Solea', 'liste des appareils réservée à l''exploitant');
select pg_temp.check(pg_temp.try_sql('select * from public.platform_devices') like 'permission denied%', 'table plateforme illisible pour un résident');

-- La passerelle inscrit l'inventaire du compte installateur.
select pg_temp.as_service();
create temp table t_assign as select * from public.platform_sync_devices(
  '[{"external_id":"tuya:old","name":"Disjoncteur","vendor":"Tuya"},{"external_id":"tuya:new1","name":"Prise 1"},{"external_id":"tuya:new2","name":"Prise 2"}]');
select pg_temp.check((select count(*) = 1 and bool_and(home_id = 'c0000000-0000-0000-0000-000000000001') from t_assign), 'appareil déjà installé : rattaché à son logement');
select pg_temp.check((select count(*) = 3 from public.platform_devices), 'inventaire inscrit');
select public.platform_sync_devices('[{"external_id":"tuya:new1","name":"Prise salon"}]');
select pg_temp.check((select name = 'Prise salon' from public.platform_devices where external_id = 'tuya:new1'), 'nom mis à jour à la synchronisation suivante');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c3');
select pg_temp.check((select managed from public.get_home_plan('c0000000-0000-0000-0000-000000000002')), 'plateforme en service : logement neuf équipé par l''installateur');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.check((select not managed from public.get_home_plan('c0000000-0000-0000-0000-000000000001')), 'logement avec sa propre passerelle : pas géré');

-- L'exploitant attribue les appareils.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.check((select count(*) = 2 from public.admin_list_platform_devices() where home_id is null), 'deux appareils à attribuer');
select pg_temp.check((select bool_and(installed) from public.admin_list_platform_devices() where external_id = 'tuya:old'), 'appareil déjà installé reconnu');
select pg_temp.check((select count(*) = 1 and bool_and(owner_email = 'r2@h.dz') from public.admin_search_homes('r2@')), 'recherche d''un logement par e-mail');
select pg_temp.check((select count(*) = 2 from public.admin_search_homes('appartement')), 'recherche par nom');
select public.admin_assign_device('tuya:new1', 'c0000000-0000-0000-0000-000000000002');
select pg_temp.check((select home_id = 'c0000000-0000-0000-0000-000000000002' and not installed from public.admin_list_platform_devices() where external_id = 'tuya:new1'), 'attribué, en attente de la passerelle');
select pg_temp.check(pg_temp.try_sql($q$select public.admin_assign_device('tuya:inconnu', null)$q$) = 'Appareil inconnu', 'appareil inconnu refusé');

-- Limite : 5 places, 4 appareils présents + 1 attribué en attente = plein.
reset role;
insert into public.devices (home_id, name, protocol) select 'c0000000-0000-0000-0000-000000000002', 'D' || i, 'tuya' from generate_series(1, 4) i;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.check(pg_temp.try_sql($q$select public.admin_assign_device('tuya:new2', 'c0000000-0000-0000-0000-000000000002')$q$) like 'LIMITE_APPAREILS%', 'logement plein : attribution refusée');

-- Changement de logement (vers un logement avec de la place) : l'appareil disparaît de l'ancien.
reset role;
delete from public.devices where home_id = 'c0000000-0000-0000-0000-000000000002';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select public.admin_assign_device('tuya:old', 'c0000000-0000-0000-0000-000000000002');
reset role;
select pg_temp.check(not exists (select 1 from public.devices where id = 'c2000000-0000-0000-0000-000000000001'), 'ancien logement : appareil retiré');
select pg_temp.check((select home_id = 'c0000000-0000-0000-0000-000000000002' from public.platform_devices where external_id = 'tuya:old'), 'nouveau logement enregistré');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select public.admin_assign_device('tuya:new1', null);
select pg_temp.check((select home_id is null from public.admin_list_platform_devices() where external_id = 'tuya:new1'), 'appareil retiré : de nouveau à attribuer');
reset role;
