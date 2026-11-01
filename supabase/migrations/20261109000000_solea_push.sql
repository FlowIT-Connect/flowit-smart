-- =============================================================================
-- Solea — notifications push (application fermée)
--
--   notifications.pushed_at : heure d'envoi push (une seule fois par notification)
--   private.settings        : réglages serveur non lisibles par les clients
--       push_url = adresse de la fonction send-push
--                  (https://<projet>.supabase.co/functions/v1/send-push)
--   trg_notifications_push  : chaque nouvelle notification (sauf priorité basse)
--       appelle la fonction send-push par pg_net, sans ralentir l'écriture.
--       Sans pg_net ou sans push_url, rien n'est envoyé et rien ne casse.
-- =============================================================================

alter table public.notifications add column if not exists pushed_at timestamptz;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (
  key   text primary key,
  value text not null
);
revoke all on private.settings from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net indisponible : notifications push désactivées (%)', sqlerrm;
end $$;

create or replace function public.trg_notifications_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
begin
  if new.priority = 'low' then return new; end if;
  select value into v_url from private.settings where key = 'push_url';
  if v_url is null or to_regnamespace('net') is null then return new; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 5000)'
    using v_url, jsonb_build_object('id', new.id), '{"Content-Type": "application/json"}'::jsonb;
  return new;
exception when others then
  raise warning 'push non envoyé pour la notification % : %', new.id, sqlerrm;
  return new;
end $$;
revoke execute on function public.trg_notifications_push() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row execute function public.trg_notifications_push();
