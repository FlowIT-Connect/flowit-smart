\set ON_ERROR_STOP 1
\set QUIET 1
-- Limite de 5 appareils et déblocage après paiement (migration 20261101000000_solea_plans.sql)
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
-- Renvoie 'ok', ou le message de refus.
create or replace function pg_temp.try_add(p_home uuid, p_name text) returns text language plpgsql as $$
begin
  insert into public.devices (home_id, name, protocol) values (p_home, p_name, 'tuya');
  return 'ok';
exception when others then return sqlerrm;
end $$;
create or replace function pg_temp.try_sql(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- Propriétaire O (logement L), membre M, exploitant X, autre propriétaire Z (logement W)
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000a1','o@l.dz'),
 ('00000000-0000-0000-0000-0000000000a2','m@l.dz'),
 ('00000000-0000-0000-0000-0000000000a3','x@solea.dz'),
 ('00000000-0000-0000-0000-0000000000a4','z@w.dz');
insert into public.homes (id, owner_id, name) values
 ('a0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Logement L'),
 ('a0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000a4','Logement W');
insert into public.home_members (home_id, user_id, role) values
 ('a0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2','member');
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000a3');

-- La passerelle ajoute 5 appareils, le 6e est refusé.
select pg_temp.as_service();
select pg_temp.check((select bool_and(pg_temp.try_add('a0000000-0000-0000-0000-000000000001', 'App ' || i) = 'ok') from generate_series(1, 5) i), '5 appareils gratuits acceptés');
select pg_temp.check(pg_temp.try_add('a0000000-0000-0000-0000-000000000001', 'App 6') like 'LIMITE_APPAREILS%', '6e appareil refusé (LIMITE_APPAREILS)');
select pg_temp.check(pg_temp.try_add('a0000000-0000-0000-0000-000000000002', 'Autre') = 'ok', 'la limite ne touche pas un autre logement');
select pg_temp.check(pg_temp.try_sql($q$insert into public.home_plans (home_id, device_limit, waiting_devices) values ('a0000000-0000-0000-0000-000000000001', 5, 1) on conflict (home_id) do update set waiting_devices = 1$q$) = 'ok', 'la passerelle note 1 appareil en attente');

-- Le propriétaire voit 5/5 et ne peut plus demander d'ajout.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.check((select device_count = 5 and device_limit = 5 and not pending_request from public.get_home_plan('a0000000-0000-0000-0000-000000000001')), 'compteur 5/5');
select pg_temp.check(pg_temp.try_sql($q$select public.request_pairing('a0000000-0000-0000-0000-000000000001', 'scan')$q$) like 'LIMITE_APPAREILS%', 'ajout depuis l''app refusé à 5/5');
select pg_temp.check(pg_temp.try_sql($q$insert into public.home_plans (home_id, device_limit) values ('a0000000-0000-0000-0000-000000000001', 100)$q$) like 'permission denied%', 'le résident ne peut pas se débloquer lui-même');
select pg_temp.check(pg_temp.try_sql('select * from public.admin_list_upgrades()') = 'Réservé à l''exploitant Solea', 'page Paiements interdite au résident');
select pg_temp.check(not public.is_platform_admin(), 'le résident n''est pas exploitant');
create temp table t_req as select public.request_upgrade('a0000000-0000-0000-0000-000000000001', 'Je veux 10 appareils') as id;
select pg_temp.check((select pending_request from public.get_home_plan('a0000000-0000-0000-0000-000000000001')), 'demande de déblocage envoyée');
select pg_temp.check(public.request_upgrade('a0000000-0000-0000-0000-000000000001') = (select id from t_req), 'une seule demande en attente par logement');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.check((select device_limit = 5 from public.get_home_plan('a0000000-0000-0000-0000-000000000001')), 'un membre voit le compteur');
select pg_temp.check(pg_temp.try_sql($q$select public.request_upgrade('a0000000-0000-0000-0000-000000000001')$q$) = 'Réservé au propriétaire ou à un administrateur', 'un simple membre ne demande pas le déblocage');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a4');
select pg_temp.check(pg_temp.try_sql($q$select * from public.get_home_plan('a0000000-0000-0000-0000-000000000001')$q$) = 'Accès refusé', 'compteur d''un autre logement refusé');

-- L'exploitant confirme le paiement : 10 appareils pendant 1 mois.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.check(public.is_platform_admin(), 'exploitant reconnu');
select pg_temp.check((select count(*) = 1 and bool_and(owner_email = 'o@l.dz' and device_count = 5 and status = 'pending') from public.admin_list_upgrades()), 'l''exploitant voit la demande et l''e-mail du propriétaire');
select pg_temp.check(pg_temp.try_sql($q$select public.admin_decide_upgrade((select request_id from public.admin_list_upgrades() limit 1), true, 3, 1)$q$) = 'Nombre d''appareils : entre 6 et 1000', 'limite trop basse refusée');
select public.admin_decide_upgrade((select request_id from public.admin_list_upgrades() limit 1), true, 10, 1);
select pg_temp.check(pg_temp.try_sql($q$select public.admin_decide_upgrade((select request_id from public.admin_list_upgrades() limit 1), true, 10, 1)$q$) = 'Demande introuvable ou déjà traitée', 'une demande ne se traite qu''une fois');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.check((select device_limit = 10 and paid_until > now() + interval '27 days' and not pending_request from public.get_home_plan('a0000000-0000-0000-0000-000000000001')), 'logement débloqué : 10 appareils pendant 1 mois');
select pg_temp.as_service();
select pg_temp.check(pg_temp.try_add('a0000000-0000-0000-0000-000000000001', 'App 6') = 'ok', 'l''appareil en attente est accepté après paiement');

-- Fin de l'abonnement : les appareils restent, les nouveaux ajouts sont bloqués.
update public.home_plans set paid_until = now() - interval '1 day' where home_id = 'a0000000-0000-0000-0000-000000000001';
select pg_temp.check(pg_temp.try_add('a0000000-0000-0000-0000-000000000001', 'App 7') like 'LIMITE_APPAREILS : 5 %', 'abonnement expiré : retour à 5');
select pg_temp.check((select count(*) = 6 from public.devices where home_id = 'a0000000-0000-0000-0000-000000000001'), 'les appareils déjà présents restent');

-- Renouvellement sans date de fin.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select public.request_upgrade('a0000000-0000-0000-0000-000000000001');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select public.admin_decide_upgrade((select request_id from public.admin_list_upgrades() where status = 'pending'), true, 20, null);
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.check((select device_limit = 20 and paid_until is null from public.get_home_plan('a0000000-0000-0000-0000-000000000001')), 'déblocage sans date de fin');

-- Refus d'une demande.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a4');
select public.request_upgrade('a0000000-0000-0000-0000-000000000002');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select public.admin_decide_upgrade((select request_id from public.admin_list_upgrades() where status = 'pending'), false);
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a4');
select pg_temp.check((select device_limit = 5 and not pending_request from public.get_home_plan('a0000000-0000-0000-0000-000000000002')), 'demande refusée : toujours 5');
reset role;
