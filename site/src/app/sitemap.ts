import type { MetadataRoute } from "next";
import { locales } from "@/lib/locales";
import { publicPaths } from "@/lib/nav";
import { siteUrl } from "@/lib/seo";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return publicPaths.flatMap((path) =>
    locales.map((l) => ({
      url: `${siteUrl}/${l}${path}`,
      lastModified: now,
      changeFrequency: path === "" ? "weekly" : "monthly",
      priority: path === "" ? 1 : 0.7,
      alternates: { languages: Object.fromEntries(locales.map((x) => [x, `${siteUrl}/${x}${path}`])) },
    })),
  );
}
