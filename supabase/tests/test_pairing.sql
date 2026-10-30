\set ON_ERROR_STOP 1
\set QUIET 1
-- Ajout d'appareils depuis l'application (migration 20261031000000_solea_pairing.sql)
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
-- Renvoie 'ok', ou le message de refus.
create or replace function pg_temp.try_pair(p_home uuid, p_kind text, p_room uuid default null, p_data text default null) returns text language plpgsql as $$
begin
  perform public.request_pairing(p_home, p_kind, 'Entrée', p_room, p_data);
  return 'ok';
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- Propriétaire O, administrateur A, membre M ; maison P et une autre maison Q
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000f1','o@p.dz'),
 ('00000000-0000-0000-0000-0000000000f2','a@p.dz'),
 ('00000000-0000-0000-0000-0000000000f3','m@p.dz');
insert into public.homes (id, owner_id, name) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f1','Maison P'),
 ('f0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000f1','Maison Q');
insert into public.home_members (home_id, user_id, role) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f2','admin'),
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f3','member');
insert into public.rooms (id, home_id, name) values
 ('f2000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','Hall'),
 ('f2000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000002','Garage Q');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'ttlock_lock', 'f2000000-0000-0000-0000-000000000001', repeat('L', 64)) = 'ok', 'propriétaire : demande d''ajout de serrure');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'ttlock_lock') = 'Clé de la serrure manquante', 'serrure sans clé refusée');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan', 'f2000000-0000-0000-0000-000000000002') = 'La pièce n''appartient pas à cette maison', 'pièce d''une autre maison refusée');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'zigbee') = 'Type d''ajout inconnu', 'type inconnu refusé');
do $$ begin
  perform lock_data from public.pairing_requests;
  raise exception 'ÉCHEC: clé de serrure lisible depuis l''application';
exception when insufficient_privilege then raise notice 'OK: la clé de la serrure ne se lit pas depuis l''application';
end $$;
select pg_temp.check((select count(*) from public.pairing_requests where home_id = 'f0000000-0000-0000-0000-000000000001' and status = 'pending') = 1, 'propriétaire : suit l''état de sa demande');
do $$ begin
  insert into public.pairing_requests (home_id, kind) values ('f0000000-0000-0000-0000-000000000001', 'scan');
  raise exception 'ÉCHEC: insertion directe acceptée';
exception when insufficient_privilege then raise notice 'OK: pas d''insertion directe (seulement request_pairing)';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan', 'f2000000-0000-0000-0000-000000000001') = 'ok', 'administrateur : demande d''ajout Smart Life');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan') = 'Réservé au propriétaire ou à un administrateur', 'membre : ajout refusé');
select pg_temp.check((select count(*) from public.pairing_requests) = 0, 'membre : ne voit pas les demandes');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
select pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan');
select pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan');
select pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan');
select pg_temp.check(pg_temp.try_pair('f0000000-0000-0000-0000-000000000001', 'scan') like 'Trop d''ajouts en cours%', 'au plus 5 ajouts en cours par maison');

reset role;
select pg_temp.check((select count(*) from public.event_logs where home_id = 'f0000000-0000-0000-0000-000000000001' and result = 'pairing_requested') = 5, 'chaque demande est journalisée');
select pg_temp.check((select details::text from public.event_logs where result = 'pairing_requested' limit 1) not like '%LLLL%', 'la clé n''apparaît pas au journal');
-- Nettoyage : les tests suivants comptent les comptes existants.
delete from public.homes where id::text like 'f0000000-0000-0000-0000-00000000000_';
delete from auth.users where id::text like '00000000-0000-0000-0000-0000000000f_';
