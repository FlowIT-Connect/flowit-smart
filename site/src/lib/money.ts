import { intlTag, type Currency, type Locale } from "./locales.ts";

/**
 * Taux indicatifs de départ (1 EUR = x). Ils seront remplacés par la table des devises
 * administrable (lot 4). Les montants convertis restent indicatifs : le prix facturé est
 * fixé à la commande dans une devise de facturation activée.
 */
export const fallbackRates: Record<Currency, number> = {
  EUR: 1,
  DZD: 150,
  USD: 1.08,
  GBP: 0.85,
  SAR: 4.05,
  AED: 3.97,
  CAD: 1.5,
  CHF: 0.95,
};

/** Pas d'arrondi par devise (ex. DZD à 10 près). */
export const roundingStep: Record<Currency, number> = {
  EUR: 0.01, USD: 0.01, GBP: 0.01, CAD: 0.01, CHF: 0.05, SAR: 0.01, AED: 0.01, DZD: 10,
};

export function convert(amount: number, from: Currency, to: Currency, rates = fallbackRates): number {
  const eur = amount / rates[from];
  const raw = eur * rates[to];
  const step = roundingStep[to];
  return Math.round(raw / step) * step;
}

export function formatPrice(amount: number, currency: Currency, locale: Locale): string {
  const digits = currency === "DZD" ? 0 : 2;
  return new Intl.NumberFormat(intlTag[locale], {
    style: "currency",
    currency,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(amount);
}
