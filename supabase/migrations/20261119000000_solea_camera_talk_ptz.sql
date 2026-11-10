-- Caméras : parler à travers la caméra et l'orienter depuis Solea (comme l'application de la caméra).
--
--   video_sessions : une session peut maintenant envoyer le micro du téléphone vers le
--     haut-parleur de la caméra (quality = 'talk'). Même signalisation WebRTC que le direct ;
--     le boîtier vidéo relaie la voix vers la caméra sur le réseau de la maison.
--   video_ptz_commands : ordres d'orientation (déplacer, arrêter, aller au point favori),
--     déposés par l'application via camera_ptz() et exécutés par le boîtier vidéo.

-- -----------------------------------------------------------------------------
-- Sessions : parler à travers la caméra
-- -----------------------------------------------------------------------------
alter table public.video_sessions drop constraint if exists video_sessions_quality_check;
alter table public.video_sessions add constraint video_sessions_quality_check check (quality in ('main', 'sub', 'playback', 'talk'));

-- -----------------------------------------------------------------------------
-- Orientation (PTZ)
-- -----------------------------------------------------------------------------
create table if not exists public.video_ptz_commands (
  id           uuid primary key default gen_random_uuid(),
  home_id      uuid not null references public.homes (id) on delete cascade,
  device_id    uuid not null references public.devices (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade default auth.uid(),
  action       text not null check (action in ('move', 'stop', 'preset')),
  pan          real not null default 0 check (pan between -1 and 1),
  tilt         real not null default 0 check (tilt between -1 and 1),
  preset       text check (preset is null or preset ~ '^[A-Za-z0-9_.-]{1,32}$'),
  status       text not null default 'pending' check (status in ('pending', 'done', 'failed')),
  error        text,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index if not exists video_ptz_commands_home_idx on public.video_ptz_commands (home_id, status, created_at desc);
alter table public.video_ptz_commands enable row level security;
revoke insert, update, delete on public.video_ptz_commands from anon, authenticated;
drop policy if exists video_ptz_commands_select on public.video_ptz_commands;
create policy video_ptz_commands_select on public.video_ptz_commands for select to authenticated
  using (user_id = auth.uid());

-- Seuls les membres autorisés sur la caméra peuvent l'orienter ; 240 ordres par minute au plus
-- (l'application renouvelle « déplacer » toutes les 0,7 s tant que le doigt reste appuyé).
create or replace function public.camera_ptz(p_device_id uuid, p_action text, p_pan real default 0, p_tilt real default 0, p_preset text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_home uuid; v_id uuid;
begin
  select home_id into v_home from public.devices where id = p_device_id;
  if v_home is null or not public.can_use_device(p_device_id) then
    raise exception 'Accès refusé à cette caméra' using errcode = '42501';
  end if;
  if (select count(*) from public.video_ptz_commands where user_id = auth.uid() and created_at > now() - interval '1 minute') >= 240 then
    raise exception 'TROP_DE_DEMANDES_VIDEO : réessayez dans une minute' using errcode = '54000';
  end if;
  delete from public.video_ptz_commands where home_id = v_home and created_at < now() - interval '1 hour';
  insert into public.video_ptz_commands (home_id, device_id, action, pan, tilt, preset)
  values (v_home, p_device_id, p_action, coalesce(p_pan, 0), coalesce(p_tilt, 0), p_preset) returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.camera_ptz(uuid, text, real, real, text) from public, anon;
grant execute on function public.camera_ptz(uuid, text, real, real, text) to authenticated;

-- Temps réel : le boîtier reçoit les ordres tout de suite.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'video_ptz_commands') then
    alter publication supabase_realtime add table public.video_ptz_commands;
  end if;
end $$;
