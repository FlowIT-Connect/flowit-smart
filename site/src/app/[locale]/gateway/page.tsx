import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { Check, Info } from "lucide-react";
import { PageHero } from "@/components/blocks";
import { Reveal } from "@/components/Reveal";
import { GatewayRender } from "@/components/art/GatewayRender";
import { GatewayForm } from "@/components/Forms";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("gateway", "/gateway");

export default function Gateway({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("gatewayPage");
  const c = useTranslations("common");
  const features = t.raw("features") as string[];
  const views = [
    ["front", t("viewFront")],
    ["side", t("viewSide")],
    ["situ", t("viewSitu")],
  ] as const;
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")}>
        <p className="mt-8 inline-flex items-center gap-2 rounded-full border border-amber/40 bg-amber/10 px-4 py-2 text-sm font-bold text-amber">
          <span className="size-2 rounded-full bg-amber animate-glow" /> {t("status")}
        </p>
      </PageHero>

      <section className="py-20 md:py-24">
        <div className="container-x">
          <div className="grid gap-5 md:grid-cols-3">
            {views.map(([v, label], i) => (
              <Reveal key={v} delay={i * 100}>
                <figure className="card overflow-hidden">
                  <div className={v === "situ" ? "" : "bg-gradient-to-b from-sand to-white p-6"}>
                    <GatewayRender view={v} className="block h-auto w-full" title={`Solea Gateway, ${label}`} />
                  </div>
                  <figcaption className="px-6 py-4 text-sm font-bold">{label}</figcaption>
                </figure>
              </Reveal>
            ))}
          </div>
          <p className="mt-4 text-center text-xs text-ink-faint">{c("conceptNote")}</p>

          <Reveal>
            <p className="mx-auto mt-10 flex max-w-3xl gap-3 rounded-2xl border border-amber/40 bg-amber/10 p-5 text-sm leading-relaxed text-ink-soft">
              <Info className="mt-0.5 size-5 shrink-0 text-brand-strong" aria-hidden /> {t("notForSale")}
            </p>
          </Reveal>
        </div>
      </section>

      <section className="bg-sand py-20 md:py-24">
        <div className="container-x grid gap-12 lg:grid-cols-2">
          <Reveal>
            <h2 className="h-section !text-3xl md:!text-4xl">{t("featuresTitle")}</h2>
            <ul className="mt-8 grid gap-3">
              {features.map((f) => (
                <li key={f} className="glass flex items-center gap-3 rounded-2xl px-5 py-4 font-semibold">
                  <span className="grid size-7 shrink-0 place-items-center rounded-full bg-sun"><Check className="size-4 text-ink" aria-hidden /></span>
                  {f}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal delay={120}>
            <div id="notify" className="card scroll-mt-28 p-7 md:p-10">
              <h2 className="text-2xl font-extrabold">{t("formTitle")}</h2>
              <p className="mt-2 mb-7 text-ink-soft">{t("formText")}</p>
              <GatewayForm />
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
}
