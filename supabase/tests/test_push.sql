\set ON_ERROR_STOP 1
\set QUIET 1
-- Notifications push (migration 20261109000000_solea_push.sql)
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'ÉCHEC: %', label; end if;
  raise notice 'OK: %', label;
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000007a','p@push.dz');
insert into public.homes (id, owner_id, name) values
 ('7a000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000007a','Maison P');

-- Sans pg_net ni adresse : la notification est écrite, rien n'est envoyé.
select public.notify_home('7a000000-0000-0000-0000-000000000001', 'smoke', null, 'Cuisine');
select pg_temp.check((select count(*) = 1 from public.notifications where home_id = '7a000000-0000-0000-0000-000000000001'),
                     'sans pg_net, la notification est quand même créée');

-- pg_net simulé : on enregistre les appels.
create schema if not exists net;
create table net.calls (url text, body jsonb);
create or replace function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int)
returns bigint language sql as $$ insert into net.calls values (url, body) returning 1::bigint $$;

select public.notify_home('7a000000-0000-0000-0000-000000000001', 'water_leak', null, 'Salle de bain');
select pg_temp.check((select count(*) = 0 from net.calls), 'sans adresse push_url, aucun appel');

insert into private.settings values ('push_url', 'https://exemple.supabase.co/functions/v1/send-push');
select public.notify_home('7a000000-0000-0000-0000-000000000001', 'door_open', null, 'Entrée');
select pg_temp.check((select count(*) = 1 from net.calls c join public.notifications n on n.id = (c.body ->> 'id')::bigint
                      where n.type = 'door_open' and c.url like '%/send-push'), 'nouvelle notification envoyée à send-push');
select public.notify_home('7a000000-0000-0000-0000-000000000001', 'automation_run', null, 'Routine');
select pg_temp.check((select count(*) = 1 from net.calls), 'priorité basse : pas de push');

-- Un échec de pg_net ne bloque jamais la notification.
create or replace function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int)
returns bigint language plpgsql as $$ begin raise exception 'réseau coupé'; end $$;
select public.notify_home('7a000000-0000-0000-0000-000000000001', 'motion', null, 'Salon');
select pg_temp.check((select count(*) = 1 from public.notifications where home_id = '7a000000-0000-0000-0000-000000000001' and type = 'motion'),
                     'panne du push : notification conservée');

-- Les clients ne lisent pas les réglages serveur et ne marquent pas l'envoi.
select pg_temp.check(not has_schema_privilege('authenticated', 'private', 'usage'), 'schéma private fermé aux clients');
select pg_temp.check(not has_table_privilege('authenticated', 'private.settings', 'select'), 'réglages serveur invisibles des clients');
select pg_temp.check(not has_column_privilege('authenticated', 'public.notifications', 'pushed_at', 'update'), 'pushed_at non modifiable par les clients');
drop schema net cascade;
