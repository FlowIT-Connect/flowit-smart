import type { Metadata } from "next";
import { pageMetadata } from "./seo";
import type { Locale } from "./locales";

/** Fabrique generateMetadata pour une page publique. */
export const metaFor = (key: string, path: string) =>
  async function generateMetadata({ params }: { params: Promise<{ locale: Locale }> }): Promise<Metadata> {
    const { locale } = await params;
    return pageMetadata(locale, key, path);
  };
