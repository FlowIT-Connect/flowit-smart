import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { PageHero, SolutionCard } from "@/components/blocks";
import { solutionKeys } from "@/lib/catalog";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("solutions", "/solutions");

export default function Solutions({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("solutionsPage");
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")} />
      <section className="py-20 md:py-24">
        <div className="container-x grid gap-5 md:grid-cols-2">
          {solutionKeys.map((k, i) => <SolutionCard key={k} k={k} delay={(i % 2) * 100} detailed />)}
        </div>
      </section>
    </>
  );
}
