-- Historique des caméras : relecture de la carte mémoire (Dahua Hero, caméras IP Dahua).
--
--   video_recording_queries : l'application demande les heures enregistrées d'une journée,
--     le boîtier vidéo interroge la caméra et répond dans « slots ».
--   video_sessions : une session peut maintenant relire un passage enregistré
--     (quality = 'playback', playback_start / playback_end), avec la même signalisation WebRTC
--     que le direct. Rien n'est copié hors de la maison : la vidéo reste sur la carte mémoire.

-- -----------------------------------------------------------------------------
-- Sessions : relecture d'un passage enregistré
-- -----------------------------------------------------------------------------
alter table public.video_sessions add column if not exists playback_start timestamptz;
alter table public.video_sessions add column if not exists playback_end timestamptz;
alter table public.video_sessions drop constraint if exists video_sessions_quality_check;
alter table public.video_sessions add constraint video_sessions_quality_check check (quality in ('main', 'sub', 'playback'));
alter table public.video_sessions drop constraint if exists video_sessions_playback_check;
alter table public.video_sessions add constraint video_sessions_playback_check check (
  (quality = 'playback') = (playback_start is not null)
  and (playback_end is null or (playback_end > playback_start and playback_end <= playback_start + interval '3 hours'))
);

-- -----------------------------------------------------------------------------
-- Heures enregistrées sur la carte mémoire
-- -----------------------------------------------------------------------------
create table if not exists public.video_recording_queries (
  id           uuid primary key default gen_random_uuid(),
  home_id      uuid not null references public.homes (id) on delete cascade,
  device_id    uuid not null references public.devices (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade default auth.uid(),
  day          date not null,
  status       text not null default 'pending' check (status in ('pending', 'done', 'failed')),
  slots        jsonb not null default '[]'::jsonb,
  error        text,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index if not exists video_recording_queries_home_idx on public.video_recording_queries (home_id, status, created_at desc);
alter table public.video_recording_queries enable row level security;
revoke insert, update, delete on public.video_recording_queries from anon, authenticated;
drop policy if exists video_recording_queries_select on public.video_recording_queries;
create policy video_recording_queries_select on public.video_recording_queries for select to authenticated
  using (user_id = auth.uid());

-- Même règle que la vidéo : seuls les membres autorisés sur la caméra voient son historique.
create or replace function public.request_video_recordings(p_device_id uuid, p_day date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_home uuid; v_id uuid;
begin
  select home_id into v_home from public.devices where id = p_device_id;
  if v_home is null or not public.can_use_device(p_device_id) then
    raise exception 'Accès refusé à cette caméra' using errcode = '42501';
  end if;
  if p_day > current_date + 1 or p_day < current_date - 366 then
    raise exception 'Jour invalide' using errcode = '22023';
  end if;
  -- La même demande en cours est rendue telle quelle ; 20 demandes par minute au plus.
  select id into v_id from public.video_recording_queries
   where user_id = auth.uid() and device_id = p_device_id and day = p_day and status = 'pending'
     and created_at > now() - interval '1 minute'
   order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.video_recording_queries where user_id = auth.uid() and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'TROP_DE_DEMANDES_VIDEO : réessayez dans une minute' using errcode = '54000';
  end if;
  delete from public.video_recording_queries where home_id = v_home and created_at < now() - interval '1 day';
  insert into public.video_recording_queries (home_id, device_id, day) values (v_home, p_device_id, p_day) returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.request_video_recordings(uuid, date) from public, anon;
grant execute on function public.request_video_recordings(uuid, date) to authenticated;

-- Temps réel : le boîtier voit les demandes tout de suite.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'video_recording_queries') then
    alter publication supabase_realtime add table public.video_recording_queries;
  end if;
end $$;
