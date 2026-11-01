\set ON_ERROR_STOP 1
\set QUIET 1
-- Centre de notifications (migration 20261106000000_solea_notifications.sql)
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
 ('00000000-0000-0000-0000-00000000009a','o@n.dz'),
 ('00000000-0000-0000-0000-00000000009b','m@n.dz'),
 ('00000000-0000-0000-0000-00000000009c','x@n.dz');
insert into public.homes (id, owner_id, name) values
 ('9a000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000009a','Maison N');
insert into public.home_members (home_id, user_id, role, permissions) values
 ('9a000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000009b','member',
  '{"devices":["9a100000-0000-0000-0000-000000000001"]}');
insert into public.rooms (id, home_id, name, icon) values
 ('9a200000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000001','Entrée','door');
insert into public.devices (id, home_id, room_id, name, protocol, availability, state) values
 ('9a100000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000001','9a200000-0000-0000-0000-000000000001','Porte d''entrée','tuya','available','{"contact":true}'),
 ('9a100000-0000-0000-0000-000000000002','9a000000-0000-0000-0000-000000000001',null,'Fenêtre chambre','tuya','available','{"contact":true}'),
 ('9a100000-0000-0000-0000-000000000003','9a000000-0000-0000-0000-000000000001',null,'Capteur salon','tuya','available','{"temperature":22,"motion":false,"water_leak":false}');

-- La passerelle (service_role) écrit l'état réel des appareils.
update public.devices set state = '{"contact":false}' where id = '9a100000-0000-0000-0000-000000000001';
select pg_temp.check((select count(*) = 2 from public.notifications where type = 'door_open' and priority = 'high'
                      and body = 'Porte d''entrée · Entrée'), 'porte ouverte : propriétaire et membre notifiés');
update public.devices set state = '{"contact":false,"battery":80}' where id = '9a100000-0000-0000-0000-000000000001';
select pg_temp.check((select count(*) = 2 from public.notifications where type = 'door_open'), 'pas de doublon si la porte reste ouverte');
update public.devices set state = '{"contact":true}' where id = '9a100000-0000-0000-0000-000000000001';
select pg_temp.check((select count(*) = 2 from public.notifications where type = 'door_closed' and priority = 'low'), 'porte fermée');

update public.devices set state = '{"contact":false}' where id = '9a100000-0000-0000-0000-000000000002';
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'window_open'), 'fenêtre ouverte : seulement le propriétaire (membre limité à la porte)');

update public.devices set state = '{"temperature":22,"motion":true,"water_leak":true}' where id = '9a100000-0000-0000-0000-000000000003';
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'motion'), 'mouvement détecté');
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'water_leak' and priority = 'critical' and category = 'alarm'), 'fuite d''eau : critique');
select pg_temp.check((select count(*) = 0 from public.notifications where type = 'temperature_abnormal'), 'température normale : rien');

-- Le propriétaire coupe les mouvements et règle son seuil haut à 28 °C.
update public.profiles set preferences = '{"notifications":{"off":["motion"],"temp_max":28}}' where id = '00000000-0000-0000-0000-00000000009a';
update public.devices set state = '{"temperature":30,"motion":false}' where id = '9a100000-0000-0000-0000-000000000003';
update public.devices set state = '{"temperature":30,"motion":true}' where id = '9a100000-0000-0000-0000-000000000003';
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'motion'), 'type désactivé : plus de mouvement notifié');
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'temperature_abnormal' and data ->> 'temperature' = '30'),
                     'température anormale selon le seuil du membre');

update public.devices set availability = 'unavailable' where id = '9a100000-0000-0000-0000-000000000003';
select pg_temp.check((select count(*) = 1 from public.notifications where type = 'device_offline'), 'appareil déconnecté');

insert into public.automations (id, home_id, name, trigger, actions) values
 ('9a300000-0000-0000-0000-000000000001','9a000000-0000-0000-0000-000000000001','Bonne nuit','{"type":"manual"}','[{"scene_id":"x"}]');
update public.automations set last_run_at = now() where id = '9a300000-0000-0000-0000-000000000001';
select pg_temp.check((select count(*) = 2 from public.notifications where type = 'automation_run' and body = 'Bonne nuit'), 'automatisation exécutée');

set role service_role;
select pg_temp.check(public.notify_home('9a000000-0000-0000-0000-000000000001', 'high_wind', null, 'Vent 92 km/h', '{"wind":92}') = 2,
                     'la passerelle signale des vents forts');
reset role;

-- Côté application
select pg_temp.as_user('00000000-0000-0000-0000-00000000009b');
select pg_temp.check((select count(*) = 4 from public.notifications), 'le membre ne voit que ses notifications');
do $$ begin
  insert into public.notifications (home_id, user_id, type, category, priority, title)
  values ('9a000000-0000-0000-0000-000000000001', auth.uid(), 'smoke', 'alarm', 'critical', 'Faux');
  raise exception 'ÉCHEC: le client crée une notification';
exception when insufficient_privilege then raise notice 'OK: le client ne crée pas de notification';
end $$;
do $$ begin
  update public.notifications set title = 'Modifié';
  raise exception 'ÉCHEC: le client réécrit une notification';
exception when insufficient_privilege then raise notice 'OK: le client ne réécrit pas une notification';
end $$;
do $$ begin
  perform public.notify_home('9a000000-0000-0000-0000-000000000001', 'smoke');
  raise exception 'ÉCHEC: le client déclenche notify_home';
exception when insufficient_privilege then raise notice 'OK: notify_home réservé à la passerelle';
end $$;
update public.notifications set read_at = now() where type = 'door_open';
select pg_temp.check((select count(*) = 3 from public.notifications where read_at is null), 'marquer une notification comme lue');
select pg_temp.check(public.mark_notifications_read() = 3, 'tout marquer comme lu');
delete from public.notifications where type = 'door_closed';
select pg_temp.check((select count(*) = 3 from public.notifications), 'supprimer une notification');
insert into public.push_tokens (token, user_id, platform) values (repeat('t', 40), auth.uid(), 'android');

select pg_temp.as_user('00000000-0000-0000-0000-00000000009c');
select pg_temp.check((select count(*) = 0 from public.notifications) and (select count(*) = 0 from public.push_tokens),
                     'un étranger ne voit ni notifications ni jetons');
reset role;
select pg_temp.check((select count(*) = 0 from public.notifications where user_id = '00000000-0000-0000-0000-00000000009a' and read_at is not null),
                     'les notifications du propriétaire restent non lues');
