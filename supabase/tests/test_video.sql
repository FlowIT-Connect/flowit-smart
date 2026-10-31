\set ON_ERROR_STOP 1
\set QUIET 1
-- Interphonie et vidéo, phase A (migration 20261103000000_solea_video.sql)
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

-- Exploitant X ; propriétaire P du logement V1 ; membre M limité à la lampe ; voisin N (logement V2)
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000f1','x@solea.dz'),
 ('00000000-0000-0000-0000-0000000000f2','p@v.dz'),
 ('00000000-0000-0000-0000-0000000000f3','m@v.dz'),
 ('00000000-0000-0000-0000-0000000000f4','n@v.dz');
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000f1');
insert into public.homes (id, owner_id, name) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f2','Apt 12'),
 ('f0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000f4','Apt 14');
insert into public.devices (id, home_id, name, protocol) values
 ('f1000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000001','Lampe','wifi');
insert into public.home_members (home_id, user_id, role, permissions) values
 ('f0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000f3','member','{"devices":["f1000000-0000-0000-0000-000000000002"]}');
insert into public.integrations (id, home_id, provider, status) values
 ('f2000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','other','connected');

-- ---------------------------------------------------------------- Sites
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check(pg_temp.try_sql($$select public.create_site('Résidence Les Pins')$$) like '%exploitant%', 'un propriétaire ne crée pas de site');
select pg_temp.check(pg_temp.try_sql($$update public.homes set site_id = gen_random_uuid() where id = 'f0000000-0000-0000-0000-000000000001'$$) like '%SITE_PROTEGE%' or
                     pg_temp.try_sql($$update public.homes set site_id = gen_random_uuid() where id = 'f0000000-0000-0000-0000-000000000001'$$) like '%foreign key%',
                     'un propriétaire ne rattache pas son logement à un immeuble directement');
select pg_temp.check(pg_temp.try_sql($$update public.homes set unit_label = 'Villa' where id = 'f0000000-0000-0000-0000-000000000001'$$) like '%SITE_PROTEGE%', 'unit_label protégé');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
create temp table t_site as select public.create_site('Résidence Les Pins', 'building', 'Alger') as id;
grant select on t_site to public;
select pg_temp.check((select count(*) = 1 from public.site_members where site_id = (select id from t_site) and role = 'manager'), 'le créateur devient gestionnaire');
create temp table t_entrance as select public.add_site_entrance((select id from t_site), 'Entrée principale') as id;
grant select on t_entrance to public;
select public.set_home_site('f0000000-0000-0000-0000-000000000001', (select id from t_site), 'Bât. B · Apt 12');
select public.set_home_site('f0000000-0000-0000-0000-000000000002', (select id from t_site), 'Bât. B · Apt 14');
select public.set_site_member((select id from t_site), '00000000-0000-0000-0000-0000000000f4', 'security');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check((select unit_label = 'Bât. B · Apt 12' from public.homes where id = 'f0000000-0000-0000-0000-000000000001'), 'logement rattaché à l''immeuble');
select pg_temp.check((select count(*) = 1 from public.sites), 'un résident voit son immeuble');
select pg_temp.check((select count(*) = 1 from public.site_entrances), 'un résident voit les entrées');
select pg_temp.check((select count(*) = 0 from public.site_members), 'un résident ne voit pas la liste du personnel');
select pg_temp.check(pg_temp.try_sql($$select public.add_site_entrance((select id from t_site), 'Parking')$$) like '%gestionnaire%', 'un résident n''ajoute pas d''entrée');
select pg_temp.check(pg_temp.try_sql($$select public.set_home_site('f0000000-0000-0000-0000-000000000001', null)$$) like '%gestionnaire%', 'un résident ne quitte pas l''immeuble seul');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f4');
select pg_temp.check((select count(*) = 2 from public.site_members), 'l''agent de sécurité voit le personnel');
select pg_temp.check(pg_temp.try_sql($$select public.set_site_member((select id from t_site), '00000000-0000-0000-0000-0000000000f4', 'manager')$$) like '%gestionnaire%', 'l''agent ne se promeut pas gestionnaire');

-- ---------------------------------------------------------------- Équipements vidéo
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check(pg_temp.try_sql($$select public.add_video_source('f0000000-0000-0000-0000-000000000001', 'Entrée', 'onvif', 'camera', '192.168.1.20')$$) like '%Réservé%', 'un membre n''ajoute pas de caméra');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check(pg_temp.try_sql($$select public.add_video_source('f0000000-0000-0000-0000-000000000001', 'Garage', 'rtsp', 'camera', null, null, 'rtsp://admin:secret@192.168.1.21/stream1')$$) like '%IDENTIFIANTS_DANS_URL%', 'identifiants refusés dans l''adresse RTSP');
select pg_temp.check(pg_temp.try_sql($$select public.add_video_source('f0000000-0000-0000-0000-000000000001', 'Garage', 'rtsp', 'camera')$$) like '%check%', 'RTSP sans adresse refusé');
select pg_temp.check(pg_temp.try_sql($$select public.add_video_source('f0000000-0000-0000-0000-000000000002', 'Chez le voisin', 'onvif', 'camera', '192.168.1.30')$$) like '%Réservé%', 'pas de caméra dans le logement d''un autre');
create temp table t_src as select public.add_video_source('f0000000-0000-0000-0000-000000000001', 'Entrée', 'onvif', 'intercom', '192.168.1.20', null,
  null, null, null, 'admin', 'S3cret!', null, null, 'Portail', (select id from t_entrance)) as id;
