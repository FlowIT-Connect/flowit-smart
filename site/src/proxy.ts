import createMiddleware from "next-intl/middleware";
import { NextResponse, type NextRequest } from "next/server";
import { routing } from "./i18n/routing";
import { suggest } from "./lib/locales";
import { countryFromHeaders } from "./lib/geo-headers";

const intl = createMiddleware(routing);

/**
 * Première visite sur « / » : on choisit la langue d'après le pays (en-tête posé par le proxy
 * HTTPS ou le CDN) et les langues du navigateur. Ensuite, le cookie NEXT_LOCALE fait foi.
 */
export default function proxy(req: NextRequest) {
  if (req.nextUrl.pathname === "/" && !req.cookies.get("NEXT_LOCALE")) {
    const s = suggest(countryFromHeaders(req.headers), req.headers.get("accept-language"));
    const url = req.nextUrl.clone();
    url.pathname = `/${s.locale}`;
    return NextResponse.redirect(url, 307);
  }
  return intl(req);
}

export const config = {
  matcher: ["/((?!api|_next|_vercel|.*\\..*).*)"],
};
