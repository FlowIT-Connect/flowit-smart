-- =============================================================================
-- Solea — préférences d'apparence (thème, arrière-plan, flou, transparence)
--
--   profiles.preferences : réglages de l'utilisateur, en JSON
--                          ({"appearance": {"theme": "blue_glass", …}}).
--   Bucket privé backgrounds : photo d'arrière-plan personnelle,
--                          chemin « <user_id>/bg-<horodatage>.<ext> »,
--                          visible et modifiable par l'utilisateur seul.
-- =============================================================================

alter table public.profiles
  add column if not exists preferences jsonb not null default '{}'::jsonb
    check (jsonb_typeof(preferences) = 'object' and pg_column_size(preferences) <= 16384);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('backgrounds', 'backgrounds', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Chemin valide : dossier = l'utilisateur lui-même.
create or replace function public.is_own_background(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_name ~ '^[0-9a-f-]{36}/bg-[0-9]+\.(jpg|jpeg|png|webp)$'
     and split_part(p_name, '/', 1) = auth.uid()::text
$$;
grant execute on function public.is_own_background(text) to authenticated;

drop policy if exists backgrounds_select on storage.objects;
drop policy if exists backgrounds_insert on storage.objects;
drop policy if exists backgrounds_update on storage.objects;
drop policy if exists backgrounds_delete on storage.objects;
create policy backgrounds_select on storage.objects for select to authenticated
  using (bucket_id = 'backgrounds' and public.is_own_background(name));
create policy backgrounds_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'backgrounds' and public.is_own_background(name));
create policy backgrounds_update on storage.objects for update to authenticated
  using (bucket_id = 'backgrounds' and public.is_own_background(name))
  with check (bucket_id = 'backgrounds' and public.is_own_background(name));
create policy backgrounds_delete on storage.objects for delete to authenticated
  using (bucket_id = 'backgrounds' and public.is_own_background(name));
