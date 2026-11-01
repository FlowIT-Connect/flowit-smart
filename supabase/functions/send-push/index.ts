// Solea — envoi des notifications push (Firebase Cloud Messaging, API HTTP v1).
//
// Appelée par la base (déclencheur notifications_push, extension pg_net) avec
// {"id": <notification>}. Elle relit la notification avec la clé service_role,
// la marque envoyée (pushed_at) pour ne jamais l'envoyer deux fois, puis
// l'envoie à chaque téléphone de son destinataire (table push_tokens). Les
// jetons refusés par Firebase sont supprimés.
//
// Secret à créer dans Supabase > Edge Functions > Secrets :
//   FCM_SERVICE_ACCOUNT = contenu complet du fichier JSON « compte de service »
//                         (Firebase > Paramètres du projet > Comptes de service).
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase.
// Déployée sans vérification JWT (--no-verify-jwt) : un appel ne peut rien
// faire d'autre qu'envoyer, une seule fois, une notification récente déjà créée.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MAX_AGE_MS = 10 * 60_000;

const TITLES: Record<string, Record<string, string>> = {
  en: {
    motion: "Motion detected", door_open: "Door opened", door_closed: "Door closed",
    window_open: "Window opened", water_leak: "Water leak", smoke: "Smoke detected",
    camera_offline: "Camera offline", device_offline: "Device disconnected",
    temperature_abnormal: "Abnormal temperature", automation_run: "Automation ran",
    high_wind: "High winds detected", shutters_auto_closed: "Shutters closed automatically",
  },
  ar: {
    motion: "تم رصد حركة", door_open: "باب مفتوح", door_closed: "باب مغلق",
    window_open: "نافذة مفتوحة", water_leak: "تسرب مياه", smoke: "تم رصد دخان",
    camera_offline: "كاميرا غير متصلة", device_offline: "جهاز غير متصل",
    temperature_abnormal: "درجة حرارة غير طبيعية", automation_run: "تم تنفيذ أتمتة",
    high_wind: "رياح قوية", shutters_auto_closed: "إغلاق المصاريع تلقائيًا",
  },
};

type Notification = {
  id: number; user_id: string; home_id: string; type: string; priority: string;
  title: string; body: string; created_at: string;
};
type Token = { token: string; platform: string; locale: string | null };

function rest(path: string, init: RequestInit = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

// ---------------------------------------------------------------- Jeton Google OAuth
const b64url = (data: ArrayBuffer | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

let cached: { token: string; exp: number; project: string } | null = null;

async function googleAccess(): Promise<{ token: string; project: string }> {
  if (cached && cached.exp > Date.now() + 60_000) return cached;
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "null");
  if (!sa?.private_key || !sa?.client_email || !sa?.project_id) throw new Error("FCM_SERVICE_ACCOUNT manquant ou invalide");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) throw new Error(`Jeton Google refusé (HTTP ${res.status})`);
  const j = await res.json();
  cached = { token: j.access_token, exp: Date.now() + (j.expires_in ?? 3600) * 1000, project: sa.project_id };
  return cached;
}

// ---------------------------------------------------------------- Envoi
async function sendOne(n: Notification, t: Token, access: { token: string; project: string }) {
  const lang = t.locale ?? "fr";
  const title = TITLES[lang]?.[n.type] ?? n.title;
  const urgent = n.priority === "high" || n.priority === "critical";
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${access.project}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: t.token,
        notification: { title, body: n.body || undefined },
        data: { notification_id: String(n.id), type: n.type, home_id: n.home_id, priority: n.priority },
        android: {
          priority: urgent ? "HIGH" : "NORMAL",
          notification: { tag: `${n.type}:${n.home_id}`, ...(n.priority === "critical" ? { default_sound: true, notification_priority: "PRIORITY_MAX" } : {}) },
        },
        apns: { headers: { "apns-priority": urgent ? "10" : "5" }, payload: { aps: { sound: n.priority === "critical" ? "default" : undefined } } },
      },
    }),
  });
  if (res.ok) return "sent";
  const err = await res.json().catch(() => ({}));
  const code = err?.error?.details?.find?.((d: { errorCode?: string }) => d.errorCode)?.errorCode ?? err?.error?.status;
  if (res.status === 404 || code === "UNREGISTERED" || code === "INVALID_ARGUMENT") {
    await rest(`push_tokens?token=eq.${encodeURIComponent(t.token)}`, { method: "DELETE" });
    return "dropped";
  }
  console.warn("push.failed", res.status, code);
  return "failed";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST attendu", { status: 405 });
  const { id } = await req.json().catch(() => ({}));
  if (!Number.isInteger(id)) return new Response("id attendu", { status: 400 });

  // Marque la notification envoyée ; rien à faire si déjà fait, inconnue ou trop ancienne.
  const since = new Date(Date.now() - MAX_AGE_MS).toISOString();
  const claim = await rest(
    `notifications?id=eq.${id}&pushed_at=is.null&created_at=gte.${since}&select=id,user_id,home_id,type,priority,title,body,created_at`,
    { method: "PATCH", headers: { Prefer: "return=representation" }, body: JSON.stringify({ pushed_at: new Date().toISOString() }) },
  );
  if (!claim.ok) return new Response(`base: HTTP ${claim.status}`, { status: 502 });
  const [n] = (await claim.json()) as Notification[];
  if (!n) return Response.json({ skipped: true });

  const tokens = (await (await rest(`push_tokens?user_id=eq.${n.user_id}&select=token,platform,locale`)).json()) as Token[];
  if (!tokens.length) return Response.json({ sent: 0 });

  const access = await googleAccess();
  const results = await Promise.all(tokens.map((t) => sendOne(n, t, access)));
  return Response.json({
    sent: results.filter((r) => r === "sent").length,
    dropped: results.filter((r) => r === "dropped").length,
    failed: results.filter((r) => r === "failed").length,
  });
});
