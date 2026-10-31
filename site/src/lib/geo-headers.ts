/** Pays donné par un proxy ou un CDN placé devant le site (Cloudflare, Nginx GeoIP, Caddy…). */
export function countryFromHeaders(h: Headers): string | null {
  for (const name of ["cf-ipcountry", "x-country-code", "x-vercel-ip-country", "cloudfront-viewer-country"]) {
    const v = h.get(name);
    if (v && /^[A-Za-z]{2}$/.test(v) && v.toUpperCase() !== "XX") return v.toUpperCase();
  }
  return null;
}
