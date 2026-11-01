\set ON_ERROR_STOP 1
\set QUIET 1
-- Chauffage et climatisation par pièce (migration 20261110000000_solea_climate.sql)
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
create or replace function pg_temp.fails(q text) returns boolean language plpgsql as $$
begin
  execute q;
  return false;
exception when others then
  return true;
end $$;
grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000ca','o@c.dz'),
 ('00000000-0000-0000-0000-0000000000cb','m@c.dz'),
 ('00000000-0000-0000-0000-0000000000cc','x@c.dz');
insert into public.homes (id, owner_id, name) values
 ('ca000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000ca','Maison C'),
 ('ca000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000cc','Autre');
insert into public.home_members (home_id, user_id, role) values
 ('ca000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000cb','member');
insert into public.rooms (id, home_id, name, icon) values
 ('ca200000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Salon','sofa'),
 ('ca200000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Ailleurs','sofa');
insert into public.devices (id, home_id, room_id, name, protocol, availability, state) values
 ('ca100000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','ca200000-0000-0000-0000-000000000001','Clim','tuya','available','{}'),
 ('ca100000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','ca200000-0000-0000-0000-000000000002','Clim voisin','tuya','available','{}');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000ca');
insert into public.climate_settings (home_id) values ('ca000000-0000-0000-0000-000000000001');
select pg_temp.check((select (presets -> 'comfort' ->> 'heat')::int = 21 from public.climate_settings where home_id = 'ca000000-0000-0000-0000-000000000001'), 'ambiances par défaut');
select pg_temp.check(pg_temp.fails($$update public.climate_settings set presets = '{"comfort":{"heat":60}}' where home_id = 'ca000000-0000-0000-0000-000000000001'$$), 'température hors limites refusée');
insert into public.climate_zones (home_id, room_id, devices, schedule) values
 ('ca000000-0000-0000-0000-000000000001','ca200000-0000-0000-0000-000000000001','["ca100000-0000-0000-0000-000000000001"]',
  '[{"days":[1,2,3,4,5],"at":"06:30","preset":"comfort"},{"days":[1,2,3,4,5,6,7],"at":"22:30","preset":"sleep"}]');
select pg_temp.check(pg_temp.fails($$insert into public.climate_zones (home_id, room_id) values ('ca000000-0000-0000-0000-000000000001','ca200000-0000-0000-0000-000000000002')$$), 'pièce d''un autre logement refusée');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set devices = '["ca100000-0000-0000-0000-000000000002"]' where room_id = 'ca200000-0000-0000-0000-000000000001'$$), 'appareil d''un autre logement refusé');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set schedule = '[{"days":[8],"at":"06:30","preset":"comfort"}]' where room_id = 'ca200000-0000-0000-0000-000000000001'$$), 'jour invalide refusé');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set schedule = '[{"days":[1],"at":"25:00","preset":"comfort"}]' where room_id = 'ca200000-0000-0000-0000-000000000001'$$), 'heure invalide refusée');

-- Membre : voit, choisit une ambiance, mais ne règle pas le programme.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000cb');
select pg_temp.check((select count(*) = 1 from public.climate_zones), 'membre : voit la zone');
update public.climate_zones set schedule = '[]' where room_id = 'ca200000-0000-0000-0000-000000000001';
select pg_temp.check((select jsonb_array_length(schedule) = 2 from public.climate_zones), 'membre : programme inchangé (RLS)');
select public.set_climate_preset('ca000000-0000-0000-0000-000000000001', null, 'away', now() + interval '2 days');
select pg_temp.check((select home_preset = 'away' and home_preset_until is not null from public.climate_settings), 'membre : Absence pour toute la maison');
select public.set_climate_preset('ca000000-0000-0000-0000-000000000001', 'ca200000-0000-0000-0000-000000000001', 'comfort');
select pg_temp.check((select preset_override = 'comfort' from public.climate_zones), 'membre : Confort dans le salon');
select public.set_climate_preset('ca000000-0000-0000-0000-000000000001', null, null);
select pg_temp.check((select home_preset is null and home_preset_until is null from public.climate_settings), 'retour au programme');
select pg_temp.check(pg_temp.fails($$select public.set_climate_preset('ca000000-0000-0000-0000-000000000001', null, 'party')$$), 'ambiance inconnue refusée');

-- Étranger : rien.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000cc');
select pg_temp.check((select count(*) = 0 from public.climate_zones), 'étranger : aucune zone visible');
select pg_temp.check(pg_temp.fails($$select public.set_climate_preset('ca000000-0000-0000-0000-000000000001', null, 'comfort')$$), 'étranger : ambiance refusée');

-- Appareil supprimé : la passerelle peut encore écrire l'ambiance en cours.
reset role;
delete from public.devices where id = 'ca100000-0000-0000-0000-000000000001';
update public.climate_zones set active_preset = 'comfort', active_target = 21 where room_id = 'ca200000-0000-0000-0000-000000000001';
select pg_temp.check((select active_preset = 'comfort' from public.climate_zones), 'passerelle : ambiance en cours enregistrée malgré un appareil supprimé');

-- Fenêtre ouverte (migration 20261111000000_solea_climate_windows.sql)
insert into public.devices (id, home_id, room_id, name, protocol, availability, state) values
 ('ca100000-0000-0000-0000-000000000003','ca000000-0000-0000-0000-000000000001','ca200000-0000-0000-0000-000000000001','Fenêtre salon','zigbee','available','{"contact":true}');
update public.climate_zones set devices = '[]', windows = '["ca100000-0000-0000-0000-000000000003"]', window_delay = 5 where room_id = 'ca200000-0000-0000-0000-000000000001';
select pg_temp.check((select window_delay = 5 and jsonb_array_length(windows) = 1 and not active_window from public.climate_zones), 'capteur de fenêtre associé à la pièce');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set windows = '["ca100000-0000-0000-0000-000000000002"]'$$), 'capteur d''un autre logement refusé');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set window_delay = 90$$), 'délai hors limites refusé');

-- Températures intelligentes (migration 20261112000000_solea_climate_smart.sql)
select pg_temp.check((select preheat and preheat_max = 120 from public.climate_settings where home_id = 'ca000000-0000-0000-0000-000000000001'), 'préchauffage actif par défaut, 2 h au plus');
update public.climate_settings set preheat = false, preheat_max = 60 where home_id = 'ca000000-0000-0000-0000-000000000001';
select pg_temp.check((select not preheat and preheat_max = 60 from public.climate_settings where home_id = 'ca000000-0000-0000-0000-000000000001'), 'préchauffage réglé');
select pg_temp.check(pg_temp.fails($$update public.climate_settings set preheat_max = 600$$), 'avance hors limites refusée');

-- Préchauffage qui apprend (migration 20261113000000_solea_climate_learning.sql)
update public.climate_zones set heat_rate = 11.4 where room_id = 'ca200000-0000-0000-0000-000000000001';
select pg_temp.check((select heat_rate = 11.4 and cool_rate is null from public.climate_zones where room_id = 'ca200000-0000-0000-0000-000000000001'), 'vitesse de chauffe enregistrée');
select pg_temp.check(pg_temp.fails($$update public.climate_zones set cool_rate = 500$$), 'vitesse hors limites refusée');
