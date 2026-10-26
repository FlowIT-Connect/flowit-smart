\set ON_ERROR_STOP 1
\set QUIET 1
-- Identités
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-00000000000a','a@x.dz'),
 ('00000000-0000-0000-0000-00000000000b','b@x.dz'),
 ('00000000-0000-0000-0000-00000000000c','c@x.dz');
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
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
grant execute on all functions in schema pg_temp to public;

-- A crée une maison
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.homes (id, owner_id, name) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','Maison A');
select public.create_home('Résidence secondaire') as home2 \gset
select pg_temp.check((select role = 'owner' from public.home_members where home_id = :'home2' and user_id = auth.uid()), 'create_home : propriétaire membre');
delete from public.homes where id = :'home2';
select pg_temp.check((select public.create_integration('10000000-0000-0000-0000-000000000001','home_assistant','HA salon')) is not null, 'owner crée une intégration');

-- Le backend (service) synchronise des appareils
reset role; select pg_temp.as_service();
insert into public.devices (id, home_id, name, protocol) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Lampe','zigbee'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Prise','wifi');
insert into public.devices (id, home_id, name, protocol, is_sensitive) values
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Serrure','ble', true);
insert into public.device_capabilities (device_id, capability_key, type) values
 ('20000000-0000-0000-0000-000000000001','switch','boolean'),
 ('20000000-0000-0000-0000-000000000001','brightness','number'),
 ('20000000-0000-0000-0000-000000000002','switch','boolean'),
 ('20000000-0000-0000-0000-000000000003','lock','boolean');

-- A crée deux scènes
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.scenes (id, home_id, name) values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Soirée');
insert into public.scene_actions (scene_id, device_id, capability_key, value, position, delay_ms) values
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','switch','true',0,0),
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','switch','false',1,2000),
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','lock','false',2,0);
insert into public.scenes (id, home_id, name, failure_policy) values ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Stricte','stop');
insert into public.scene_actions (scene_id, device_id, capability_key, value, position) values
 ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','switch','true',0),
 ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','switch','true',1);

-- Exécution scène "continue"
select public.execute_scene('30000000-0000-0000-0000-000000000001') as run1 \gset
select pg_temp.check((select count(*) from public.device_commands where scene_run_id = :'run1') = 2, 'scène : 2 commandes émises, serrure exclue');
select pg_temp.check((select not_before - created_at >= interval '2 seconds' from public.device_commands where scene_run_id = :'run1' and device_id='20000000-0000-0000-0000-000000000002'), 'scène : délai appliqué (not_before)');
select pg_temp.check((select results @> '[{"status":"rejected","error":"Appareil sensible bloqué"}]' from public.scene_runs where id = :'run1'), 'scène : serrure signalée rejetée');
select pg_temp.check((select requested_by = '00000000-0000-0000-0000-00000000000a' from public.device_commands where scene_run_id = :'run1' limit 1), 'scène : commandes attribuées à l''utilisateur');

-- Le backend confirme l'une, échoue l'autre
reset role; select pg_temp.as_service();
update public.device_commands set status='confirmed', completed_at=now() where scene_run_id = :'run1' and device_id='20000000-0000-0000-0000-000000000001';
select pg_temp.check((select status = 'running' from public.scene_runs where id = :'run1'), 'scène : reste en cours tant qu''une commande attend');
update public.device_commands set status='failed', error='HA: timeout', completed_at=now() where scene_run_id = :'run1' and device_id='20000000-0000-0000-0000-000000000002';
select pg_temp.check((select status = 'partial' and finished_at is not null from public.scene_runs where id = :'run1'), 'scène : résultat partiel');
select pg_temp.check((select count(*) = 3 from public.scene_runs, jsonb_array_elements(results) where id = :'run1'), 'scène : 3 résultats journalisés');

-- Politique "stop"
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.execute_scene('30000000-0000-0000-0000-000000000002') as run2 \gset
reset role; select pg_temp.as_service();
update public.device_commands set status='failed', error='hors ligne' where scene_run_id = :'run2' and device_id='20000000-0000-0000-0000-000000000001';
select pg_temp.check((select status = 'rejected' from public.device_commands where scene_run_id = :'run2' and device_id='20000000-0000-0000-0000-000000000002'), 'stop : commande suivante annulée');
select pg_temp.check((select status = 'failed' from public.scene_runs where id = :'run2'), 'stop : exécution en échec');

