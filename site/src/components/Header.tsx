"use client";
import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Menu, X, ShoppingBag } from "lucide-react";
import { Link, usePathname } from "@/i18n/navigation";
import { mainNav } from "@/lib/nav";
import { Wordmark } from "./Logo";
import { Preferences } from "./Preferences";

/** En-tête en verre dépoli. Sur fond sombre (haut de l'accueil) il passe en clair. */
export function Header() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const overDark = pathname === "/" && !scrolled && !open;

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  useEffect(() => setOpen(false), [pathname]);
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
  }, [open]);

  return (
    <header className="fixed inset-x-0 top-0 z-50 px-3 pt-3">
      <div
        className={`container-x flex h-16 items-center justify-between gap-4 rounded-full transition-all duration-300 ${
          overDark ? "bg-transparent" : "glass shadow-[0_10px_40px_-20px_rgba(60,40,10,.35)]"
        }`}
      >
        <Link href="/" className="shrink-0" aria-label="Solea">
          <Wordmark dark={overDark} size={28} />
        </Link>

        <nav className="hidden items-center gap-1 lg:flex" aria-label="Main">
          {mainNav.map((item) => {
            const active = pathname.startsWith(item.href);
            return (
              <Link
                key={item.key}
                href={item.href}
                className={`rounded-full px-3.5 py-2 text-sm font-semibold transition ${
                  overDark ? "text-white/80 hover:bg-white/10 hover:text-white" : active ? "bg-ink/[.06] text-ink" : "text-ink-soft hover:bg-ink/5 hover:text-ink"
                }`}
              >
                {t(item.key)}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-1">
          <Preferences dark={overDark} />
          <Link href="/shop" className={`hidden items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold sm:inline-flex ${overDark ? "text-white/85 hover:bg-white/10" : "text-ink hover:bg-ink/5"}`}>
            <ShoppingBag className="size-4" aria-hidden />
            {t("shop")}
          </Link>
          <Link href="/contact" className={`btn hidden !py-2.5 text-sm md:inline-flex ${overDark ? "btn-sun" : "btn-primary"}`}>
            {t("quote")}
          </Link>
          <button
            type="button"
            className={`rounded-full p-2.5 lg:hidden ${overDark ? "text-white hover:bg-white/10" : "hover:bg-ink/5"}`}
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-controls="mobile-menu"
            aria-label={open ? t("close") : t("menu")}
          >
            {open ? <X className="size-6" /> : <Menu className="size-6" />}
          </button>
        </div>
      </div>

      {open && (
        <div id="mobile-menu" className="glass container-x mt-2 max-h-[calc(100dvh-6rem)] overflow-auto rounded-[2rem] p-4 shadow-2xl lg:hidden !bg-white/95">
          <nav className="flex flex-col" aria-label="Mobile">
            {[...mainNav, { key: "shop", href: "/shop" } as const, { key: "contact", href: "/contact" } as const].map((item) => (
              <Link key={item.key} href={item.href} className="rounded-2xl px-4 py-3.5 text-lg font-bold hover:bg-ink/5">
                {t(item.key)}
              </Link>
            ))}
          </nav>
          <Link href="/contact" className="btn btn-sun mt-3 w-full">{t("quote")}</Link>
        </div>
      )}
    </header>
  );
}
