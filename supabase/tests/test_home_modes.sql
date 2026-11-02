\set ON_ERROR_STOP 1
\set QUIET 1
-- Modes Été / Hiver / Vacances (migration 20261108000000_solea_home_modes.sql)
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
 ('00000000-0000-0000-0000-00000000009f','o@m.dz'),
 ('00000000-0000-0000-0000-0000000000af','m@m.dz'),
 ('00000000-0000-0000-0000-0000000000bf','x@m.dz');
insert into public.homes (id, owner_id, name) values
 ('9f000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000009f','Maison M'),
 ('9f000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000bf','Maison X');
insert into public.home_members (home_id, user_id, role) values
 ('9f000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000af','member');
insert into public.devices (id, home_id, name, protocol) values
 ('9f100000-0000-0000-0000-000000000001','9f000000-0000-0000-0000-000000000001','Salon','tuya'),
 ('9f100000-0000-0000-0000-000000000002','9f000000-0000-0000-0000-000000000002','Autre','tuya');

select pg_temp.as_user('00000000-0000-0000-0000-00000000009f');
insert into public.home_modes (home_id, season, vacation, vacation_from, vacation_to, presence_simulation, simulation_devices)
values ('9f000000-0000-0000-0000-000000000001', 'summer', true, now(), now() + interval '10 days', true, '["9f100000-0000-0000-0000-000000000001"]');
select pg_temp.check((select season = 'summer' and vacation and updated_by = auth.uid() from public.home_modes), 'propriétaire : été + vacances avec simulation');
do $$ begin
  update public.home_modes set simulation_devices = '["9f100000-0000-0000-0000-000000000002"]';
  raise exception 'ÉCHEC: appareil d''un autre logement accepté';
exception when raise_exception then raise notice 'OK: simulation limitée aux appareils du logement';
end $$;
do $$ begin
  update public.home_modes set vacation_to = vacation_from - interval '1 day';
  raise exception 'ÉCHEC: retour avant le départ accepté';
exception when check_violation then raise notice 'OK: retour après le départ';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000af');
select pg_temp.check((select count(*) = 1 from public.home_modes), 'membre : voit les modes');
update public.home_modes set season = 'winter';
select pg_temp.check((select season = 'summer' from public.home_modes), 'membre : ne change pas les modes');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000bf');
select pg_temp.check((select count(*) = 0 from public.home_modes), 'étranger : ne voit rien');
reset role;
