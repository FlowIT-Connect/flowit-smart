/** Pays donné par un proxy ou un CDN placé devant le site (Cloudflare, Netlify, Nginx GeoIP, Caddy…). */
export function countryFromHeaders(h: Headers): string | null {
  for (const name of ["cf-ipcountry", "x-country", "x-country-code", "x-vercel-ip-country", "cloudfront-viewer-country"]) {
    const v = h.get(name);
    if (v && /^[A-Za-z]{2}$/.test(v) && v.toUpperCase() !== "XX") return v.toUpperCase();
  }
  // Netlify : en-tête x-nf-geo = JSON encodé en base64 ({"country":{"code":"DZ"}, ...}).
  const geo = h.get("x-nf-geo");
  if (geo) {
    try {
      const code = JSON.parse(atob(geo))?.country?.code;
      if (typeof code === "string" && /^[A-Za-z]{2}$/.test(code)) return code.toUpperCase();
    } catch {
      /* en-tête illisible : on ignore */
    }
  }
  return null;
}
