import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { ArrowRight, Check, Cpu, Router, Cloud, Smartphone, Plug, Workflow, LayoutDashboard, TrendingUp } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { PageHero } from "@/components/blocks";
import { Reveal } from "@/components/Reveal";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("discover", "/discover");

const howIcons = [Cpu, Router, Cloud, Smartphone];

export default function Discover({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("discover");
  const hero = useTranslations("hero");
  const home = useTranslations("home");
  const why = t.raw("why") as string[];
  const how = t.raw("how") as { title: string; text: string }[];
  const blocks = [
    { icon: Plug, title: t("connectTitle"), text: t("connectText") },
    { icon: Workflow, title: t("automateTitle"), text: t("automateText") },
    { icon: LayoutDashboard, title: t("controlTitle"), text: t("controlText") },
    { icon: TrendingUp, title: t("evolveTitle"), text: t("evolveText") },
  ];
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")} />

      <section className="py-24 md:py-28">
        <div className="container-x grid gap-12 lg:grid-cols-2">
          <Reveal>
            <h2 className="h-section !text-3xl md:!text-4xl">{t("whatTitle")}</h2>
            <p className="mt-5 text-lg leading-relaxed text-ink-soft">{t("whatText")}</p>
          </Reveal>
          <Reveal delay={100} className="card p-8">
            <h2 className="text-2xl font-extrabold">{t("whyTitle")}</h2>
            <ul className="mt-6 space-y-4">
              {why.map((w) => (
                <li key={w} className="flex gap-3 leading-relaxed text-ink-soft">
                  <span className="mt-0.5 grid size-6 shrink-0 place-items-center rounded-full bg-sun"><Check className="size-3.5 text-ink" aria-hidden /></span>
                  {w}
                </li>
              ))}
            </ul>
          </Reveal>
        </div>
      </section>

      <section className="noise relative overflow-hidden bg-night py-24 text-white md:py-28">
        <div className="pointer-events-none absolute -top-40 start-1/3 size-[36rem] rounded-full bg-brand/15 blur-3xl" />
        <div className="container-x relative">
          <Reveal><h2 className="h-section max-w-2xl">{t("howTitle")}</h2></Reveal>
          <ol className="mt-14 grid gap-4 md:grid-cols-4">
            {how.map((h, i) => {
              const Icon = howIcons[i] ?? Cpu;
              return (
                <Reveal as="li" key={h.title} delay={i * 100} className="glass-dark relative rounded-3xl p-6">
                  <span className="text-sm font-bold text-amber">0{i + 1}</span>
                  <Icon className="mt-4 size-8 text-white" strokeWidth={1.5} aria-hidden />
                  <h3 className="mt-4 text-lg font-extrabold">{h.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-white/60">{h.text}</p>
                  {i < how.length - 1 && <ArrowRight className="absolute -end-4 top-1/2 z-10 hidden size-6 -translate-y-1/2 text-amber md:block rtl:rotate-180" aria-hidden />}
                </Reveal>
              );
            })}
          </ol>
        </div>
      </section>

      <section className="py-24 md:py-28">
        <div className="container-x grid gap-5 md:grid-cols-2">
          {blocks.map(({ icon: Icon, title, text }, i) => (
            <Reveal key={title} delay={(i % 2) * 100} className="card card-hover p-8">
              <span className="grid size-12 place-items-center rounded-2xl bg-sand text-brand-strong"><Icon className="size-6" strokeWidth={1.8} aria-hidden /></span>
              <h2 className="mt-5 text-2xl font-extrabold">{title}</h2>
              <p className="mt-3 leading-relaxed text-ink-soft">{text}</p>
            </Reveal>
          ))}
        </div>
        <div className="container-x mt-14 flex flex-wrap justify-center gap-3">
          <Link href="/devices" className="btn btn-primary">{home("categoriesCta")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden /></Link>
          <Link href="/shop" className="btn btn-ghost">{hero("ctaShop")}</Link>
        </div>
      </section>
    </>
  );
}
