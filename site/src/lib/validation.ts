/** Contrôles partagés par les formulaires (appliqués côté serveur, rejoués en SQL). */
export const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]{1,64}@[A-Za-z0-9.-]{1,253}\.[A-Za-z]{2,24}$/;
export const PHONE_RE = /^\+?[0-9][0-9 ().-]{5,19}$/;
export const COUNTRY_RE = /^([A-Z]{2}|INT)$/;

export const clean = (v: FormDataEntryValue | null, max = 200) =>
  typeof v === "string" ? v.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "").trim().slice(0, max) : "";

export const isEmail = (v: string) => v.length <= 254 && EMAIL_RE.test(v);
export const isPhone = (v: string) => PHONE_RE.test(v);
