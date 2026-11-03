\set ON_ERROR_STOP 1
\set QUIET 1
-- Ordre et suppression des pièces (migration 20261117000000_solea_room_layout.sql)
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
create or replace function pg_temp.try_sql(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

begin;
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000008b1','o@r.dz'),
 ('00000000-0000-0000-0000-0000000008b2','m@r.dz');
insert into public.homes (id, owner_id, name) values
 ('80b00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000008b1','Villa');
insert into public.home_members (home_id, user_id, role) values
 ('80b00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000008b2','member')
on conflict do nothing;
insert into public.rooms (id, home_id, name) values
 ('85b00000-0000-0000-0000-000000000001','80b00000-0000-0000-0000-000000000001','Salon'),
 ('85b00000-0000-0000-0000-000000000002','80b00000-0000-0000-0000-000000000001','Cuisine');
insert into public.devices (id, home_id, room_id, name, protocol) values
 ('82b00000-0000-0000-0000-000000000001','80b00000-0000-0000-0000-000000000001','85b00000-0000-0000-0000-000000000001','Lampe','tuya');

-- Le membre peut enregistrer son propre ordre des pièces.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008b2');
insert into public.device_layouts (user_id, home_id, section, item_ids) values
 ('00000000-0000-0000-0000-0000000008b2','80b00000-0000-0000-0000-000000000001','rooms',
  array['85b00000-0000-0000-0000-000000000002','85b00000-0000-0000-0000-000000000001']::uuid[]),
 ('00000000-0000-0000-0000-0000000008b2','80b00000-0000-0000-0000-000000000001','room:85b00000-0000-0000-0000-000000000001',
  array['82b00000-0000-0000-0000-000000000001']::uuid[]);
select pg_temp.check((select count(*) from public.device_layouts where home_id = '80b00000-0000-0000-0000-000000000001') = 2, 'ordre des pièces enregistré par le membre');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_layouts (user_id, home_id, section, item_ids) values ('00000000-0000-0000-0000-0000000008b2','80b00000-0000-0000-0000-000000000001','pieces','{}')$q$) <> 'ok', 'section inconnue refusée');

-- Le membre ne peut pas supprimer une pièce.
delete from public.rooms where id = '85b00000-0000-0000-0000-000000000001';
reset role;
select pg_temp.check(exists (select 1 from public.rooms where id = '85b00000-0000-0000-0000-000000000001'), 'membre : suppression de pièce sans effet');

-- Le propriétaire la supprime : l'appareil est gardé sans pièce, les ordres sont nettoyés.
select pg_temp.as_user('00000000-0000-0000-0000-0000000008b1');
delete from public.rooms where id = '85b00000-0000-0000-0000-000000000001';
reset role;
select pg_temp.check(not exists (select 1 from public.rooms where id = '85b00000-0000-0000-0000-000000000001'), 'propriétaire : pièce supprimée');
select pg_temp.check((select room_id from public.devices where id = '82b00000-0000-0000-0000-000000000001') is null, 'appareil conservé, sans pièce');
select pg_temp.check(not exists (select 1 from public.device_layouts where section = 'room:85b00000-0000-0000-0000-000000000001'), 'ordre de la pièce effacé');
select pg_temp.check((select item_ids from public.device_layouts where home_id = '80b00000-0000-0000-0000-000000000001' and section = 'rooms') = array['85b00000-0000-0000-0000-000000000002']::uuid[], 'pièce retirée de l''ordre des pièces');
rollback;
