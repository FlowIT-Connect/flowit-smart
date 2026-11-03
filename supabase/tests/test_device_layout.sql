\set ON_ERROR_STOP 1
\set QUIET 1
-- Organisation, suppression et QR codes (migration 20261116000000_solea_device_layout.sql)
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
-- Propriétaire O (logement H), membre M, voisin V (logement H2), exploitant X.
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000007a1','o@h.dz'),
 ('00000000-0000-0000-0000-0000000007a2','m@h.dz'),
 ('00000000-0000-0000-0000-0000000007a3','v@h.dz'),
 ('00000000-0000-0000-0000-0000000007a4','x@solea.dz');
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000007a4');
insert into public.homes (id, owner_id, name) values
 ('70a00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000007a1','Villa'),
 ('70a00000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000007a3','Voisin');
insert into public.home_members (home_id, user_id, role) values
 ('70a00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000007a2','member')
on conflict do nothing;
insert into public.rooms (id, home_id, name) values
 ('75a00000-0000-0000-0000-000000000001','70a00000-0000-0000-0000-000000000001','Salon');
insert into public.integrations (id, home_id, provider, status) values
 ('71a00000-0000-0000-0000-000000000001','70a00000-0000-0000-0000-000000000001','tuya','connected');
insert into public.devices (id, home_id, integration_id, room_id, name, protocol, is_pinned) values
 ('72a00000-0000-0000-0000-000000000001','70a00000-0000-0000-0000-000000000001','71a00000-0000-0000-0000-000000000001','75a00000-0000-0000-0000-000000000001','Lampe','tuya', true),
 ('72a00000-0000-0000-0000-000000000002','70a00000-0000-0000-0000-000000000001','71a00000-0000-0000-0000-000000000001','75a00000-0000-0000-0000-000000000001','Prise','tuya', false),
 ('72a00000-0000-0000-0000-000000000003','70a00000-0000-0000-0000-000000000001','71a00000-0000-0000-0000-000000000001',null,'Disjoncteur','tuya', false);
insert into public.device_bindings (device_id, integration_id, external_id) values
 ('72a00000-0000-0000-0000-000000000001','71a00000-0000-0000-0000-000000000001','tuya:lampe'),
 ('72a00000-0000-0000-0000-000000000002','71a00000-0000-0000-0000-000000000001','tuya:prise'),
 ('72a00000-0000-0000-0000-000000000003','71a00000-0000-0000-0000-000000000001','tuya:disj');
insert into public.scenes (id, home_id, name) values ('73a00000-0000-0000-0000-000000000001','70a00000-0000-0000-0000-000000000001','Soir');
insert into public.scene_actions (scene_id, device_id, capability_key, value) values
 ('73a00000-0000-0000-0000-000000000001','72a00000-0000-0000-0000-000000000001','switch','true'),
 ('73a00000-0000-0000-0000-000000000001','72a00000-0000-0000-0000-000000000002','switch','true');
insert into public.automations (id, home_id, name, trigger, actions) values
 ('74a00000-0000-0000-0000-000000000001','70a00000-0000-0000-0000-000000000001','Coucher','{"type":"time","at":"22:00"}',
  '[{"device_id":"72a00000-0000-0000-0000-000000000001","capability_key":"switch","value":false}]'),
 ('74a00000-0000-0000-0000-000000000002','70a00000-0000-0000-0000-000000000001','Autre','{"type":"time","at":"07:00"}',
  '[{"device_id":"72a00000-0000-0000-0000-000000000002","capability_key":"switch","value":true}]');

-- ---------------------------------------------------------------- Ordre personnel
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
insert into public.device_layouts (user_id, home_id, section, item_ids) values
 ('00000000-0000-0000-0000-0000000007a2','70a00000-0000-0000-0000-000000000001','devices',
  '{72a00000-0000-0000-0000-000000000002,72a00000-0000-0000-0000-000000000001}');
