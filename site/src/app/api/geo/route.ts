import { NextResponse, type NextRequest } from "next/server";
import { suggest } from "@/lib/locales";
import { countryFromHeaders } from "@/lib/geo-headers";
import { clientIp, countryFromIp } from "@/lib/geoip";

export const dynamic = "force-dynamic";

/** Suggestion de langue / pays / devise pour la première visite. L'adresse IP n'est pas conservée. */
export async function GET(req: NextRequest) {
  const country = countryFromHeaders(req.headers) ?? (await countryFromIp(clientIp(req.headers)));
  const s = suggest(country, req.headers.get("accept-language"));
  return NextResponse.json({ ...s, detected: Boolean(country) }, { headers: { "Cache-Control": "private, no-store" } });
}
