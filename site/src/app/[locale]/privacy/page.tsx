import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { PageHero } from "@/components/blocks";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("privacy", "/privacy");

export default function Privacy({ params }: { params: Promise<{ locale: Locale }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations("privacyPage");
  return (
    <>
      <PageHero eyebrow="Solea" title={t("title")} intro={t("intro")} />
      <section className="py-16">
        <div className="container-x">
          <ul className="card mx-auto max-w-3xl space-y-4 p-8 leading-relaxed text-ink-soft">
            {(t.raw("items") as string[]).map((i) => <li key={i} className="flex gap-3"><span className="mt-2.5 size-1.5 shrink-0 rounded-full bg-brand" />{i}</li>)}
          </ul>
        </div>
      </section>
    </>
  );
}
