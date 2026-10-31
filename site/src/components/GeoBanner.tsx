"use client";
import { useEffect, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import { X } from "lucide-react";
import { usePathname, useRouter } from "@/i18n/navigation";
import { localeNames, type Locale, type Suggestion } from "@/lib/locales";
import { readPrefs, regionName, savePrefs, writeCookie } from "@/lib/prefs-client";

/**
 * Première visite : propose la langue et la devise du pays détecté. Jamais imposé :
 * le visiteur accepte, choisit lui-même ou ferme. Le choix est mémorisé.
 */
export function GeoBanner() {
  const t = useTranslations("geo");
  const locale = useLocale() as Locale;
  const router = useRouter();
  const pathname = usePathname();
  const [s, setS] = useState<(Suggestion & { detected: boolean }) | null>(null);
  const [, startTransition] = useTransition();

  useEffect(() => {
    if (readPrefs().answered) return;
    const ctrl = new AbortController();
    fetch("/api/geo", { signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setS(data))
      .catch(() => {});
    return () => ctrl.abort();
  }, []);

  if (!s) return null;
  const target = s.locale;

  const accept = () => {
    savePrefs({ country: s.country, currency: s.currency });
    setS(null);
    if (target !== locale) startTransition(() => router.replace(pathname, { locale: target }));
  };
  const dismiss = () => {
    writeCookie("solea_prefs", "1");
    if (!readPrefs().country) savePrefs({ country: s.country, currency: s.currency });
    setS(null);
  };
  const choose = () => {
    dismiss();
    window.dispatchEvent(new CustomEvent("solea:open-prefs"));
  };

  const values = { country: regionName(s.country, locale, ""), language: localeNames[target], currency: s.currency };
  const text = s.country !== "INT" ? t("suggest", values) : t("suggestNoCountry", values);

  return (
    <div role="region" aria-live="polite" className="fixed inset-x-3 bottom-3 z-[70] sm:inset-x-auto sm:bottom-6 sm:end-6 sm:max-w-md">
      <div className="glass-dark rounded-3xl p-5 text-white shadow-2xl">
        <div className="flex items-start gap-3">
          <p className="flex-1 text-sm leading-relaxed text-white/85">{text}</p>
          <button type="button" onClick={dismiss} aria-label={t("dismiss")} className="-m-1 rounded-full p-1 text-white/60 hover:text-white">
            <X className="size-4" />
          </button>
        </div>
        <div className="mt-4 flex gap-2">
          <button type="button" onClick={accept} className="btn btn-sun !px-4 !py-2 text-sm">{t("accept")}</button>
          <button type="button" onClick={choose} className="btn btn-ghost-dark !px-4 !py-2 text-sm">{t("change")}</button>
        </div>
      </div>
    </div>
  );
}
