import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { locales, type Locale } from "./locales";

export const siteUrl = (process.env.SITE_URL || "https://solea-dz.com").replace(/\/$/, "");

/** Titre, description, URL canonique et balises hreflang d'une page. */
export async function pageMetadata(locale: Locale, key: string | null, path: string): Promise<Metadata> {
  const t = await getTranslations({ locale, namespace: "meta" });
  const title = key ? `${t(`${key}.title`)} | Solea` : t("title");
  const description = key ? t(`${key}.description`) : t("description");
  const languages = Object.fromEntries(locales.map((l) => [l, `${siteUrl}/${l}${path}`]));
  return {
    title,
    description,
    metadataBase: new URL(siteUrl),
    alternates: { canonical: `${siteUrl}/${locale}${path}`, languages: { ...languages, "x-default": `${siteUrl}/en${path}` } },
    openGraph: { title, description, url: `${siteUrl}/${locale}${path}`, siteName: "Solea", locale, type: "website" },
    twitter: { card: "summary_large_image", title, description },
  };
}
