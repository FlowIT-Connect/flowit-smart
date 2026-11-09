import { useTranslations } from "next-intl";
import { Reveal } from "./Reveal";
import { SectionHead } from "./SectionHead";
import { IPhoneFrame } from "./IPhoneFrame";

/** Vraies captures de l'app (public/app), affichées telles quelles dans un iPhone. */
export const appScreens = [
  { key: "home", src: "/app/accueil.webp", h: 1588 },
  { key: "rooms", src: "/app/pieces.webp", h: 1588 },
  { key: "climate", src: "/app/climat.webp", h: 1588 },
  { key: "automations", src: "/app/automatisations.webp", h: 1588 },
  { key: "climateModes", src: "/app/climat-modes.webp", h: 1588 },
  { key: "settings", src: "/app/parametres.webp", h: 1588 },
  { key: "appearance", src: "/app/apparence.webp", h: 1588 },
  { key: "signIn", src: "/app/connexion.webp", h: 1520 },
] as const;

export function AppShowcase() {
  const t = useTranslations("appShowcase");
  return (
    <section id="app" className="relative overflow-hidden bg-sand py-24 md:py-32">
      <div className="pointer-events-none absolute -top-32 end-[-10%] size-[36rem] rounded-full bg-amber/25 blur-3xl" />
      <div className="container-x relative">
        <SectionHead eyebrow={t("eyebrow")} title={t("title")} text={t("text")} center />
      </div>
      <Reveal className="relative mt-10">
        <ul
          className="flex snap-x snap-mandatory gap-6 overflow-x-auto px-[max(1rem,calc((100vw-80rem)/2+1.5rem))] pb-16 pt-4 [scrollbar-width:thin] sm:gap-8"
          aria-label={t("title")}
        >
          {appScreens.map((s, i) => {
            const label = t(`screens.${s.key}`);
            return (
              <li key={s.key} className="w-[68vw] max-w-[270px] shrink-0 snap-center sm:w-[250px]">
                <figure>
                  <IPhoneFrame src={s.src} width={720} height={s.h} alt={t("alt", { screen: label })} priority={i < 2} />
                  <figcaption className="mt-5 text-center text-sm font-bold text-ink">{label}</figcaption>
                </figure>
              </li>
            );
          })}
        </ul>
        <p className="-mt-6 text-center text-xs text-ink-faint">{t("hint")}</p>
      </Reveal>
    </section>
  );
}
