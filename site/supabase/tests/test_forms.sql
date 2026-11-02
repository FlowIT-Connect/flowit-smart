\set ON_ERROR_STOP 1
\set QUIET 1
create or replace function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if not ok then raise exception 'ÉCHEC: %', label; end if;
  raise notice 'OK: %', label;
end $$;
create or replace function pg_temp.try_sql(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlerrm; end $$;

set role anon;
select public.submit_gateway_signup('Baziz@Example.com', 'DZ', 'fr', false, 'fr');
select public.submit_gateway_signup('baziz@example.com', 'FR', 'ar', true, 'ar');
reset role;
select pg_temp.check((select count(*) from gateway_waitlist) = 1, 'gateway : réinscription = mise à jour, pas de doublon');
select pg_temp.check((select country || locale from gateway_waitlist) = 'FRar', 'gateway : pays et langue mis à jour');
select pg_temp.check((select consent_marketing and marketing_consent_at is not null from gateway_waitlist), 'gateway : consentement commercial daté');

set role anon;
select pg_temp.check(pg_temp.try_sql($$select public.submit_gateway_signup('pas-un-email', 'DZ', 'fr')$$) like '%invalid_email%', 'gateway : e-mail invalide refusé');
select pg_temp.check(pg_temp.try_sql($$select public.submit_gateway_signup('a@b.dz', 'Algeria', 'fr')$$) like '%invalid_input%', 'gateway : pays invalide refusé');
select pg_temp.check(pg_temp.try_sql($$select public.submit_gateway_signup('a@b.dz', 'DZ', 'zz')$$) like '%invalid_input%', 'gateway : langue invalide refusée');
select pg_temp.check(pg_temp.try_sql('select * from public.gateway_waitlist') like '%permission denied%', 'gateway : un visiteur ne peut pas lire la liste');
select pg_temp.check(pg_temp.try_sql($$insert into public.gateway_waitlist (email, country, locale) values ('x@y.fr', 'FR', 'fr')$$) like '%permission denied%', 'gateway : pas d''insertion directe');

select public.submit_contact_request('Amina', 'B.', 'amina@example.dz', '+213 555 12 34 56', 'DZ', 'villa', 'Villa de 300 m², éclairage et caméras.', 'fr', false);
select pg_temp.check(pg_temp.try_sql($$select public.submit_contact_request('A', 'B', 'amina@example.dz', 'abc', 'DZ', 'villa', 'Bonjour à vous', 'fr')$$) like '%contact_requests_phone_check%', 'contact : téléphone invalide refusé');
select pg_temp.check(pg_temp.try_sql($$select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'yacht', 'Bonjour à vous', 'fr')$$) like '%project_type%', 'contact : type de projet inconnu refusé');
select pg_temp.check(pg_temp.try_sql($$select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'villa', 'Hi', 'fr')$$) like '%message%', 'contact : message trop court refusé');
select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'security', 'Message numéro deux', 'fr');
select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'security', 'Message numéro trois', 'fr');
select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'security', 'Message numéro quatre', 'fr');
select public.submit_contact_request('A', 'B', 'amina@example.dz', null, 'DZ', 'security', 'Message numéro cinq', 'fr');
select pg_temp.check(pg_temp.try_sql($$select public.submit_contact_request('A', 'B', 'AMINA@example.dz', null, 'DZ', 'security', 'Message numéro six', 'fr')$$) like '%too_many%', 'contact : limite de 5 demandes par heure et par adresse');
select pg_temp.check(pg_temp.try_sql('select * from public.contact_requests') like '%permission denied%', 'contact : un visiteur ne peut pas lire les demandes');

select public.submit_partner_request('Karim', 'Elec Pro', 'electrician', 'karim@elecpro.dz', '+213661000000', 'DZ', null, 'ar', true);
select pg_temp.check(pg_temp.try_sql($$select public.submit_partner_request('K', 'E', 'astronaut', 'k@e.dz', '+213661000000', 'DZ', null, 'fr')$$) like '%activity%', 'partenaire : activité inconnue refusée');
select pg_temp.check(pg_temp.try_sql('select * from public.partner_requests') like '%permission denied%', 'partenaire : un visiteur ne peut pas lire les demandes');
reset role;
select pg_temp.check((select count(*) from contact_requests) = 5 and (select count(*) from partner_requests) = 1, 'demandes enregistrées');
select pg_temp.check((select bool_and(relrowsecurity) from pg_class where relname in ('gateway_waitlist', 'contact_requests', 'partner_requests')), 'RLS active sur les trois tables');
