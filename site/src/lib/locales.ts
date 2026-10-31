/**
 * Langues, pays et devises du site.
 * Ajouter une langue : l'ajouter à `locales`, créer messages/<code>.json, c'est tout.
 */
export const locales = ["fr", "en", "ar", "es", "de", "it"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "fr";
export const rtlLocales: readonly Locale[] = ["ar"];

export const localeNames: Record<Locale, string> = {
  fr: "Français",
  en: "English",
  ar: "العربية",
  es: "Español",
  de: "Deutsch",
  it: "Italiano",
};

/** Tag BCP 47 utilisé pour formater dates et prix (chiffres latins en arabe, plus lisibles pour les prix). */
export const intlTag: Record<Locale, string> = {
  fr: "fr-FR",
  en: "en-GB",
  ar: "ar-DZ-u-nu-latn",
  es: "es-ES",
  de: "de-DE",
  it: "it-IT",
};

export const isLocale = (v: unknown): v is Locale => typeof v === "string" && (locales as readonly string[]).includes(v);
export const dirOf = (l: Locale) => (rtlLocales.includes(l) ? "rtl" : "ltr");

export const currencies = ["DZD", "EUR", "USD", "GBP", "SAR", "AED", "CAD", "CHF"] as const;
export type Currency = (typeof currencies)[number];
export const isCurrency = (v: unknown): v is Currency => typeof v === "string" && (currencies as readonly string[]).includes(v);

/**
 * Pays proposés. `locales` : langues possibles par ordre de préférence (la première sert
 * par défaut, le navigateur peut choisir une autre de la liste). Liste extensible.
 */
export type CountryInfo = { code: string; locales: Locale[]; currency: Currency };
export const countries: CountryInfo[] = [
  { code: "DZ", locales: ["fr", "ar"], currency: "DZD" },
  { code: "MA", locales: ["fr", "ar"], currency: "EUR" },
  { code: "TN", locales: ["fr", "ar"], currency: "EUR" },
  { code: "FR", locales: ["fr"], currency: "EUR" },
  { code: "BE", locales: ["fr", "de"], currency: "EUR" },
  { code: "CH", locales: ["fr", "de", "it"], currency: "CHF" },
  { code: "LU", locales: ["fr", "de"], currency: "EUR" },
  { code: "CA", locales: ["en", "fr"], currency: "CAD" },
  { code: "US", locales: ["en", "es"], currency: "USD" },
  { code: "GB", locales: ["en"], currency: "GBP" },
  { code: "IE", locales: ["en"], currency: "EUR" },
  { code: "DE", locales: ["de"], currency: "EUR" },
  { code: "AT", locales: ["de"], currency: "EUR" },
  { code: "ES", locales: ["es"], currency: "EUR" },
  { code: "IT", locales: ["it"], currency: "EUR" },
  { code: "PT", locales: ["en", "es"], currency: "EUR" },
  { code: "NL", locales: ["en", "de"], currency: "EUR" },
  { code: "SA", locales: ["ar", "en"], currency: "SAR" },
  { code: "AE", locales: ["ar", "en"], currency: "AED" },
  { code: "QA", locales: ["ar", "en"], currency: "USD" },
  { code: "KW", locales: ["ar", "en"], currency: "USD" },
  { code: "EG", locales: ["ar", "en"], currency: "USD" },
  { code: "MX", locales: ["es"], currency: "USD" },
];
export const findCountry = (code?: string | null) =>
  code ? countries.find((c) => c.code === code.toUpperCase()) : undefined;

/** Pays par défaut si rien n'est détecté. */
export const fallbackCountry: CountryInfo = { code: "INT", locales: ["en"], currency: "EUR" };

export type Suggestion = { country: string; locale: Locale; currency: Currency };

/**
 * Langue des préférences du navigateur (« fr-DZ,ar;q=0.8,en;q=0.5 ») triées par poids.
 * Exporté pour les tests.
 */
export function parseAcceptLanguage(header: string | null | undefined): { lang: string; region?: string }[] {
  if (!header) return [];
  return header
    .split(",")
    .map((part) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
      const weight = q ? Number(q.slice(2)) : 1;
      const [lang, region] = tag.toLowerCase().split("-");
      return { lang, region: region?.toUpperCase(), weight: Number.isFinite(weight) ? weight : 0 };
    })
    .filter((x) => x.lang && x.lang !== "*" && x.weight > 0)
    .sort((a, b) => b.weight - a.weight)
    .map(({ lang, region }) => ({ lang, region }));
}

/**
 * Propose langue et devise à partir du pays (IP) et des langues du navigateur.
 * Ex. : Algérie + navigateur arabe → ar / DZD ; Algérie + navigateur français → fr / DZD.
 */
export function suggest(countryCode: string | null | undefined, acceptLanguage: string | null | undefined): Suggestion {
  const prefs = parseAcceptLanguage(acceptLanguage);
  const country = findCountry(countryCode) ?? findCountry(prefs.find((p) => p.region)?.region);
  if (country) {
    const fromBrowser = prefs.map((p) => p.lang).find((l) => country.locales.includes(l as Locale)) as Locale | undefined;
    return { country: country.code, locale: fromBrowser ?? country.locales[0], currency: country.currency };
  }
  const browserLocale = prefs.map((p) => p.lang).find(isLocale);
  return { country: fallbackCountry.code, locale: browserLocale ?? "en", currency: fallbackCountry.currency };
}
