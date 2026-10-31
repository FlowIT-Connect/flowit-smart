"use server";
import { headers } from "next/headers";
import { isLocale } from "@/lib/locales";
import { partnerActivities, projectTypes } from "@/lib/catalog";
import { clean, COUNTRY_RE, isEmail, isPhone } from "@/lib/validation";

export type FormState = { ok: boolean; error?: "required" | "email" | "phone" | "consent" | "tooMany" | "notConfigured" | "server" } | null;

/* Limite simple par adresse IP (en mémoire, par instance) : 6 envois / 10 min. */
const hits = new Map<string, number[]>();
function throttled(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 10 * 60_000);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > 6;
}

async function context() {
  const h = await headers();
  const ip = h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "local";
  return { ip };
}

/** Appelle une fonction SQL publique du projet Supabase du site (clé publique seulement). */
async function rpc(fn: string, args: Record<string, unknown>): Promise<FormState> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return { ok: false, error: "notConfigured" };
  try {
    const res = await fetch(`${url.replace(/\/$/, "")}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
      cache: "no-store",
    });
    if (res.ok) return { ok: true };
    const body = await res.text();
    if (body.includes("too_many")) return { ok: false, error: "tooMany" };
    if (body.includes("invalid_email")) return { ok: false, error: "email" };
    console.error(`[forms] ${fn} ${res.status}: ${body.slice(0, 300)}`);
    return { ok: false, error: "server" };
  } catch (e) {
    console.error(`[forms] ${fn}`, e);
    return { ok: false, error: "server" };
  }
}

function common(fd: FormData) {
  return {
    honeypot: clean(fd.get("website")),
    email: clean(fd.get("email"), 254).toLowerCase(),
    country: clean(fd.get("country"), 3).toUpperCase(),
    locale: clean(fd.get("locale"), 5),
  };
}

export async function submitGateway(_: FormState, fd: FormData): Promise<FormState> {
  const { honeypot, email, country, locale } = common(fd);
  if (honeypot) return { ok: true }; // robot : on fait semblant
  const preferred = clean(fd.get("preferred_locale"), 5);
  if (!email || !country || !preferred) return { ok: false, error: "required" };
  if (!isEmail(email)) return { ok: false, error: "email" };
  if (!COUNTRY_RE.test(country) || !isLocale(preferred) || !isLocale(locale)) return { ok: false, error: "required" };
  if (fd.get("consent_launch") !== "on") return { ok: false, error: "consent" };
  if (throttled((await context()).ip)) return { ok: false, error: "tooMany" };
  return rpc("submit_gateway_signup", {
    p_email: email,
    p_country: country,
    p_locale: preferred,
    p_marketing: fd.get("consent_marketing") === "on",
    p_source_locale: locale,
  });
}

export async function submitContact(_: FormState, fd: FormData): Promise<FormState> {
  const { honeypot, email, country, locale } = common(fd);
  if (honeypot) return { ok: true };
  const first = clean(fd.get("first_name"), 80);
  const last = clean(fd.get("last_name"), 80);
  const phone = clean(fd.get("phone"), 24);
  const type = clean(fd.get("project_type"), 20);
  const message = clean(fd.get("message"), 4000);
  if (!first || !last || !email || !country || !type || message.length < 5) return { ok: false, error: "required" };
  if (!isEmail(email)) return { ok: false, error: "email" };
  if (phone && !isPhone(phone)) return { ok: false, error: "phone" };
  if (!COUNTRY_RE.test(country) || !(projectTypes as readonly string[]).includes(type) || !isLocale(locale)) return { ok: false, error: "required" };
  if (throttled((await context()).ip)) return { ok: false, error: "tooMany" };
  return rpc("submit_contact_request", {
    p_first_name: first,
    p_last_name: last,
    p_email: email,
    p_phone: phone || null,
    p_country: country,
    p_project_type: type,
    p_message: message,
    p_locale: locale,
    p_marketing: fd.get("consent_marketing") === "on",
  });
}

export async function submitPartner(_: FormState, fd: FormData): Promise<FormState> {
  const { honeypot, email, country, locale } = common(fd);
  if (honeypot) return { ok: true };
  const name = clean(fd.get("name"), 120);
  const company = clean(fd.get("company"), 160);
  const activity = clean(fd.get("activity"), 20);
  const phone = clean(fd.get("phone"), 24);
  const message = clean(fd.get("message"), 4000);
  if (!name || !company || !email || !country || !activity || !phone) return { ok: false, error: "required" };
  if (!isEmail(email)) return { ok: false, error: "email" };
  if (!isPhone(phone)) return { ok: false, error: "phone" };
  if (!COUNTRY_RE.test(country) || !(partnerActivities as readonly string[]).includes(activity) || !isLocale(locale)) return { ok: false, error: "required" };
  if (throttled((await context()).ip)) return { ok: false, error: "tooMany" };
  return rpc("submit_partner_request", {
    p_name: name,
    p_company: company,
    p_activity: activity,
    p_email: email,
    p_phone: phone,
    p_country: country,
    p_message: message || null,
    p_locale: locale,
    p_marketing: fd.get("consent_marketing") === "on",
  });
}
