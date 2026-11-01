-- =============================================================================
-- Solea — images des pièces (bibliothèque Solea ou photo personnelle)
--
--   rooms.image_key  : image choisie dans la bibliothèque livrée avec l'app
--                      (« salon_moderne_2 »). null = image par défaut selon l'icône.
--   rooms.photo_path : photo personnelle, bucket privé room-photos,
--                      chemin « <home_id>/<room_id>-<horodatage>.<ext> ».
--   rooms.image_fit  : cadrage { x, y (-1 à 1), zoom (1 à 3) }.
--
-- Lecture : tous les membres du logement. Écriture : propriétaire et administrateurs
-- (mêmes droits que pour les pièces elles-mêmes, policy rooms_write).
-- =============================================================================

alter table public.rooms
  add column if not exists image_key text
    check (image_key is null or (image_key ~ '^[a-z_]+_[0-9]+$' and length(image_key) <= 60)),
  add column if not exists photo_path text
    check (photo_path is null or length(photo_path) <= 200),
  add column if not exists image_fit jsonb not null default '{"x":0,"y":0,"zoom":1}'::jsonb
    check (
      jsonb_typeof(image_fit) = 'object'
      and coalesce((image_fit ->> 'x')::numeric between -1 and 1, true)
      and coalesce((image_fit ->> 'y')::numeric between -1 and 1, true)
      and coalesce((image_fit ->> 'zoom')::numeric between 1 and 3, true)
    );

-- Pièce désignée par un chemin Storage, seulement si le chemin commence par son logement.
create or replace function public.media_room_id(p_name text)
returns uuid language sql stable security definer set search_path = '' as $$
  select r.id
  from public.rooms r
  where r.id = (
      (regexp_match(p_name, '^[0-9a-f-]{36}/([0-9a-f-]{36})(-[0-9]+)?\.(jpg|jpeg|png|webp)$'))[1]
    )::uuid
    and r.home_id::text = split_part(p_name, '/', 1)
$$;

create or replace function public.can_view_room_media(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.rooms r
    where r.id = public.media_room_id(p_name) and public.is_home_member(r.home_id)
  )
$$;

create or replace function public.can_edit_room_media(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.rooms r
    where r.id = public.media_room_id(p_name) and public.is_home_manager(r.home_id)
  )
$$;

grant execute on function public.media_room_id(text) to authenticated;
grant execute on function public.can_view_room_media(text) to authenticated;
grant execute on function public.can_edit_room_media(text) to authenticated;

-- Le chemin de photo doit désigner la pièce elle-même (pas celle d'un autre logement).
create or replace function public.check_room_photo_path()
returns trigger language plpgsql as $$
begin
  if new.photo_path is not null and public.media_room_id(new.photo_path) is distinct from new.id then
    raise exception 'Chemin de photo invalide pour cette pièce';
  end if;
  return new;
end $$;
drop trigger if exists rooms_photo_path_check on public.rooms;
create trigger rooms_photo_path_check before insert or update of photo_path on public.rooms
  for each row execute function public.check_room_photo_path();

-- Bucket privé des photos de pièces (5 Mo, JPEG / PNG / WebP).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('room-photos', 'room-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists room_photos_select on storage.objects;
drop policy if exists room_photos_insert on storage.objects;
drop policy if exists room_photos_update on storage.objects;
drop policy if exists room_photos_delete on storage.objects;
create policy room_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'room-photos' and public.can_view_room_media(name));
create policy room_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'room-photos' and public.can_edit_room_media(name));
create policy room_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'room-photos' and public.can_edit_room_media(name))
  with check (bucket_id = 'room-photos' and public.can_edit_room_media(name));
create policy room_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'room-photos' and public.can_edit_room_media(name));