select pg_temp.check((select item_ids[1] = '72a00000-0000-0000-0000-000000000002' from public.device_layouts where section = 'devices'), 'un membre enregistre son ordre');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_layouts (user_id, home_id, section) values
  ('00000000-0000-0000-0000-0000000007a1','70a00000-0000-0000-0000-000000000001','favorites')$q$) like '%row-level security%', 'pas d''ordre au nom d''un autre');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_layouts (user_id, home_id, section) values
  ('00000000-0000-0000-0000-0000000007a2','70a00000-0000-0000-0000-000000000002','favorites')$q$) like '%row-level security%', 'pas d''ordre dans un logement étranger');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_layouts (user_id, home_id, section) values
  ('00000000-0000-0000-0000-0000000007a2','70a00000-0000-0000-0000-000000000001','bidon')$q$) like '%check constraint%', 'section inconnue refusée');
update public.device_layouts set item_ids = '{72a00000-0000-0000-0000-000000000001}' where section = 'devices';
select pg_temp.check((select cardinality(item_ids) = 1 from public.device_layouts where section = 'devices'), 'ordre mis à jour');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
select pg_temp.check((select count(*) = 0 from public.device_layouts), 'l''ordre d''un membre reste privé');
insert into public.device_layouts (user_id, home_id, section, item_ids) values
 ('00000000-0000-0000-0000-0000000007a1','70a00000-0000-0000-0000-000000000001','room:d5000000-0000-0000-0000-000000000001',
  '{72a00000-0000-0000-0000-000000000002,72a00000-0000-0000-0000-000000000001}');

-- ---------------------------------------------------------------- Permissions de suppression
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
select pg_temp.check(pg_temp.try_sql($q$select public.remove_device('72a00000-0000-0000-0000-000000000001','home')$q$) like 'Réservé%', 'un simple membre ne retire rien');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a3');
select pg_temp.check(pg_temp.try_sql($q$select public.remove_device('72a00000-0000-0000-0000-000000000001','unlink')$q$) like 'Réservé%', 'un voisin ne touche pas aux appareils d''un autre logement');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
select pg_temp.check(pg_temp.try_sql($q$select public.remove_device('72a00000-0000-0000-0000-000000000001','tout')$q$) like 'Mode%', 'mode inconnu refusé');

-- ---------------------------------------------------------------- Retirer de ma résidence
create temp table t_res as select public.remove_device('72a00000-0000-0000-0000-000000000001','home') r;
select r from t_res;
select pg_temp.check((select (r->>'scenes')::int = 1 and (r->>'automations_paused')::int = 1 from t_res), 'scène nettoyée et automatisation mise en pause');
select pg_temp.check((select count(*) = 0 from public.devices where id = '72a00000-0000-0000-0000-000000000001'), 'appareil retiré invisible');
select pg_temp.check((select count(*) = 2 from public.devices), 'les autres appareils restent');
select pg_temp.check((select not enabled from public.automations where id = '74a00000-0000-0000-0000-000000000001'), 'automatisation concernée en pause');
select pg_temp.check((select enabled from public.automations where id = '74a00000-0000-0000-0000-000000000002'), 'autre automatisation intacte');
select pg_temp.check((select item_ids = '{72a00000-0000-0000-0000-000000000002}' from public.device_layouts where section like 'room:%'), 'retiré de l''ordre d''affichage');
select pg_temp.check((select count(*) = 1 and bool_and(name = 'Lampe') from public.list_removed_devices('70a00000-0000-0000-0000-000000000001')), 'liste des appareils retirés');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_commands (home_id, device_id, capability_key, value, idempotency_key)
  values ('70a00000-0000-0000-0000-000000000001','72a00000-0000-0000-0000-000000000001','switch','true', gen_random_uuid())$q$) <> 'ok', 'plus de commande vers un appareil retiré');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
