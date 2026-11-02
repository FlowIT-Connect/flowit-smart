-- =============================================================================
-- Solea — températures intelligentes (phase 4)
--
--   preheat     : la passerelle anticipe le prochain changement d'ambiance
--                 (programme, retour annoncé avec « Je rentre à 18 h ») pour que
--                 la pièce soit à la bonne température à l'heure prévue. Elle
--                 compte d'après l'écart entre la température mesurée et la
--                 consigne, et la météo (plus de marge quand il gèle dehors).
--   preheat_max : avance maximale, en minutes (0 à 240).
--   « Je pars » / « Je rentre » utilisent set_climate_preset (Absence pour la
--   maison, éventuellement jusqu'à l'heure du retour).
-- =============================================================================

alter table public.climate_settings
  add column if not exists preheat boolean not null default true,
  add column if not exists preheat_max integer not null default 120;

do $$ begin
  alter table public.climate_settings add constraint climate_settings_preheat_max_check
    check (preheat_max between 0 and 240);
exception when duplicate_object then null;
end $$;
