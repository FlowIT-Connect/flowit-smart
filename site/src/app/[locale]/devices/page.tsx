import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { BadgeCheck, Info } from "lucide-react";
import { PageHero } from "@/components/blocks";
import { Reveal } from "@/components/Reveal";
import { categoryKeys, categoryMeta } from "@/lib/catalog";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("devices", "/devices");

export default function Devices({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("devicesPage");
  const cat = useTranslations("categories");
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")}>
        <nav className="mt-10 flex flex-wrap gap-2" aria-label={t("eyebrow")}>
          {categoryKeys.map((k) => {
            const Icon = categoryMeta[k].icon;
            return (
              <a key={k} href={`#${k}`} className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-4 py-2 text-sm font-semibold text-white/85 transition hover:bg-white/10">
                <Icon className="size-4 text-amber" aria-hidden /> {cat(`${k}.name`)}
              </a>
            );
          })}
        </nav>
      </PageHero>

      <section className="py-20 md:py-24">
        <div className="container-x space-y-6">
          {categoryKeys.map((k) => {
            const { icon: Icon, hue, protocols } = categoryMeta[k];
            const items = cat.raw(`${k}.items`) as string[];
            const note = cat.has(`${k}.note`) ? cat(`${k}.note`) : null;
            return (
              <Reveal key={k}>
                <article id={k} className="card relative grid scroll-mt-28 gap-8 overflow-hidden p-7 md:grid-cols-[minmax(0,18rem)_1fr] md:p-10">
                  <div className={`pointer-events-none absolute -start-16 -top-16 size-64 rounded-full bg-gradient-to-br ${hue} opacity-40 blur-3xl`} />
                  <div className="relative">
                    <div className={`grid aspect-[4/3] place-items-center rounded-3xl bg-gradient-to-br ${hue}`}>
                      <Icon className="size-20 text-ink/80" strokeWidth={1.2} aria-hidden />
                    </div>
                    <h2 className="mt-6 text-2xl font-extrabold">{cat(`${k}.name`)}</h2>
                    <p className="mt-2 leading-relaxed text-ink-soft">{cat(`${k}.text`)}</p>
                  </div>
                  <div className="relative">
                    <ul className="grid gap-2.5 sm:grid-cols-2">
                      {items.map((i) => (
                        <li key={i} className="flex items-center gap-3 rounded-2xl bg-sand/70 px-4 py-3 text-sm font-semibold">
                          <span className="size-1.5 shrink-0 rounded-full bg-brand" aria-hidden /> {i}
                        </li>
                      ))}
                    </ul>
                    <div className="mt-6">
                      <p className="text-xs font-bold uppercase tracking-widest text-ink-faint rtl:tracking-normal">{t("protocols")}</p>
                      <div className="mt-3 flex flex-wrap gap-2" dir="ltr">
                        {protocols.map((p) => <span key={p} className="rounded-full border border-line bg-white px-3 py-1 text-xs font-bold">{p}</span>)}
                      </div>
                    </div>
                    {note && (
                      <p className="mt-6 flex gap-3 rounded-2xl border border-amber/40 bg-amber/10 p-4 text-sm leading-relaxed text-ink-soft">
                        <Info className="mt-0.5 size-5 shrink-0 text-brand-strong" aria-hidden /> {note}
                      </p>
                    )}
                  </div>
                </article>
              </Reveal>
            );
          })}
          <Reveal>
            <p className="flex items-center justify-center gap-3 rounded-3xl bg-night p-6 text-center text-white/80">
              <BadgeCheck className="size-6 shrink-0 text-amber" aria-hidden /> {t("honesty")}
            </p>
          </Reveal>
        </div>
      </section>
    </>
  );
}
