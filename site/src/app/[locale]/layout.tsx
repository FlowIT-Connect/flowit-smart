import type { ReactNode } from "react";
import type { Metadata, Viewport } from "next";
import { notFound } from "next/navigation";
import { NextIntlClientProvider, hasLocale } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { routing } from "@/i18n/routing";
import { dirOf, type Locale } from "@/lib/locales";
import { pageMetadata, siteUrl } from "@/lib/seo";
import { manrope, plexArabic } from "../fonts";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { GeoBanner } from "@/components/GeoBanner";
import "../globals.css";

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export const viewport: Viewport = { themeColor: "#0e0c0a", width: "device-width", initialScale: 1 };

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) return {};
  return { ...(await pageMetadata(locale, null, "")), icons: { icon: "/favicon.svg" } };
}

export default async function LocaleLayout({ children, params }: { children: ReactNode; params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: "nav" });
  const meta = await getTranslations({ locale, namespace: "meta" });

  const orgLd = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "Solea",
    url: `${siteUrl}/${locale}`,
    logo: `${siteUrl}/favicon.svg`,
    email: "contact@solea-dz.com",
    description: meta("description"),
    parentOrganization: { "@type": "Organization", name: "FlowIT" },
  };

  return (
    <html lang={locale} dir={dirOf(locale as Locale)} className={`${manrope.variable} ${plexArabic.variable}`}>
      <body className="min-h-dvh antialiased">
        <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:start-4 focus:top-4 focus:z-[100] focus:rounded-full focus:bg-ink focus:px-4 focus:py-2 focus:text-white">
          {t("skip")}
        </a>
        <NextIntlClientProvider>
          <Header />
          <main id="main">{children}</main>
          <Footer />
          <GeoBanner />
        </NextIntlClientProvider>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(orgLd).replace(/</g, "\\u003c") }} />
      </body>
    </html>
  );
}