select pg_temp.check((select count(*) = 0 from public.list_removed_devices('70a00000-0000-0000-0000-000000000001')), 'liste des retirés réservée aux gestionnaires');
reset role;
select pg_temp.check((select removed_at is not null and not is_pinned from public.devices where id = '72a00000-0000-0000-0000-000000000001'), 'appareil gardé en base, sorti des favoris');
select pg_temp.check((select count(*) = 1 from public.event_logs where event_type = 'device_removed'), 'retrait journalisé');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
select public.restore_device('72a00000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 1 from public.devices where id = '72a00000-0000-0000-0000-000000000001'), 'appareil remis');

-- ---------------------------------------------------------------- Dissocier définitivement
select pg_temp.check((select public.remove_device('72a00000-0000-0000-0000-000000000002','unlink') is not null), 'dissociation');
reset role;
select pg_temp.check((select count(*) = 0 from public.devices where id = '72a00000-0000-0000-0000-000000000002'), 'appareil supprimé');
select pg_temp.check((select count(*) = 1 from public.device_exclusions where external_id = 'tuya:prise'), 'exclusion inscrite pour la passerelle');
select pg_temp.check((select count(*) = 1 from public.event_logs where event_type = 'device_unlinked'), 'historique conservé');
-- Une ancienne passerelle le recrée : il est aussitôt retiré.
insert into public.devices (id, home_id, integration_id, name, protocol) values
 ('72a00000-0000-0000-0000-000000000009','70a00000-0000-0000-0000-000000000001','71a00000-0000-0000-0000-000000000001','Prise','tuya');
insert into public.device_bindings (device_id, integration_id, external_id) values
 ('72a00000-0000-0000-0000-000000000009','71a00000-0000-0000-0000-000000000001','tuya:prise');
select pg_temp.check((select removed_at is not null from public.devices where id = '72a00000-0000-0000-0000-000000000009'), 'appareil dissocié recréé : retiré aussitôt');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
select pg_temp.check((select count(*) = 1 from public.device_exclusions), 'le propriétaire voit les appareils dissociés');
select pg_temp.check(pg_temp.try_sql('select external_id from public.device_exclusions') like 'permission denied%', 'identifiant fournisseur illisible');
select public.allow_excluded_device((select id from public.device_exclusions limit 1));
reset role;
select pg_temp.check((select count(*) = 0 from public.device_exclusions), 'appareil de nouveau autorisé');

-- Appareil de l'installateur : dissociation réservée à l'exploitant.
insert into public.platform_devices (external_id, name, home_id, assigned_at) values ('tuya:disj','Disjoncteur','70a00000-0000-0000-0000-000000000001', now());
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
select pg_temp.check(pg_temp.try_sql($q$select public.remove_device('72a00000-0000-0000-0000-000000000003','unlink')$q$) like 'Appareil fourni%', 'appareil partagé de l''installateur protégé');

-- ---------------------------------------------------------------- QR codes
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a1');
insert into public.device_qr_scans (home_id, raw_payload, qr_code_type, parser_type, manufacturer, recognition_status)
values ('70a00000-0000-0000-0000-000000000001','{SN:ABC123,DT:DH-H5A,SC:****}','proprietary','dahua','Dahua','recognized');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_qr_scans (home_id, raw_payload, qr_code_type, parser_type, recognition_status)
  values ('70a00000-0000-0000-0000-000000000001','WIFI:S:shelly1;T:WPA;P:secret123;;','wifi','wifi','unknown')$q$) like '%check constraint%', 'mot de passe en clair refusé');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a2');
select pg_temp.check(pg_temp.try_sql($q$insert into public.device_qr_scans (home_id, user_id, raw_payload, qr_code_type, parser_type, recognition_status)
  values ('70a00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000007a2','X','serial','serial','unknown')$q$) like '%row-level security%', 'un simple membre n''ajoute pas d''appareil');
select pg_temp.check((select count(*) = 0 from public.device_qr_scans), 'scans d''un autre invisibles');
select pg_temp.as_user('00000000-0000-0000-0000-0000000007a4');
select pg_temp.check((select count(*) = 1 from public.device_qr_scans), 'l''exploitant voit les QR signalés');
reset role;
rollback;
