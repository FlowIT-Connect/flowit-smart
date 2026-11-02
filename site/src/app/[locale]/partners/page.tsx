import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { Check, Users } from "lucide-react";
import { PageHero } from "@/components/blocks";
import { Reveal } from "@/components/Reveal";
import { PartnerForm } from "@/components/Forms";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("partners", "/partners");

export default function Partners({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("partnersPage");
  const targets = t.raw("targets") as string[];
  const benefits = t.raw("benefits") as string[];
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")} />
      <section className="py-20 md:py-24">
        <div className="container-x grid gap-5 lg:grid-cols-2">
          <Reveal className="card p-8">
            <Users className="size-8 text-brand-strong" strokeWidth={1.6} aria-hidden />
            <h2 className="mt-4 text-2xl font-extrabold">{t("targetsTitle")}</h2>
            <ul className="mt-6 flex flex-wrap gap-2">
              {targets.map((x) => <li key={x} className="rounded-full bg-sand px-4 py-2 text-sm font-semibold">{x}</li>)}
            </ul>
          </Reveal>
          <Reveal delay={100} className="noise relative overflow-hidden rounded-[1.75rem] bg-night p-8 text-white">
            <h2 className="text-2xl font-extrabold">{t("benefitsTitle")}</h2>
            <ul className="mt-6 space-y-3">
              {benefits.map((x) => (
                <li key={x} className="flex items-center gap-3 text-white/80">
                  <span className="grid size-6 shrink-0 place-items-center rounded-full bg-sun"><Check className="size-3.5 text-ink" aria-hidden /></span> {x}
                </li>
              ))}
            </ul>
          </Reveal>
        </div>
        <div className="container-x mt-5">
          <Reveal className="card mx-auto max-w-3xl p-7 md:p-10">
            <h2 className="mb-7 text-2xl font-extrabold">{t("formTitle")}</h2>
            <PartnerForm />
          </Reveal>
        </div>
      </section>
    </>
  );
}