-- Automatisation exécutée par le backend
select public.execute_scene('30000000-0000-0000-0000-000000000002', null) as run3 \gset
select pg_temp.check((select count(*) = 2 and bool_and(requested_by is null) from public.device_commands where scene_run_id = :'run3'), 'service : exécution sans utilisateur');
update public.device_commands set status='confirmed' where scene_run_id = :'run3';
select pg_temp.check((select status = 'success' from public.scene_runs where id = :'run3'), 'service : succès complet');

-- Étranger C
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  perform public.execute_scene('30000000-0000-0000-0000-000000000001');
  raise exception 'ÉCHEC: étranger a exécuté la scène';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: étranger ne peut pas exécuter la scène (%)', sqlerrm;
end $$;
do $$ begin
  perform public.create_integration('10000000-0000-0000-0000-000000000001','tuya',null);
  raise exception 'ÉCHEC: étranger a créé une intégration';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: étranger ne peut pas créer d''intégration';
end $$;
select pg_temp.check((select count(*) = 0 from public.scene_runs), 'étranger ne voit aucune exécution');
do $$ begin
  insert into public.device_commands (home_id, device_id, capability_key, value, idempotency_key, scene_run_id)
  values ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','switch','true','x', null);
  raise exception 'ÉCHEC';
exception when others then
  if sqlerrm = 'ÉCHEC' then raise; end if;
  raise notice 'OK: le client ne peut pas renseigner scene_run_id (%)', sqlerrm;
end $$;

-- Invitation de B
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.home_invitations (home_id, email, role, invited_by) values ('10000000-0000-0000-0000-000000000001','B@x.dz','member','00000000-0000-0000-0000-00000000000a');
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.check((select count(*) = 1 from public.list_my_invitations()), 'B voit son invitation');
select public.accept_home_invitation((select token from public.list_my_invitations() limit 1)) is not null as accepted \gset
select pg_temp.check((select count(*) = 1 from public.homes), 'B voit la maison après acceptation');
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.check((select count(*) = 0 from public.list_my_invitations()), 'C ne voit pas l''invitation de B');

-- Membre B : pas de création d'intégration
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  perform public.create_integration('10000000-0000-0000-0000-000000000001','tuya',null);
  raise exception 'ÉCHEC: membre a créé une intégration';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: membre ne peut pas créer d''intégration';
end $$;
do $$ begin
  perform public.transfer_home_ownership('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000b');
  raise exception 'ÉCHEC: membre a pris la propriété';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: membre ne peut pas se transférer la propriété';
end $$;

-- Transfert A -> B
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.transfer_home_ownership('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000b');
select pg_temp.check((select role = 'admin' from public.home_members where user_id='00000000-0000-0000-0000-00000000000a'), 'transfert : A devient admin');
select pg_temp.check((select owner_id = '00000000-0000-0000-0000-00000000000b' from public.homes), 'transfert : B propriétaire');

-- Journal
select pg_temp.check((select count(*) > 0 from public.event_logs where event_type = 'scene_finished'), 'journal : fin de scène');
select pg_temp.check((select count(*) > 0 from public.event_logs where event_type = 'config_changed'), 'journal : changements de configuration');
reset role; select pg_temp.as_service();
update public.devices set availability = 'unavailable' where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.check((select count(*) = 1 from public.event_logs where event_type = 'device_unavailable'), 'journal : appareil indisponible');

-- Suppression de compte : C (aucune maison) puis B (propriétaire)
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select public.delete_my_account();
reset role; select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select public.delete_my_account();
reset role;
select pg_temp.check((select count(*) = 1 from auth.users), 'suppression : seuls les comptes supprimés disparaissent');
select pg_temp.check((select count(*) = 0 from public.homes), 'suppression : maison du propriétaire supprimée');
select pg_temp.check(public.purge_event_logs(0) >= 0, 'purge du journal');
