import { getTranslations } from "next-intl/server";
import { Mail } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { mainNav } from "@/lib/nav";
import { Wordmark } from "./Logo";

export async function Footer() {
  const t = await getTranslations("footer");
  const nav = await getTranslations("nav");
  const year = new Date().getFullYear();
  return (
    <footer className="relative overflow-hidden bg-night text-white">
      <div className="pointer-events-none absolute -top-40 start-1/2 h-80 w-[60rem] -translate-x-1/2 rounded-full bg-brand/20 blur-3xl rtl:translate-x-1/2" />
      <div className="container-x relative grid gap-12 py-16 md:grid-cols-[1.4fr_1fr_1fr]">
        <div>
          <Wordmark dark size={32} />
          <p className="mt-5 max-w-sm text-white/60">{t("tagline")}</p>
          <p className="mt-3 text-sm text-white/40">{t("by")}</p>
        </div>
        <div>
          <h3 className="text-sm font-bold uppercase tracking-widest text-white/40 rtl:tracking-normal">{t("explore")}</h3>
          <ul className="mt-4 space-y-2.5">
            {mainNav.map((i) => (
              <li key={i.key}>
                <Link href={i.href} className="text-white/75 transition hover:text-amber">{nav(i.key)}</Link>
              </li>
            ))}
            <li><Link href="/shop" className="text-white/75 transition hover:text-amber">{nav("shop")}</Link></li>
          </ul>
        </div>
        <div>
          <h3 className="text-sm font-bold uppercase tracking-widest text-white/40 rtl:tracking-normal">{t("contact")}</h3>
          <ul className="mt-4 space-y-2.5">
            <li><Link href="/contact" className="text-white/75 transition hover:text-amber">{nav("quote")}</Link></li>
            <li>
              <a href="mailto:contact@solea-dz.com" className="inline-flex items-center gap-2 text-white/75 transition hover:text-amber" dir="ltr">
                <Mail className="size-4" aria-hidden /> contact@solea-dz.com
              </a>
            </li>
            <li>
              <a href="mailto:support@solea-dz.com" className="text-white/75 transition hover:text-amber">
                {t("support")} : <span dir="ltr">support@solea-dz.com</span>
              </a>
            </li>
            <li><Link href="/partners" className="text-white/75 transition hover:text-amber">{nav("partners")}</Link></li>
          </ul>
        </div>
      </div>
      <div className="border-t border-white/10">
        <div className="container-x flex flex-col gap-2 py-6 text-sm text-white/40 sm:flex-row sm:items-center sm:justify-between">
          <p>© {year} FlowIT · Solea. {t("rights")}</p>
          <div className="flex gap-5">
            <a href="https://db-ip.com" rel="noopener" className="hover:text-white">{t("geoip")}</a>
            <Link href="/privacy" className="hover:text-white">{t("privacy")}</Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
