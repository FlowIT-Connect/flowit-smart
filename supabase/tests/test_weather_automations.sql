\set ON_ERROR_STOP 1
\set QUIET 1
-- Automatisations météo (migration 20261107000000_solea_weather_automations.sql)
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
grant execute on all functions in schema pg_temp to public;

insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-00000000009d','o@w.dz'),
 ('00000000-0000-0000-0000-00000000009e','x@w.dz');
insert into public.homes (id, owner_id, name) values
 ('9d000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000009d','Maison W');

select pg_temp.as_user('00000000-0000-0000-0000-00000000009d');
update public.homes set latitude = 36.75380, longitude = 3.05880, location_name = 'Alger' where id = '9d000000-0000-0000-0000-000000000001';
select pg_temp.check((select latitude = 36.7538 from public.homes where id = '9d000000-0000-0000-0000-000000000001'), 'position du logement enregistrée');
do $$ begin
  update public.homes set latitude = 120 where id = '9d000000-0000-0000-0000-000000000001';
  raise exception 'ÉCHEC: latitude invalide acceptée';
exception when check_violation then raise notice 'OK: latitude contrôlée';
end $$;

insert into public.automations (id, home_id, name, trigger, exceptions, follow_up, priority, actions) values
 ('9d100000-0000-0000-0000-000000000001','9d000000-0000-0000-0000-000000000001','Vents forts',
  '{"type":"weather","metric":"wind_speed","op":"gt","value":80,"for_minutes":2}',
  '[{"type":"device_state","device_id":"x","capability_key":"contact","op":"eq","value":false}]',
  '{"after_minutes":30,"actions":[{"device_id":"x","capability_key":"cover_position","value":100}],"conditions":[{"type":"weather","metric":"wind_speed","op":"lt","value":50}]}',
  'security', '[{"device_id":"x","capability_key":"cover_position","value":0}]');
select pg_temp.check((select priority = 'security' and follow_up ->> 'after_minutes' = '30' from public.automations
                      where id = '9d100000-0000-0000-0000-000000000001'), 'règle vent fort avec SAUF SI et PUIS');
do $$ begin
  insert into public.automations (home_id, name, trigger, follow_up, actions) values
   ('9d000000-0000-0000-0000-000000000001','Mauvais','{"type":"manual"}','{"after_minutes":5000,"actions":[{}]}','[{}]');
  raise exception 'ÉCHEC: délai PUIS hors limites accepté';
exception when check_violation then raise notice 'OK: délai PUIS contrôlé';
end $$;
do $$ begin
  insert into public.automations (home_id, name, trigger, actions) values
   ('9d000000-0000-0000-0000-000000000001','Mauvais','{"type":"inconnu"}','[{}]');
  raise exception 'ÉCHEC: déclencheur inconnu accepté';
exception when check_violation then raise notice 'OK: type de déclencheur contrôlé';
end $$;
do $$ begin
  insert into public.automation_runs (home_id, status) values ('9d000000-0000-0000-0000-000000000001', 'success');
  raise exception 'ÉCHEC: le client écrit l''historique';
exception when insufficient_privilege then raise notice 'OK: historique écrit par la passerelle seule';
end $$;

reset role;
set role service_role;
insert into public.automation_runs (home_id, automation_id, name, status, reason) values
 ('9d000000-0000-0000-0000-000000000001','9d100000-0000-0000-0000-000000000001','Vents forts','success','vent 92 km/h');
insert into public.weather_readings (home_id, wind_speed, wind_gust, temperature, is_day) values
 ('9d000000-0000-0000-0000-000000000001', 92, 110, 18.5, true);
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000009d');
select pg_temp.check((select count(*) = 1 from public.automation_runs) and (select count(*) = 1 from public.weather_readings),
                     'le membre lit l''historique et la météo');
select pg_temp.as_user('00000000-0000-0000-0000-00000000009e');
select pg_temp.check((select count(*) = 0 from public.automation_runs) and (select count(*) = 0 from public.weather_readings),
                     'un étranger ne lit rien');
reset role;
