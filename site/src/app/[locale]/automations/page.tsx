import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { PageHero, ScenarioCard, type Scenario } from "@/components/blocks";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("automations", "/automations");

export default function Automations({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("automationsPage");
  const scenarios = t.raw("scenarios") as Scenario[];
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")} />
      <section className="py-20 md:py-24">
        <div className="container-x grid gap-5 md:grid-cols-2 lg:grid-cols-3">
          {scenarios.map((s, i) => <ScenarioCard key={s.key} s={s} index={i} delay={(i % 3) * 90} />)}
        </div>
      </section>
    </>
  );
}
