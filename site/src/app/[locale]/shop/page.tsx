import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { ShoppingBag } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { PageHero } from "@/components/blocks";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("shop", "/shop");

/** Lot 1 : la boutique n'est pas encore ouverte, on le dit clairement. Remplacée au lot 2. */
export default function Shop({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("shopPage");
  return (
    <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("text")}>
      <div className="mt-10 flex flex-wrap gap-3">
        <Link href="/contact" className="btn btn-sun"><ShoppingBag className="size-4" aria-hidden /> {t("quote")}</Link>
        <Link href="/devices" className="btn btn-ghost-dark">{t("devices")}</Link>
      </div>
    </PageHero>
  );
}
