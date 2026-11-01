\set ON_ERROR_STOP 1
\set QUIET 1
-- Préférences d'apparence (migration 20261105000000_solea_appearance.sql)
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
 ('00000000-0000-0000-0000-0000000000a7','u@a.dz'),
 ('00000000-0000-0000-0000-0000000000a8','v@a.dz');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a7');
select pg_temp.check((select preferences = '{}'::jsonb from public.profiles where id = auth.uid()), 'préférences vides par défaut');
update public.profiles set preferences = '{"appearance":{"theme":"blue_glass","blur":14}}' where id = auth.uid();
select pg_temp.check((select preferences #>> '{appearance,theme}' = 'blue_glass' from public.profiles where id = auth.uid()), 'l''utilisateur enregistre son thème');

do $$ begin
  update public.profiles set preferences = '[1,2]' where id = auth.uid();
  raise exception 'ÉCHEC: préférences non objet acceptées';
exception when check_violation then raise notice 'OK: préférences = objet JSON';
end $$;

insert into storage.objects (bucket_id, name) values ('backgrounds', '00000000-0000-0000-0000-0000000000a7/bg-1730000000.jpg');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'backgrounds'), 'l''utilisateur dépose sa photo d''arrière-plan');
do $$ begin
  insert into storage.objects (bucket_id, name) values ('backgrounds', '00000000-0000-0000-0000-0000000000a8/bg-1.jpg');
  raise exception 'ÉCHEC: photo déposée dans le dossier d''un autre';
exception when insufficient_privilege then raise notice 'OK: pas de photo dans le dossier d''un autre';
end $$;
do $$ begin
  insert into storage.objects (bucket_id, name) values ('backgrounds', '00000000-0000-0000-0000-0000000000a7/script.html');
  raise exception 'ÉCHEC: nom de fichier libre accepté';
exception when insufficient_privilege then raise notice 'OK: nom de fichier contrôlé';
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000000a8');
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'backgrounds'), 'un autre utilisateur ne voit pas la photo');
update public.profiles set preferences = '{"x":1}' where id = '00000000-0000-0000-0000-0000000000a7';
reset role;
select pg_temp.check((select preferences #>> '{appearance,theme}' = 'blue_glass' from public.profiles where id = '00000000-0000-0000-0000-0000000000a7'), 'un autre utilisateur ne change pas les préférences');
