import { use } from "react";
import { useTranslations } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { Mail } from "lucide-react";
import { PageHero } from "@/components/blocks";
import { Reveal } from "@/components/Reveal";
import { ContactForm } from "@/components/Forms";
import { metaFor } from "@/lib/page";
import type { Locale } from "@/lib/locales";

export const generateMetadata = metaFor("contact", "/contact");

export default function Contact({ params, searchParams }: { params: Promise<{ locale: Locale }>; searchParams: Promise<{ type?: string }> }) {
  const { locale } = use(params);
  const { type } = use(searchParams);
  setRequestLocale(locale);
  const t = useTranslations("contactPage");
  return (
    <>
      <PageHero eyebrow={t("eyebrow")} title={t("title")} intro={t("intro")}>
        <a href="mailto:contact@solea-dz.com" className="mt-8 inline-flex items-center gap-3 text-white/80 hover:text-amber">
          <Mail className="size-5 text-amber" aria-hidden /> <span className="text-sm">{t("emailLabel")} :</span> <span dir="ltr" className="font-bold">contact@solea-dz.com</span>
        </a>
      </PageHero>
      <section className="py-20 md:py-24">
        <div className="container-x">
          <Reveal className="card mx-auto max-w-3xl p-7 md:p-10">
            <ContactForm defaultType={type} />
          </Reveal>
        </div>
      </section>
    </>
  );
}
