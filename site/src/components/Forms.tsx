"use client";
import { useActionState, useEffect, useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";
import { CheckCircle2, AlertCircle, Loader2, Send } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { submitContact, submitGateway, submitPartner, type FormState } from "@/app/actions";
import { countries, localeNames, locales, type Locale } from "@/lib/locales";
import { partnerActivities, projectTypes } from "@/lib/catalog";
import { readPrefs, regionName } from "@/lib/prefs-client";

function useDefaultCountry() {
  const [c, setC] = useState("");
  useEffect(() => setC(readPrefs().country ?? ""), []);
  return c;
}

function CountrySelect({ id = "country" }: { id?: string }) {
  const t = useTranslations("form");
  const p = useTranslations("prefs");
  const locale = useLocale();
  const def = useDefaultCountry();
  const [value, setValue] = useState("");
  useEffect(() => setValue((v) => v || def), [def]);
  const sorted = [...countries].sort((a, b) => regionName(a.code, locale, "").localeCompare(regionName(b.code, locale, ""), locale));
  return (
    <Field label={t("country")} htmlFor={id} required>
      <select id={id} name="country" className="field" required value={value} onChange={(e) => setValue(e.target.value)}>
        <option value="" disabled>{t("choose")}</option>
        {sorted.map((c) => <option key={c.code} value={c.code}>{regionName(c.code, locale, "")}</option>)}
        <option value="INT">{p("otherCountry")}</option>
      </select>
    </Field>
  );
}

function Field({ label, htmlFor, required, hint, children, className = "" }: { label: string; htmlFor: string; required?: boolean; hint?: string; children: ReactNode; className?: string }) {
  return (
    <div className={className}>
      <label className="label" htmlFor={htmlFor}>
        {label} {required && <span className="text-brand-strong" aria-hidden>*</span>}
      </label>
      {children}
      {hint && <p className="mt-1.5 text-xs text-ink-faint">{hint}</p>}
    </div>
  );
}

function Hidden() {
  const locale = useLocale();
  return (
    <>
      <input type="hidden" name="locale" value={locale} />
      {/* Champ piège pour les robots : invisible pour les humains. */}
      <div aria-hidden className="absolute -start-[9999px] h-0 w-0 overflow-hidden">
        <label>Website<input type="text" name="website" tabIndex={-1} autoComplete="off" /></label>
      </div>
    </>
  );
}

function Status({ state, success }: { state: FormState; success: string }) {
  const t = useTranslations("form.errors");
  if (!state) return null;
  if (state.ok)
    return (
      <p role="status" className="flex items-start gap-3 rounded-2xl bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">
        <CheckCircle2 className="mt-0.5 size-5 shrink-0" aria-hidden /> {success}
      </p>
    );
  return (
    <p role="alert" className="flex items-start gap-3 rounded-2xl bg-red-50 p-4 text-sm font-semibold text-red-800">
      <AlertCircle className="mt-0.5 size-5 shrink-0" aria-hidden /> {t(state.error ?? "server")}
    </p>
  );
}

function Submit({ pending, label }: { pending: boolean; label: string }) {
  const t = useTranslations("form");
  return (
    <button type="submit" disabled={pending} className="btn btn-primary w-full disabled:opacity-60 sm:w-auto">
      {pending ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <Send className="size-4 rtl:-scale-x-100" aria-hidden />}
      {pending ? t("sending") : label}
    </button>
  );
}

function Consent({ name, label, required }: { name: string; label: string; required?: boolean }) {
  return (
    <label className="flex cursor-pointer items-start gap-3 text-sm leading-relaxed text-ink-soft">
      <input type="checkbox" name={name} required={required} className="mt-0.5 size-5 shrink-0 accent-[#f28c1b]" />
      <span>{label}{required && <span className="text-brand-strong" aria-hidden> *</span>}</span>
    </label>
  );
}

function PrivacyNote() {
  const t = useTranslations("form");
  return (
    <p className="text-xs text-ink-faint">
      {t("privacy")} <Link href="/privacy" className="underline hover:text-ink">{t("privacyLink")}</Link>
    </p>
  );
}

export function GatewayForm() {
  const t = useTranslations("form");
  const locale = useLocale() as Locale;
  const [state, action, pending] = useActionState(submitGateway, null);
  if (state?.ok) return <Status state={state} success={t("successGateway")} />;
  return (
    <form action={action} className="relative space-y-5" noValidate={false}>
      <Hidden />
      <Field label={t("email")} htmlFor="gw-email" required>
        <input id="gw-email" name="email" type="email" required autoComplete="email" className="field" dir="ltr" />
      </Field>
      <div className="grid gap-5 sm:grid-cols-2">
        <CountrySelect id="gw-country" />
        <Field label={t("language")} htmlFor="gw-lang" required>
          <select id="gw-lang" name="preferred_locale" className="field" defaultValue={locale} required>
            {locales.map((l) => <option key={l} value={l} lang={l}>{localeNames[l]}</option>)}
          </select>
        </Field>
      </div>
      <Consent name="consent_launch" label={t("consentLaunch")} required />
      <Consent name="consent_marketing" label={t("consentMarketing")} />
      <Status state={state} success="" />
      <Submit pending={pending} label={t("submitGateway")} />
      <PrivacyNote />
    </form>
  );
}

export function ContactForm({ defaultType }: { defaultType?: string }) {
  const t = useTranslations("form");
  const [state, action, pending] = useActionState(submitContact, null);
  if (state?.ok) return <Status state={state} success={t("success")} />;
  const type = (projectTypes as readonly string[]).includes(defaultType ?? "") ? defaultType : "";
  return (
    <form action={action} className="relative space-y-5">
      <Hidden />
      <div className="grid gap-5 sm:grid-cols-2">
        <Field label={t("firstName")} htmlFor="c-first" required><input id="c-first" name="first_name" required autoComplete="given-name" className="field" maxLength={80} /></Field>
        <Field label={t("lastName")} htmlFor="c-last" required><input id="c-last" name="last_name" required autoComplete="family-name" className="field" maxLength={80} /></Field>
        <Field label={t("email")} htmlFor="c-email" required><input id="c-email" name="email" type="email" required autoComplete="email" className="field" dir="ltr" /></Field>
        <Field label={t("phone")} htmlFor="c-phone" hint={t("phoneHint")}><input id="c-phone" name="phone" type="tel" autoComplete="tel" className="field" dir="ltr" placeholder="+213 …" maxLength={24} /></Field>
        <CountrySelect id="c-country" />
        <Field label={t("projectType")} htmlFor="c-type" required>
          <select id="c-type" name="project_type" className="field" required defaultValue={type}>
            <option value="" disabled>{t("choose")}</option>
            {projectTypes.map((p) => <option key={p} value={p}>{t(`types.${p}`)}</option>)}
          </select>
        </Field>
      </div>
      <Field label={t("message")} htmlFor="c-msg" required>
        <textarea id="c-msg" name="message" required minLength={5} maxLength={4000} rows={6} className="field resize-y" />
      </Field>
      <Consent name="consent_marketing" label={t("consentMarketing")} />
      <Status state={state} success="" />
      <Submit pending={pending} label={t("submit")} />
      <PrivacyNote />
    </form>
  );
}

export function PartnerForm() {
  const t = useTranslations("form");
  const [state, action, pending] = useActionState(submitPartner, null);
  if (state?.ok) return <Status state={state} success={t("success")} />;
  return (
    <form action={action} className="relative space-y-5">
      <Hidden />
      <div className="grid gap-5 sm:grid-cols-2">
        <Field label={t("name")} htmlFor="p-name" required><input id="p-name" name="name" required autoComplete="name" className="field" maxLength={120} /></Field>
        <Field label={t("company")} htmlFor="p-company" required><input id="p-company" name="company" required autoComplete="organization" className="field" maxLength={160} /></Field>
        <Field label={t("activity")} htmlFor="p-activity" required>
          <select id="p-activity" name="activity" className="field" required defaultValue="">
            <option value="" disabled>{t("choose")}</option>
            {partnerActivities.map((a) => <option key={a} value={a}>{t(`activities.${a}`)}</option>)}
          </select>
        </Field>
        <CountrySelect id="p-country" />
        <Field label={t("email")} htmlFor="p-email" required><input id="p-email" name="email" type="email" required autoComplete="email" className="field" dir="ltr" /></Field>
        <Field label={t("phone")} htmlFor="p-phone" required hint={t("phoneHint")}><input id="p-phone" name="phone" type="tel" required autoComplete="tel" className="field" dir="ltr" placeholder="+213 …" maxLength={24} /></Field>
      </div>
      <Field label={t("message")} htmlFor="p-msg"><textarea id="p-msg" name="message" maxLength={4000} rows={5} className="field resize-y" /></Field>
      <Consent name="consent_marketing" label={t("consentMarketing")} />
      <Status state={state} success="" />
      <Submit pending={pending} label={t("submit")} />
      <PrivacyNote />
    </form>
  );
}
