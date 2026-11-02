-- =============================================================================
-- Solea : ajout des caméras Dahua par QR code (numéro de série + code de sécurité)
--
--   video_sources.serial / mac : numéro de série lu dans le QR code de l'étiquette ; le boîtier
--     vidéo retrouve la caméra sur le Wi-Fi par ce numéro (recherche Dahua, port 37810) et
--     enregistre lui-même son adresse IP. Le client n'a jamais d'adresse à saisir.
--   driver « dahua » : flux RTSP standard de Dahua, identifiant admin, mot de passe = code de
--     sécurité (rangé dans video_source_secrets, illisible par l'application).
--   add_video_source accepte p_serial (paramètre ajouté à la fin : les anciennes versions de
--     l'application continuent de fonctionner).
-- =============================================================================

alter table public.video_sources
  add column if not exists serial text check (serial is null or serial ~ '^[A-Za-z0-9-]{4,40}$'),
  add column if not exists mac text check (mac is null or mac ~ '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$');
create unique index if not exists video_sources_home_serial_idx on public.video_sources (home_id, upper(serial)) where serial is not null;

alter table public.video_sources drop constraint if exists video_sources_driver_check;
alter table public.video_sources add constraint video_sources_driver_check check (driver in ('onvif', 'rtsp', 'dahua'));
alter table public.video_sources drop constraint if exists video_sources_check;
alter table public.video_sources add constraint video_sources_check check (
  (driver = 'onvif' and host is not null)
  or (driver = 'rtsp' and rtsp_url is not null)
  or (driver = 'dahua' and (serial is not null or host is not null))
);

drop function if exists public.add_video_source(uuid, text, text, text, text, integer, text, text, text, text, text, text, text, text, uuid);

create or replace function public.add_video_source(
  p_home_id      uuid,
  p_name         text,
  p_driver       text,
  p_category     text default 'camera',
  p_host         text default null,
  p_port         integer default null,
  p_rtsp_url     text default null,
  p_rtsp_sub_url text default null,
  p_snapshot_url text default null,
  p_username     text default null,
  p_password     text default null,
  p_manufacturer text default null,
  p_model        text default null,
  p_location     text default null,
  p_entrance_id  uuid default null,
  p_serial       text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_serial text := nullif(upper(btrim(coalesce(p_serial, ''))), '');
begin
  if not public.can_manage_video(p_home_id) then
    raise exception 'Réservé au propriétaire, à l''administrateur ou à l''installateur' using errcode = '42501';
  end if;
  if coalesce(p_rtsp_url, '') ~ '^rtsps?://[^/]*@' or coalesce(p_rtsp_sub_url, '') ~ '^rtsps?://[^/]*@'
     or coalesce(p_snapshot_url, '') ~ '^https?://[^/]*@' then
    raise exception 'IDENTIFIANTS_DANS_URL : saisissez l''identifiant et le mot de passe à part' using errcode = '22023';
  end if;
  if p_entrance_id is not null and not exists (
    select 1 from public.site_entrances e join public.homes h on h.site_id = e.site_id
    where e.id = p_entrance_id and h.id = p_home_id
  ) then
    raise exception 'Cette entrée n''appartient pas au site du logement' using errcode = '22023';
  end if;
  if v_serial is not null and exists (select 1 from public.video_sources where home_id = p_home_id and upper(serial) = v_serial) then
    raise exception 'CAMERA_DEJA_AJOUTEE : cette caméra est déjà dans le logement' using errcode = '23505';
  end if;
  insert into public.video_sources (home_id, name, category, driver, host, port, rtsp_url, rtsp_sub_url, snapshot_url,
                                    manufacturer, model, location, entrance_id, serial, credentials_updated_at)
  values (p_home_id, btrim(p_name), p_category, p_driver, nullif(btrim(coalesce(p_host, '')), ''),
          case when p_driver = 'onvif' then coalesce(p_port, 80) else p_port end,
          nullif(btrim(coalesce(p_rtsp_url, '')), ''), nullif(btrim(coalesce(p_rtsp_sub_url, '')), ''),
          nullif(btrim(coalesce(p_snapshot_url, '')), ''),
          coalesce(nullif(btrim(coalesce(p_manufacturer, '')), ''), case when p_driver = 'dahua' then 'Dahua' end),
          nullif(btrim(coalesce(p_model, '')), ''), nullif(btrim(coalesce(p_location, '')), ''), p_entrance_id, v_serial, now())
  returning id into v_id;
  insert into public.video_source_secrets (source_id, username, password)
  values (v_id, coalesce(nullif(p_username, ''), case when p_driver = 'dahua' then 'admin' end), nullif(p_password, ''));
  return v_id;
end $$;

revoke execute on function public.add_video_source(uuid, text, text, text, text, integer, text, text, text, text, text, text, text, text, uuid, text) from public, anon;
grant execute on function public.add_video_source(uuid, text, text, text, text, integer, text, text, text, text, text, text, text, text, uuid, text) to authenticated;
