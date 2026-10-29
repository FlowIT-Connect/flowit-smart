-- =============================================================================
-- Solea — photos d'appareils et images de caméras
--
--   devices.image_url   : photo officielle du produit fournie par la passerelle
--                         (ex. icône produit Tuya, celle de l'app Smart Life).
--   devices.photo_path  : photo prise par l'utilisateur, dans le bucket device-photos.
--
-- Deux buckets Storage privés, chemins « <home_id>/<device_id>[-<horodatage>].<ext> » :
--   camera-frames : dernière image de chaque caméra, écrite par la passerelle
--                   (service_role) uniquement pendant qu'un membre regarde.
--   device-photos : photos personnalisées, gérées par owner/admin/installateur.
-- Lecture réservée aux membres autorisés sur l'appareil (can_use_device).
-- =============================================================================

alter table public.devices
  add column if not exists image_url text check (image_url is null or image_url ~ '^https://'),
  add column if not exists photo_path text check (photo_path is null or length(photo_path) <= 200);

grant update (photo_path) on public.devices to authenticated;

-- Appareil désigné par un chemin Storage, seulement si le chemin commence par sa maison.
create or replace function public.media_device_id(p_name text)
returns uuid language sql stable security definer set search_path = '' as $$
  select d.id
  from public.devices d
  where d.id = (
      (regexp_match(p_name, '^[0-9a-f-]{36}/([0-9a-f-]{36})(-[0-9]+)?\.(jpg|jpeg|png|webp)$'))[1]
    )::uuid
    and d.home_id::text = split_part(p_name, '/', 1)
$$;

create or replace function public.can_view_device_media(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.can_use_device(public.media_device_id(p_name)), false)
$$;

create or replace function public.can_edit_device_media(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.devices d
    where d.id = public.media_device_id(p_name)
      and public.home_role_of(d.home_id) in ('owner', 'admin', 'installer')
  )
$$;

grant execute on function public.media_device_id(text) to authenticated;
grant execute on function public.can_view_device_media(text) to authenticated;
grant execute on function public.can_edit_device_media(text) to authenticated;

-- Le chemin de photo doit désigner l'appareil lui-même (pas celui d'une autre maison).
create or replace function public.check_device_photo_path()
returns trigger language plpgsql as $$
begin
  if new.photo_path is not null and public.media_device_id(new.photo_path) is distinct from new.id then
    raise exception 'Chemin de photo invalide pour cet appareil';
  end if;
  return new;
end $$;
create trigger devices_photo_path_check before insert or update of photo_path on public.devices
  for each row execute function public.check_device_photo_path();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('camera-frames', 'camera-frames', false, 2097152, array['image/jpeg', 'image/png']),
  ('device-photos', 'device-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy camera_frames_select on storage.objects for select to authenticated
  using (bucket_id = 'camera-frames' and public.can_view_device_media(name));

create policy device_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'device-photos' and public.can_view_device_media(name));
create policy device_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'device-photos' and public.can_edit_device_media(name));
create policy device_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'device-photos' and public.can_edit_device_media(name))
  with check (bucket_id = 'device-photos' and public.can_edit_device_media(name));
create policy device_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'device-photos' and public.can_edit_device_media(name));
