"use client";
import { isCurrency, type Currency } from "./locales";

const YEAR = 60 * 60 * 24 * 365;

export function readCookie(name: string): string | null {
  if (typeof document === "undefined") return null;
  const m = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`));
  return m ? decodeURIComponent(m[1]) : null;
}

export function writeCookie(name: string, value: string) {
  const secure = location.protocol === "https:" ? "; Secure" : "";
  document.cookie = `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${YEAR}; SameSite=Lax${secure}`;
}

export type Prefs = { country: string | null; currency: Currency | null; answered: boolean };

export function readPrefs(): Prefs {
  const c = readCookie("solea_currency");
  return { country: readCookie("solea_country"), currency: isCurrency(c) ? c : null, answered: readCookie("solea_prefs") === "1" };
}

export function savePrefs(p: { country: string; currency: Currency }) {
  writeCookie("solea_country", p.country);
  writeCookie("solea_currency", p.currency);
  writeCookie("solea_prefs", "1");
  window.dispatchEvent(new CustomEvent("solea:prefs"));
}

export function regionName(code: string, locale: string, otherLabel: string): string {
  if (code === "INT") return otherLabel;
  try {
    return new Intl.DisplayNames([locale], { type: "region" }).of(code) ?? code;
  } catch {
    return code;
  }
}
