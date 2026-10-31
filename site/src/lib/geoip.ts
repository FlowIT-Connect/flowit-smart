import "server-only";
import path from "node:path";
import fs from "node:fs";
import maxmind, { type CountryResponse, type Reader } from "maxmind";

let reader: Promise<Reader<CountryResponse> | null> | undefined;

/** Ouvre une seule fois la base DB-IP / MaxMind si elle est présente. */
function open(): Promise<Reader<CountryResponse> | null> {
  if (!reader) {
    const file = process.env.GEOIP_DB
      ? path.resolve(/*turbopackIgnore: true*/ process.env.GEOIP_DB)
      : path.join(process.cwd(), "data", "dbip-country-lite.mmdb");
    reader = fs.existsSync(file) ? maxmind.open<CountryResponse>(file).catch(() => null) : Promise.resolve(null);
  }
  return reader;
}

export function clientIp(h: Headers): string | null {
  const fwd = h.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = fwd || h.get("x-real-ip") || null;
  return ip && maxmind.validate(ip) ? ip : null;
}

export async function countryFromIp(ip: string | null): Promise<string | null> {
  if (!ip) return null;
  const db = await open();
  return db?.get(ip)?.country?.iso_code ?? null;
}
