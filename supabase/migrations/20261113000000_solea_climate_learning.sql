-- =============================================================================
-- Solea — préchauffage qui apprend
--
--   heat_rate / cool_rate : minutes par degré mesurées par la passerelle pour
--   chaque pièce (chauffage / clim), hors marge météo. Null tant que rien
--   n'a été mesuré : 15 min/°C en chauffage, 10 en clim par défaut.
-- =============================================================================

alter table public.climate_zones
  add column if not exists heat_rate numeric(4, 1),
  add column if not exists cool_rate numeric(4, 1);

do $$ begin
  alter table public.climate_zones add constraint climate_zones_rates_check
    check ((heat_rate is null or heat_rate between 1 and 120) and (cool_rate is null or cool_rate between 1 and 120));
exception when duplicate_object then null;
end $$;
