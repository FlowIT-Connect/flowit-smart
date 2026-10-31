"use client";
import { useEffect, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import { Globe, X } from "lucide-react";
import { usePathname, useRouter } from "@/i18n/navigation";
import { countries, currencies, findCountry, localeNames, locales, isCurrency, type Currency, type Locale } from "@/lib/locales";
import { readPrefs, regionName, savePrefs } from "@/lib/prefs-client";

/** Bouton + fenêtre « Langue, pays et devise ». Toujours accessible depuis l'en-tête. */
export function Preferences({ dark = false }: { dark?: boolean }) {
  const t = useTranslations("prefs");
  const locale = useLocale() as Locale;
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [lang, setLang] = useState<Locale>(locale);
  const [country, setCountry] = useState("INT");
  const [currency, setCurrency] = useState<Currency>("EUR");
  const [shown, setShown] = useState<{ country: string; currency: Currency } | null>(null);
  const [, startTransition] = useTransition();

  useEffect(() => {
    const sync = () => {
      const p = readPrefs();
      const c = p.country ?? "INT";
      const cur = p.currency ?? findCountry(c)?.currency ?? "EUR";
      setShown({ country: c, currency: cur });
      setCountry(c);
      setCurrency(cur);
    };
    sync();
    const onOpen = () => setOpen(true);
    window.addEventListener("solea:prefs", sync);
    window.addEventListener("solea:open-prefs", onOpen);
    return () => {
      window.removeEventListener("solea:prefs", sync);
      window.removeEventListener("solea:open-prefs", onOpen);
    };
  }, []);

  useEffect(() => setLang(locale), [locale, open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  const save = () => {
    savePrefs({ country, currency });
    setOpen(false);
    if (lang !== locale) startTransition(() => router.replace(pathname, { locale: lang }));
  };

  const sortedCountries = [...countries].sort((a, b) => regionName(a.code, locale, "").localeCompare(regionName(b.code, locale, ""), locale));

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t("button")}
        className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold transition ${dark ? "text-white/85 hover:bg-white/10" : "text-ink hover:bg-ink/5"}`}
      >
        <Globe className="size-4" aria-hidden />
        <span className="uppercase">{locale}</span>
        {shown && <span className={dark ? "text-white/50" : "text-ink-faint"}>· {shown.currency}</span>}
      </button>

      {open && (
        <div className="fixed inset-0 z-[80] flex items-end justify-center bg-night/50 p-0 backdrop-blur-sm sm:items-center sm:p-6" onClick={() => setOpen(false)}>
          <div role="dialog" aria-modal="true" aria-labelledby="prefs-title" className="glass w-full max-w-md rounded-t-[2rem] p-6 shadow-2xl sm:rounded-[2rem] sm:p-8 !bg-white/90" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h2 id="prefs-title" className="text-xl font-extrabold">{t("title")}</h2>
              <button type="button" onClick={() => setOpen(false)} className="rounded-full p-2 hover:bg-ink/5" aria-label="×">
                <X className="size-5" />
              </button>
            </div>
            <div className="mt-6 space-y-4">
              <div>
                <label className="label" htmlFor="pref-lang">{t("language")}</label>
                <select id="pref-lang" className="field" value={lang} onChange={(e) => setLang(e.target.value as Locale)}>
                  {locales.map((l) => (
                    <option key={l} value={l} lang={l}>{localeNames[l]}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="label" htmlFor="pref-country">{t("country")}</label>
                <select
                  id="pref-country"
                  className="field"
                  value={country}
                  onChange={(e) => {
                    setCountry(e.target.value);
                    const c = findCountry(e.target.value);
                    if (c) setCurrency(c.currency);
                  }}
                >
                  {sortedCountries.map((c) => (
                    <option key={c.code} value={c.code}>{regionName(c.code, locale, "")}</option>
                  ))}
                  <option value="INT">{t("otherCountry")}</option>
                </select>
              </div>
              <div>
                <label className="label" htmlFor="pref-cur">{t("currency")}</label>
                <select id="pref-cur" className="field" value={currency} onChange={(e) => isCurrency(e.target.value) && setCurrency(e.target.value)}>
                  {currencies.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
              <p className="text-xs leading-relaxed text-ink-faint">{t("note")}</p>
              <button type="button" onClick={save} className="btn btn-primary w-full">{t("save")}</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
