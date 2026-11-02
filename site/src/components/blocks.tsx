import { useTranslations } from "next-intl";
import { ArrowRight, Check, BellRing, Footprints, LogOut, ShieldAlert, Thermometer, DoorOpen } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { categoryMeta, solutionIcons, type CategoryKey, type SolutionKey } from "@/lib/catalog";
import { Reveal } from "./Reveal";

export function CategoryTile({ k, delay = 0, compact = false }: { k: CategoryKey; delay?: number; compact?: boolean }) {
  const t = useTranslations("categories");
  const { icon: Icon, hue } = categoryMeta[k];
  return (
    <Reveal delay={delay}>
      <Link href={`/devices#${k}`} className="card card-hover group relative flex h-full flex-col overflow-hidden p-6">
        <div className={`pointer-events-none absolute -end-10 -top-10 size-40 rounded-full bg-gradient-to-br ${hue} opacity-50 blur-2xl transition group-hover:opacity-80`} />
        <span className={`relative grid size-14 place-items-center rounded-2xl bg-gradient-to-br ${hue} shadow-inner`}>
          <Icon className="size-7 text-ink" strokeWidth={1.7} aria-hidden />
        </span>
        <h3 className="relative mt-6 text-lg font-extrabold">{t(`${k}.name`)}</h3>
        {!compact && <p className="relative mt-2 text-sm leading-relaxed text-ink-soft">{t(`${k}.text`)}</p>}
        <ArrowRight className="relative mt-auto size-5 pt-0 text-ink-faint transition group-hover:translate-x-1 group-hover:text-brand rtl:rotate-180 rtl:group-hover:-translate-x-1" aria-hidden />
      </Link>
    </Reveal>
  );
}

const scenarioIcons = { welcome: Footprints, leave: LogOut, security: ShieldAlert, climate: Thermometer, visitor: DoorOpen } as const;
export type Scenario = { key: keyof typeof scenarioIcons; title: string; steps: string[] };

export function ScenarioCard({ s, index, delay = 0 }: { s: Scenario; index: number; delay?: number }) {
  const Icon = scenarioIcons[s.key] ?? BellRing;
  return (
    <Reveal delay={delay} className="h-full">
      <article className="card card-hover group relative h-full overflow-hidden p-7">
        <div className="flex items-center justify-between">
          <span className="grid size-12 place-items-center rounded-2xl bg-sun text-ink shadow-[0_10px_30px_-10px_rgba(242,140,27,.8)]">
            <Icon className="size-6" strokeWidth={1.8} aria-hidden />
          </span>
          <span className="text-5xl font-extrabold text-ink/[.06]" aria-hidden>{String(index + 1).padStart(2, "0")}</span>
        </div>
        <h3 className="mt-6 text-xl font-extrabold">{s.title}</h3>
        <ol className="relative mt-5 space-y-4 border-s-2 border-dashed border-line ps-5">
          {s.steps.map((step, i) => (
            <li key={i} className="relative text-sm leading-relaxed text-ink-soft">
              <span className={`absolute -start-[1.72rem] top-1 size-3 rounded-full ring-4 ring-white ${i === 0 ? "bg-brand" : "bg-amber/70"}`} />
              {step}
            </li>
          ))}
        </ol>
      </article>
    </Reveal>
  );
}

export function SolutionCard({ k, delay = 0, detailed = false }: { k: SolutionKey; delay?: number; detailed?: boolean }) {
  const t = useTranslations("solutions");
  const c = useTranslations("common");
  const Icon = solutionIcons[k];
  const items = t.raw(`${k}.items`) as string[];
  return (
    <Reveal delay={delay} className="h-full">
      <article id={k} className="card card-hover group relative flex h-full scroll-mt-28 flex-col overflow-hidden p-7">
        <div className="pointer-events-none absolute inset-x-0 top-0 h-28 bg-gradient-to-b from-amber/15 to-transparent" />
        <span className="relative grid size-14 place-items-center rounded-2xl bg-night text-amber">
          <Icon className="size-7" strokeWidth={1.6} aria-hidden />
        </span>
        <h3 className="relative mt-6 text-xl font-extrabold">{t(`${k}.name`)}</h3>
        <p className="relative mt-2 text-sm leading-relaxed text-ink-soft">{t(`${k}.text`)}</p>
        <ul className={`relative mt-5 flex flex-wrap gap-2 ${detailed ? "" : "mb-2"}`}>
          {(detailed ? items : items.slice(0, 4)).map((i) => (
            <li key={i} className="inline-flex items-center gap-1.5 rounded-full bg-sand px-3 py-1.5 text-xs font-semibold text-ink-soft">
              <Check className="size-3.5 text-brand" aria-hidden /> {i}
            </li>
          ))}
        </ul>
        <Link href={`/contact?type=${k}`} className="relative mt-auto inline-flex items-center gap-2 pt-6 text-sm font-bold text-ink hover:text-brand-strong">
          {c("requestStudy")} <ArrowRight className="size-4 rtl:rotate-180" aria-hidden />
        </Link>
      </article>
    </Reveal>
  );
}

export function PageHero({ eyebrow, title, intro, children }: { eyebrow: string; title: string; intro?: string; children?: React.ReactNode }) {
  return (
    <section className="noise relative overflow-hidden bg-night pb-20 pt-36 text-white md:pb-28 md:pt-44">
      <div className="pointer-events-none absolute -top-32 end-[-10%] size-[36rem] rounded-full bg-brand/25 blur-3xl" />
      <div className="pointer-events-none absolute bottom-[-12rem] start-[-8rem] size-[28rem] rounded-full bg-flame/15 blur-3xl" />
      <div className="container-x relative">
        <Reveal className="max-w-3xl">
          <p className="eyebrow !text-amber">{eyebrow}</p>
          <h1 className="h-display mt-5 text-4xl sm:text-5xl md:text-6xl">{title}</h1>
          {intro && <p className="mt-6 max-w-2xl text-lg leading-relaxed text-white/65">{intro}</p>}
          {children}
        </Reveal>
      </div>
    </section>
  );
}
