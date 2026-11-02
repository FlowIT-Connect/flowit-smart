\set ON_ERROR_STOP 1
\set QUIET 1
-- Images des pièces (migration 20261104000000_solea_room_images.sql)
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

-- Propriétaire O, simple membre M, étranger X (avec sa propre maison)
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000b1','o@r.dz'),
 ('00000000-0000-0000-0000-0000000000b2','m@r.dz'),
 ('00000000-0000-0000-0000-0000000000b3','x@r.dz');
insert into public.homes (id, owner_id, name) values
 ('b0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','Maison R'),
 ('b0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000b3','Maison X');
insert into public.home_members (home_id, user_id, role) values
 ('b0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2','member');
insert into public.rooms (id, home_id, name, icon) values
 ('b1000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','Salon','sofa'),
 ('b1000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000002','Salon X','sofa');

select pg_temp.check((select image_fit = '{"x":0,"y":0,"zoom":1}'::jsonb and image_key is null and photo_path is null
                      from public.rooms where id = 'b1000000-0000-0000-0000-000000000001'), 'pièce existante : image par défaut, cadrage centré');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
update public.rooms set image_key = 'salon_moderne_2', image_fit = '{"x":0.3,"y":-0.2,"zoom":1.5}'
 where id = 'b1000000-0000-0000-0000-000000000001';
select pg_temp.check((select image_key = 'salon_moderne_2' from public.rooms where id = 'b1000000-0000-0000-0000-000000000001'),
                     'propriétaire : choisit une image de la bibliothèque et son cadrage');

do $$ begin
  update public.rooms set image_key = '../../etc/passwd' where id = 'b1000000-0000-0000-0000-000000000001';
  raise exception 'ÉCHEC: clé d''image invalide acceptée';
exception when check_violation then raise notice 'OK: clé d''image de bibliothèque contrôlée';
end $$;

do $$ begin
  update public.rooms set image_fit = '{"x":0,"y":0,"zoom":9}' where id = 'b1000000-0000-0000-0000-000000000001';
  raise exception 'ÉCHEC: zoom hors limites accepté';
exception when check_violation then raise notice 'OK: zoom limité de 1 à 3';
end $$;

-- Photo personnelle
insert into storage.objects (bucket_id, name) values
 ('room-photos', 'b0000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000001-1730000000.jpg');
update public.rooms set photo_path = 'b0000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000001-1730000000.jpg'
 where id = 'b1000000-0000-0000-0000-000000000001';
select pg_temp.check((select photo_path is not null from public.rooms where id = 'b1000000-0000-0000-0000-000000000001'),
                     'propriétaire : enregistre une photo personnelle');

do $$ begin
  update public.rooms set photo_path = 'b0000000-0000-0000-0000-000000000002/b1000000-0000-0000-0000-000000000002.jpg'
   where id = 'b1000000-0000-0000-0000-000000000001';
  raise exception 'ÉCHEC: photo d''une autre pièce acceptée';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'OK: le chemin de photo doit désigner la pièce elle-même';
end $$;

do $$ begin
  insert into storage.objects (bucket_id, name) values ('room-photos', 'b0000000-0000-0000-0000-000000000002/b1000000-0000-0000-0000-000000000002.jpg');
  raise exception 'ÉCHEC: photo déposée dans la maison d''un autre';
exception when insufficient_privilege then raise notice 'OK: pas de photo de pièce dans la maison d''un autre';
end $$;

do $$ begin
  insert into storage.objects (bucket_id, name) values ('room-photos', 'b0000000-0000-0000-0000-000000000002/b1000000-0000-0000-0000-000000000001.jpg');
  raise exception 'ÉCHEC: chemin maison/pièce incohérent accepté';
exception when insufficient_privilege then raise notice 'OK: chemin maison/pièce incohérent refusé';
end $$;

-- Simple membre : voit l'image, ne la change pas
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b2');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'room-photos'), 'membre : voit la photo de la pièce');
select pg_temp.check((select image_key = 'salon_moderne_2' from public.rooms where id = 'b1000000-0000-0000-0000-000000000001'), 'membre : voit l''image choisie');
do $$ begin
  insert into storage.objects (bucket_id, name) values ('room-photos', 'b0000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000001-2.jpg');
  raise exception 'ÉCHEC: simple membre ajoute une photo de pièce';
exception when insufficient_privilege then raise notice 'OK: un simple membre ne change pas la photo';
end $$;
update public.rooms set image_key = 'garage_1' where id = 'b1000000-0000-0000-0000-000000000001';
reset role;
select pg_temp.check((select image_key = 'salon_moderne_2' from public.rooms where id = 'b1000000-0000-0000-0000-000000000001'), 'membre : ne change pas l''image de la pièce');

-- Étranger : rien
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b3');
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'room-photos' and name like 'b0000000-0000-0000-0000-000000000001/%'),
                     'étranger : aucune photo de pièce de la maison R');
reset role;
