import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { use } from "react";
import { ArrowRight, Bell, ShoppingBag, Lightbulb, Cctv, Thermometer, Handshake } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { benefitIcons, benefitKeys, categoryKeys, featureIcons, featureKeys, solutionKeys, techKeys } from "@/lib/catalog";
import { Reveal } from "@/components/Reveal";
import { SectionHead } from "@/components/SectionHead";
import { CategoryTile, ScenarioCard, SolutionCard, type Scenario } from "@/components/blocks";
import { VillaScene } from "@/components/art/VillaScene";
import { GatewayRender } from "@/components/art/GatewayRender";
import type { Locale } from "@/lib/locales";

export default function Home({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("home");
  const hero = useTranslations("hero");
  const f = useTranslations("features");
  const tech = useTranslations("tech");
  const cat = useTranslations("categories");
  const b = useTranslations("benefits");
  const gw = useTranslations("gatewayPage");
  const common = useTranslations("common");
  const nav = useTranslations("nav");
  const scenarios = (useTranslations("automationsPage").raw("scenarios") as Scenario[]).slice(0, 3);

  return (
    <>
      {/* Bannière principale */}
      <section className="noise relative isolate overflow-hidden bg-night text-white">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute -top-40 start-[-10%] size-[40rem] rounded-full bg-brand/20 blur-3xl" />
          <div className="absolute bottom-0 end-[-10%] size-[34rem] rounded-full bg-flame/20 blur-3xl" />
        </div>
        <div className="container-x grid min-h-[100svh] items-center gap-10 pb-16 pt-32 lg:grid-cols-[1.05fr_1fr] lg:pt-28">
          <Reveal>
            <p className="eyebrow !text-amber">{hero("eyebrow")}</p>
            <h1 className="h-display mt-6 text-[2.6rem] sm:text-6xl xl:text-[4.25rem]">
              {hero("title")
                .split(/(?<=[.。؟?!])\s+/)
                .map((part, i, arr) => (
                  <span key={i} className={i === arr.length - 1 ? "text-gradient block pb-[0.14em]" : "block"}>{part}</span>
                ))}
            </h1>
            <p className="mt-7 max-w-xl text-lg leading-relaxed text-white/70">{hero("text")}</p>
            <div className="mt-9 flex flex-wrap gap-3">
              <Link href="/discover" className="btn btn-sun">
                {hero("ctaDiscover")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden />
              </Link>
              <Link href="/shop" className="btn btn-ghost-dark">
                <ShoppingBag className="size-4" aria-hidden /> {hero("ctaShop")}
              </Link>
            </div>
            <dl className="mt-12 grid max-w-lg grid-cols-3 gap-4">
              {[
                ["8", hero("statProtocols")],
                ["9", hero("statFamilies")],
                ["1", hero("statApp")],
              ].map(([n, label]) => (
                <div key={label} className="glass-dark rounded-2xl px-4 py-3">
                  <dt className="sr-only">{label}</dt>
                  <dd className="text-3xl font-extrabold text-gradient">{n}</dd>
                  <dd className="mt-1 text-xs leading-snug text-white/55">{label}</dd>
                </div>
              ))}
            </dl>
          </Reveal>

          <Reveal delay={150} className="relative">
            <div className="relative overflow-hidden rounded-[2.5rem] border border-white/10 shadow-[0_40px_120px_-40px_rgba(242,140,27,.55)]">
              <VillaScene className="block h-auto w-full" title={hero("sceneLabel")} />
            </div>
            <div className="glass-dark absolute -start-3 top-8 flex animate-float items-center gap-3 rounded-2xl px-4 py-3 sm:-start-8">
              <span className="grid size-10 place-items-center rounded-xl bg-sun text-ink"><Lightbulb className="size-5" aria-hidden /></span>
              <span className="text-sm font-bold">{cat("lighting.name")}</span>
            </div>
            <div className="glass-dark absolute -end-2 top-1/2 flex animate-float items-center gap-3 rounded-2xl px-4 py-3 [animation-delay:1.5s] sm:-end-6">
              <span className="grid size-10 place-items-center rounded-xl bg-white/10 text-amber"><Thermometer className="size-5" aria-hidden /></span>
              <span className="text-sm font-bold" dir="ltr">22,5 °C</span>
            </div>
            <div className="glass-dark absolute -bottom-5 start-8 flex animate-float items-center gap-3 rounded-2xl px-4 py-3 [animation-delay:3s]">
              <span className="relative grid size-10 place-items-center rounded-xl bg-white/10 text-amber">
                <Cctv className="size-5" aria-hidden />
                <span className="absolute end-1.5 top-1.5 size-2 rounded-full bg-red-500 animate-glow" />
              </span>
              <span className="text-sm font-bold">{cat("security.name")}</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* Fonctionnalités */}
      <section className="py-24 md:py-32">
        <div className="container-x">
          <SectionHead eyebrow={t("featuresEyebrow")} title={t("featuresTitle")} text={t("featuresText")} />
          <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {featureKeys.map((k, i) => {
              const Icon = featureIcons[k];
              return (
                <Reveal key={k} delay={i * 70}>
                  <div className="card card-hover h-full p-7">
                    <span className="grid size-12 place-items-center rounded-2xl bg-sand text-brand-strong"><Icon className="size-6" strokeWidth={1.8} aria-hidden /></span>
                    <h3 className="mt-5 text-lg font-extrabold">{f(`${k}.title`)}</h3>
                    <p className="mt-2 leading-relaxed text-ink-soft">{f(`${k}.text`)}</p>
                  </div>
                </Reveal>
              );
            })}
          </div>
        </div>
      </section>

      {/* Technologies */}
      <section className="relative overflow-hidden bg-sand py-24 md:py-32">
        <div className="container-x grid gap-14 lg:grid-cols-[1fr_1.3fr] lg:items-center">
          <SectionHead eyebrow={t("techEyebrow")} title={t("techTitle")} text={t("techText")} />
          <div className="grid grid-cols-2 gap-3 sm:gap-4">
            {techKeys.map((k, i) => (
              <Reveal key={k} delay={i * 50}>
                <div className="glass h-full rounded-3xl p-5 shadow-[0_20px_50px_-35px_rgba(70,45,15,.5)]">
                  <p className="text-lg font-extrabold" dir="ltr">{tech(`${k}.name`)}</p>
                  <p className="mt-1.5 text-sm leading-relaxed text-ink-soft">{tech(`${k}.text`)}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* Catégories */}
      <section className="py-24 md:py-32">
        <div className="container-x">
          <div className="flex flex-col justify-between gap-6 md:flex-row md:items-end">
            <SectionHead eyebrow={t("categoriesEyebrow")} title={t("categoriesTitle")} />
            <Link href="/devices" className="btn btn-ghost shrink-0">{t("categoriesCta")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden /></Link>
          </div>
          <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {categoryKeys.map((k, i) => <CategoryTile key={k} k={k} delay={(i % 3) * 80} />)}
          </div>
        </div>
      </section>

      {/* Solea Gateway */}
      <section className="noise relative overflow-hidden bg-night py-24 text-white md:py-32">
        <div className="pointer-events-none absolute start-1/2 top-1/2 size-[44rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-brand/15 blur-3xl" />
        <div className="container-x relative grid items-center gap-14 lg:grid-cols-2">
          <div>
            <SectionHead eyebrow={t("gatewayEyebrow")} title={t("gatewayTitle")} text={t("gatewayText")} dark />
            <Reveal delay={100}>
              <p className="mt-6 inline-flex items-center gap-2 rounded-full border border-amber/40 bg-amber/10 px-4 py-2 text-sm font-bold text-amber">
                <span className="size-2 rounded-full bg-amber animate-glow" /> {gw("status")}
              </p>
              <div className="mt-8">
                <Link href="/gateway#notify" className="btn btn-sun"><Bell className="size-4" aria-hidden /> {t("gatewayCta")}</Link>
              </div>
            </Reveal>
          </div>
          <Reveal delay={150}>
            <figure className="glass-dark rounded-[2.5rem] p-6 sm:p-10">
              <GatewayRender view="front" className="mx-auto w-full max-w-md animate-float" title="Solea Gateway" />
              <figcaption className="mt-4 text-center text-xs text-white/45">{common("conceptNote")}</figcaption>
            </figure>
          </Reveal>
        </div>
      </section>

      {/* Automatisations */}
      <section className="py-24 md:py-32">
        <div className="container-x">
          <div className="flex flex-col justify-between gap-6 md:flex-row md:items-end">
            <SectionHead eyebrow={t("automationsEyebrow")} title={t("automationsTitle")} />
            <Link href="/automations" className="btn btn-ghost shrink-0">{t("automationsCta")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden /></Link>
          </div>
          <div className="mt-14 grid gap-5 md:grid-cols-3">
            {scenarios.map((s, i) => <ScenarioCard key={s.key} s={s} index={i} delay={i * 90} />)}
          </div>
        </div>
      </section>

      {/* Solutions */}
      <section className="bg-sand py-24 md:py-32">
        <div className="container-x">
          <SectionHead eyebrow={t("solutionsEyebrow")} title={t("solutionsTitle")} />
          <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {solutionKeys.map((k, i) => <SolutionCard key={k} k={k} delay={i * 80} />)}
          </div>
        </div>
      </section>

      {/* Boutique (honnête : pas encore de produits en vente) */}
      <section className="py-24 md:py-32">
        <div className="container-x">
          <Reveal>
            <div className="card relative grid gap-8 overflow-hidden p-8 md:grid-cols-[1.4fr_1fr] md:items-center md:p-14">
              <div className="pointer-events-none absolute -end-24 -top-24 size-72 rounded-full bg-amber/25 blur-3xl" />
              <div className="relative">
                <p className="eyebrow">{t("shopEyebrow")}</p>
                <h2 className="h-section mt-4 !text-3xl md:!text-4xl">{t("shopTitle")}</h2>
                <p className="mt-4 leading-relaxed text-ink-soft">{t("shopText")}</p>
              </div>
              <div className="relative flex flex-wrap gap-3 md:justify-end">
                <Link href="/shop" className="btn btn-primary"><ShoppingBag className="size-4" aria-hidden /> {t("shopCta")}</Link>
                <Link href="/contact" className="btn btn-ghost">{nav("quote")}</Link>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* Avantages */}
      <section className="pb-24 md:pb-32">
        <div className="container-x">
          <SectionHead eyebrow={t("benefitsEyebrow")} title={t("benefitsTitle")} center />
          <div className="mt-14 grid gap-x-8 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
            {benefitKeys.map((k, i) => {
              const Icon = benefitIcons[k];
              return (
                <Reveal key={k} delay={(i % 3) * 80} className="flex gap-4">
                  <span className="grid size-12 shrink-0 place-items-center rounded-2xl bg-sun text-ink"><Icon className="size-6" strokeWidth={1.8} aria-hidden /></span>
                  <div>
                    <h3 className="text-lg font-extrabold">{b(`${k}.title`)}</h3>
                    <p className="mt-1 leading-relaxed text-ink-soft">{b(`${k}.text`)}</p>
                  </div>
                </Reveal>
              );
            })}
          </div>
        </div>
      </section>

      {/* Partenaires */}
      <section className="pb-24 md:pb-32">
        <div className="container-x">
          <Reveal>
            <div className="noise relative overflow-hidden rounded-[2.5rem] bg-sun p-10 text-ink md:p-16">
              <div className="pointer-events-none absolute -bottom-24 -end-16 size-80 rounded-full bg-white/30 blur-3xl" />
              <div className="relative flex flex-col gap-8 md:flex-row md:items-center md:justify-between">
                <div className="max-w-2xl">
                  <Handshake className="size-10" strokeWidth={1.6} aria-hidden />
                  <h2 className="h-section mt-4 !text-3xl md:!text-5xl">{t("partnerTitle")}</h2>
                  <p className="mt-4 text-lg text-ink/75">{t("partnerText")}</p>
                </div>
                <Link href="/partners" className="btn btn-primary shrink-0">{t("partnerCta")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden /></Link>
              </div>
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
}
