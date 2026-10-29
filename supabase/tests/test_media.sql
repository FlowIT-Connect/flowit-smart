\set ON_ERROR_STOP 1
\set QUIET 1
-- Photos d'appareils et images de caméras (migration 20261029000000_solea_media.sql)
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

-- Propriétaire O, membre restreint R (n'a droit qu'à la lampe), étranger X
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000d1','o@x.dz'),
 ('00000000-0000-0000-0000-0000000000d2','r@x.dz'),
 ('00000000-0000-0000-0000-0000000000d3','x@x.dz');
insert into public.homes (id, owner_id, name) values
 ('d0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000d1','Maison D'),
 ('d0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000d3','Maison X');
insert into public.devices (id, home_id, name, protocol) values
 ('e0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001','Caméra entrée','wifi'),
 ('e0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-000000000001','Lampe','wifi'),
 ('e0000000-0000-0000-0000-000000000003','d0000000-0000-0000-0000-000000000002','Caméra X','wifi');
insert into public.home_members (home_id, user_id, role, permissions) values
 ('d0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000d2','member','{"devices":["e0000000-0000-0000-0000-000000000002"]}');

-- La passerelle (service_role) dépose une image de caméra
insert into storage.objects (bucket_id, name) values
 ('camera-frames', 'd0000000-0000-0000-0000-000000000001/e0000000-0000-0000-0000-000000000001.jpg'),
 ('camera-frames', 'd0000000-0000-0000-0000-000000000002/e0000000-0000-0000-0000-000000000003.jpg');
update public.devices set image_url = 'https://images.tuyaeu.com/smart/icon/clim.png' where id = 'e0000000-0000-0000-0000-000000000002';

do $$ begin
  update public.devices set image_url = 'http://exemple.dz/a.png' where id = 'e0000000-0000-0000-0000-000000000002';
  raise exception 'ÉCHEC: image_url non https acceptée';
exception when check_violation then raise notice 'OK: image_url doit être en https';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'camera-frames'), 'caméra : le propriétaire voit l''image de sa maison seulement');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'camera-frames'), 'caméra : membre restreint sans droit sur la caméra ne voit rien');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
do $$ begin
  insert into storage.objects (bucket_id, name) values ('camera-frames', 'd0000000-0000-0000-0000-000000000001/e0000000-0000-0000-0000-000000000001.jpg');
  raise exception 'ÉCHEC: un utilisateur écrit une image de caméra';
exception when insufficient_privilege then raise notice 'OK: seules les passerelles écrivent les images de caméra';
end $$;

-- Photo personnalisée
insert into storage.objects (bucket_id, name) values ('device-photos', 'd0000000-0000-0000-0000-000000000001/e0000000-0000-0000-0000-000000000002-1730000000.jpg');
update public.devices set photo_path = 'd0000000-0000-0000-0000-000000000001/e0000000-0000-0000-0000-000000000002-1730000000.jpg' where id = 'e0000000-0000-0000-0000-000000000002';
select pg_temp.check((select photo_path is not null from public.devices where id = 'e0000000-0000-0000-0000-000000000002'), 'photo : le propriétaire ajoute une photo');

do $$ begin
  update public.devices set photo_path = 'd0000000-0000-0000-0000-000000000002/e0000000-0000-0000-0000-000000000003.jpg' where id = 'e0000000-0000-0000-0000-000000000002';
  raise exception 'ÉCHEC: photo d''un autre appareil acceptée';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: le chemin de photo doit désigner l''appareil lui-même';
end $$;

do $$ begin
  insert into storage.objects (bucket_id, name) values ('device-photos', 'd0000000-0000-0000-0000-000000000002/e0000000-0000-0000-0000-000000000003.jpg');
  raise exception 'ÉCHEC: photo déposée dans une autre maison';
exception when insufficient_privilege then raise notice 'OK: pas de photo dans la maison d''un autre';
end $$;

do $$ begin
  insert into storage.objects (bucket_id, name) values ('device-photos', 'd0000000-0000-0000-0000-000000000002/e0000000-0000-0000-0000-000000000001.jpg');
  raise exception 'ÉCHEC: chemin maison/appareil incohérent accepté';
exception when insufficient_privilege then raise notice 'OK: chemin maison/appareil incohérent refusé';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'device-photos'), 'photo : membre restreint voit la photo de la lampe autorisée');
do $$ begin
  insert into storage.objects (bucket_id, name) values ('device-photos', 'd0000000-0000-0000-0000-000000000001/e0000000-0000-0000-0000-000000000002-1.jpg');
  raise exception 'ÉCHEC: simple membre ajoute une photo';
exception when insufficient_privilege then raise notice 'OK: un simple membre ne change pas les photos';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d3');
select pg_temp.check((select count(*) = 0 from storage.objects where name like 'd0000000-0000-0000-0000-000000000001/%'), 'étranger : aucune image de la maison D');
reset role;
