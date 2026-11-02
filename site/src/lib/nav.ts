export const mainNav = [
  { key: "discover", href: "/discover" },
  { key: "devices", href: "/devices" },
  { key: "solutions", href: "/solutions" },
  { key: "automations", href: "/automations" },
  { key: "gateway", href: "/gateway" },
  { key: "partners", href: "/partners" },
] as const;

/** Toutes les pages publiques (sitemap, hreflang). */
export const publicPaths = ["", "/discover", "/devices", "/solutions", "/automations", "/gateway", "/partners", "/contact", "/shop", "/privacy"] as const;
