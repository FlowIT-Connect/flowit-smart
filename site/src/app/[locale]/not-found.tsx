import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { SunMark } from "@/components/Logo";

export default function NotFound() {
  const t = useTranslations("notFound");
  return (
    <section className="grid min-h-[80vh] place-items-center bg-night px-6 pt-24 text-center text-white">
      <div>
        <SunMark size={72} className="mx-auto animate-float" />
        <h1 className="h-display mt-8 text-5xl">{t("title")}</h1>
        <p className="mt-4 text-white/60">{t("text")}</p>
        <Link href="/" className="btn btn-sun mt-8">{t("back")}</Link>
      </div>
    </section>
  );
}