grant select on t_src to public;
select pg_temp.check((select port = 80 and status = 'pending' and category = 'intercom' from public.video_sources where id = (select id from t_src)), 'caméra ONVIF ajoutée (port 80 par défaut)');
select pg_temp.check(pg_temp.try_sql($$select * from public.video_source_secrets$$) like '%permission denied%', 'mots de passe illisibles par l''application');
select pg_temp.check(pg_temp.try_sql($$update public.video_sources set status = 'online'$$) like '%permission denied%', 'statut écrit seulement par le boîtier');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check((select count(*) = 0 from public.video_sources), 'un membre ne voit pas l''adresse IP des caméras');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f4');
select pg_temp.check((select count(*) = 0 from public.video_sources), 'le voisin ne voit pas les caméras du logement');

-- Le boîtier crée l'appareil : le lien se fait tout seul.
select pg_temp.as_service();
select pg_temp.check((select username = 'admin' and password = 'S3cret!' from public.video_source_secrets where source_id = (select id from t_src)), 'le boîtier lit les identifiants');
insert into public.devices (id, home_id, integration_id, name, protocol) values
 ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','Entrée','other');
insert into public.device_bindings (device_id, integration_id, external_id)
 select 'f1000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','udi:' || id from t_src;
select pg_temp.check((select device_id = 'f1000000-0000-0000-0000-000000000001' from public.video_sources where id = (select id from t_src)), 'appareil Solea relié à l''équipement');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select public.set_video_source_credentials((select id from t_src), 'admin', 'Nouveau1');
select pg_temp.check((select test_requested_at is not null and status = 'pending' from public.video_sources where id = (select id from t_src)), 'nouveau mot de passe : nouveau diagnostic demandé');

-- ---------------------------------------------------------------- Recherche réseau
create temp table t_scan as select public.request_video_scan('f0000000-0000-0000-0000-000000000001') as id;
grant select on t_scan to public;
select pg_temp.check(public.request_video_scan('f0000000-0000-0000-0000-000000000001') = (select id from t_scan), 'une seule recherche à la fois');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check(pg_temp.try_sql($$select public.request_video_scan('f0000000-0000-0000-0000-000000000001')$$) like '%Réservé%', 'un membre ne lance pas de recherche');

-- ---------------------------------------------------------------- Sessions WebRTC
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check(pg_temp.try_sql($$insert into public.video_sessions (home_id, device_id, offer) values ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre sdp')$$) like '%row-level security%',
  'un membre limité ne regarde pas une caméra non autorisée');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f4');
select pg_temp.check(pg_temp.try_sql($$insert into public.video_sessions (home_id, device_id, offer) values ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre sdp')$$) like '%row-level security%',
  'le voisin ne regarde jamais la caméra d''un autre logement');
select pg_temp.check(pg_temp.try_sql($$insert into public.video_sessions (home_id, device_id, offer) values ('f0000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000001','v=0 offre sdp')$$) like '%row-level security%',
  'logement et appareil doivent correspondre');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
insert into public.video_sessions (id, home_id, device_id, offer) values
 ('f3000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre sdp');
select pg_temp.check(pg_temp.try_sql($$insert into public.video_sessions (home_id, device_id, offer, status, answer) values ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre','answered','v=0 fausse')$$) like '%row-level security%',
  'l''application n''écrit pas de réponse');
select pg_temp.check(pg_temp.try_sql($$update public.video_sessions set answer = 'v=0 fausse' where id = 'f3000000-0000-0000-0000-000000000001'$$) like '%permission denied%', 'la réponse n''est écrite que par le boîtier');

select pg_temp.as_service();
update public.video_sessions set status = 'answered', answer = 'v=0 réponse' where id = 'f3000000-0000-0000-0000-000000000001';
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select pg_temp.check((select answer = 'v=0 réponse' from public.video_sessions where id = 'f3000000-0000-0000-0000-000000000001'), 'le propriétaire lit la réponse');
update public.video_sessions set status = 'closed' where id = 'f3000000-0000-0000-0000-000000000001';
select pg_temp.check((select status = 'closed' from public.video_sessions where id = 'f3000000-0000-0000-0000-000000000001'), 'le propriétaire ferme sa session');
select pg_temp.check(pg_temp.try_sql($$update public.video_sessions set status = 'offer' where id = 'f3000000-0000-0000-0000-000000000001'$$) like '%row-level security%', 'une session fermée ne se rouvre pas');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check((select count(*) = 0 from public.video_sessions), 'chacun ne voit que ses sessions');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
do $$ begin
  for i in 1..9 loop
    insert into public.video_sessions (home_id, device_id, offer) values ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre sdp');
  end loop;
end $$;
select pg_temp.check(pg_temp.try_sql($$insert into public.video_sessions (home_id, device_id, offer) values ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','v=0 offre sdp')$$) like '%TROP_DE_DEMANDES_VIDEO%', 'limite de 10 demandes vidéo par minute');

-- ---------------------------------------------------------------- Boîtier
select pg_temp.as_service();
insert into public.media_gateways (home_id, ice_servers, relay_ok, last_seen_at) values
 ('f0000000-0000-0000-0000-000000000001','[{"urls":["stun:stun.l.google.com:19302"]}]', true, now());
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
select pg_temp.check((select relay_ok from public.media_gateways where home_id = 'f0000000-0000-0000-0000-000000000001'), 'les membres voient l''état du boîtier vidéo');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f4');
select pg_temp.check((select count(*) = 0 from public.media_gateways), 'le voisin ne voit pas le boîtier du logement');

-- ---------------------------------------------------------------- Suppression
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
select public.delete_video_source((select id from t_src));
select pg_temp.check((select count(*) = 0 from public.devices where id = 'f1000000-0000-0000-0000-000000000001'), 'supprimer l''équipement supprime l''appareil');
reset role;
