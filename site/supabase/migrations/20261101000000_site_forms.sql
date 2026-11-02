-- Site Solea (projet Supabase DÉDIÉ au site, pas celui de l'app) — lot 1 : formulaires publics.
-- Préinscriptions Solea Gateway, demandes de contact / devis / étude, demandes de partenariat.
-- Les visiteurs n'ont AUCUN accès direct aux tables : ils passent par trois fonctions qui
-- valident les données et limitent les envois. La lecture se fera depuis l'administration (lot 4).

create extension if not exists citext;

-- Langues et pays acceptés (gardés en texte pour pouvoir en ajouter sans migration lourde).
create or replace function public.site_valid_locale(p text) returns boolean
language sql immutable as $$ select p in ('fr', 'en', 'ar', 'es', 'de', 'it') $$;

create or replace function public.site_valid_country(p text) returns boolean
language sql immutable as $$ select p ~ '^([A-Z]{2}|INT)$' $$;

create or replace function public.site_valid_email(p text) returns boolean
language sql immutable as $$
  select p is not null and length(p) <= 254
     and p ~ '^[^[:space:]@<>()\[\]\\,;:"]{1,64}@[A-Za-z0-9.-]{1,253}\.[A-Za-z]{2,24}$'
$$;

-- ── Préinscriptions Solea Gateway ─────────────────────────────────────────────
create table if not exists public.gateway_waitlist (
  id                uuid primary key default gen_random_uuid(),
  email             citext not null unique,
  country           text not null check (public.site_valid_country(country)),
  locale            text not null check (public.site_valid_locale(locale)),
  consent_launch_at timestamptz not null default now(),
  consent_marketing boolean not null default false,
  marketing_consent_at timestamptz,
  source_locale     text check (source_locale is null or public.site_valid_locale(source_locale)),
  status            text not null default 'active' check (status in ('active', 'unsubscribed', 'notified')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists gateway_waitlist_country_idx on public.gateway_waitlist (country);
alter table public.gateway_waitlist enable row level security;

-- ── Demandes de contact, de devis et d'étude ──────────────────────────────────
create table if not exists public.contact_requests (
  id                uuid primary key default gen_random_uuid(),
  first_name        text not null check (length(first_name) between 1 and 80),
  last_name         text not null check (length(last_name) between 1 and 80),
  email             citext not null check (public.site_valid_email(email::text)),
  phone             text check (phone is null or phone ~ '^\+?[0-9][0-9 ().-]{5,19}$'),
  country           text not null check (public.site_valid_country(country)),
  project_type      text not null check (project_type in ('villa', 'apartment', 'residence', 'business', 'installation', 'security', 'intercom', 'partnership')),
  message           text not null check (length(message) between 5 and 4000),
  locale            text not null check (public.site_valid_locale(locale)),
  consent_marketing boolean not null default false,
  status            text not null default 'new' check (status in ('new', 'in_progress', 'answered', 'closed', 'spam')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists contact_requests_created_idx on public.contact_requests (created_at desc);
create index if not exists contact_requests_email_idx on public.contact_requests (email, created_at desc);
alter table public.contact_requests enable row level security;

-- ── Demandes de partenariat ───────────────────────────────────────────────────
create table if not exists public.partner_requests (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (length(name) between 1 and 120),
  company           text not null check (length(company) between 1 and 160),
  activity          text not null check (activity in ('reseller', 'installer', 'electrician', 'security', 'integrator', 'developer', 'construction', 'other')),
  email             citext not null check (public.site_valid_email(email::text)),
  phone             text not null check (phone ~ '^\+?[0-9][0-9 ().-]{5,19}$'),
  country           text not null check (public.site_valid_country(country)),
  message           text check (message is null or length(message) <= 4000),
  locale            text not null check (public.site_valid_locale(locale)),
  consent_marketing boolean not null default false,
  status            text not null default 'new' check (status in ('new', 'in_progress', 'accepted', 'declined', 'spam')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists partner_requests_email_idx on public.partner_requests (email, created_at desc);
alter table public.partner_requests enable row level security;

-- Aucun droit direct pour les visiteurs (les fonctions ci-dessous sont SECURITY DEFINER).
revoke all on public.gateway_waitlist, public.contact_requests, public.partner_requests from anon, authenticated;

create or replace function public.site_touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists gateway_waitlist_touch on public.gateway_waitlist;
create trigger gateway_waitlist_touch before update on public.gateway_waitlist for each row execute function public.site_touch_updated_at();
drop trigger if exists contact_requests_touch on public.contact_requests;
create trigger contact_requests_touch before update on public.contact_requests for each row execute function public.site_touch_updated_at();
drop trigger if exists partner_requests_touch on public.partner_requests;
create trigger partner_requests_touch before update on public.partner_requests for each row execute function public.site_touch_updated_at();

-- ── Fonctions appelées par le site ────────────────────────────────────────────

-- Préinscription : idempotente (réinscrire la même adresse met à jour pays, langue, consentement).
create or replace function public.submit_gateway_signup(
  p_email text, p_country text, p_locale text, p_marketing boolean default false, p_source_locale text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email));
begin
  if not public.site_valid_email(v_email) then raise exception 'invalid_email'; end if;
  if not public.site_valid_country(p_country) or not public.site_valid_locale(p_locale) then raise exception 'invalid_input'; end if;
  -- Anti-abus global : au plus 200 inscriptions par 10 minutes.
  if (select count(*) from public.gateway_waitlist where created_at > now() - interval '10 minutes') >= 200 then
    raise exception 'too_many';
  end if;
  insert into public.gateway_waitlist (email, country, locale, consent_marketing, marketing_consent_at, source_locale)
  values (v_email, p_country, p_locale, coalesce(p_marketing, false), case when p_marketing then now() end,
          case when public.site_valid_locale(p_source_locale) then p_source_locale end)
  on conflict (email) do update set
    country = excluded.country,
    locale = excluded.locale,
    consent_launch_at = now(),
    consent_marketing = public.gateway_waitlist.consent_marketing or excluded.consent_marketing,
    marketing_consent_at = coalesce(public.gateway_waitlist.marketing_consent_at, excluded.marketing_consent_at),
    status = 'active';
end $$;

create or replace function public.submit_contact_request(
  p_first_name text, p_last_name text, p_email text, p_phone text, p_country text,
  p_project_type text, p_message text, p_locale text, p_marketing boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email));
begin
  if not public.site_valid_email(v_email) then raise exception 'invalid_email'; end if;
  -- Au plus 5 demandes par adresse et par heure.
  if (select count(*) from public.contact_requests where email = v_email::citext and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too_many';
  end if;
  insert into public.contact_requests (first_name, last_name, email, phone, country, project_type, message, locale, consent_marketing)
  values (trim(p_first_name), trim(p_last_name), v_email, nullif(trim(p_phone), ''), p_country, p_project_type, trim(p_message), p_locale, coalesce(p_marketing, false));
end $$;

create or replace function public.submit_partner_request(
  p_name text, p_company text, p_activity text, p_email text, p_phone text, p_country text,
  p_message text, p_locale text, p_marketing boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email));
begin
  if not public.site_valid_email(v_email) then raise exception 'invalid_email'; end if;
  if (select count(*) from public.partner_requests where email = v_email::citext and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'too_many';
  end if;
  insert into public.partner_requests (name, company, activity, email, phone, country, message, locale, consent_marketing)
  values (trim(p_name), trim(p_company), p_activity, v_email, trim(p_phone), p_country, nullif(trim(p_message), ''), p_locale, coalesce(p_marketing, false));
end $$;

revoke all on function public.submit_gateway_signup(text, text, text, boolean, text) from public;
revoke all on function public.submit_contact_request(text, text, text, text, text, text, text, text, boolean) from public;
revoke all on function public.submit_partner_request(text, text, text, text, text, text, text, text, boolean) from public;
grant execute on function public.submit_gateway_signup(text, text, text, boolean, text) to anon, authenticated;
grant execute on function public.submit_contact_request(text, text, text, text, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.submit_partner_request(text, text, text, text, text, text, text, text, boolean) to anon, authenticated;
