// Tests de bout en bout dans un vrai navigateur (Chromium + Playwright).
// Usage : site compilé et lancé (scripts/serve-standalone.sh), puis : node tests/e2e.mjs [url]
import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const base = process.argv[2] ?? "http://127.0.0.1:3100";
const locales = ["fr", "en", "ar", "es", "de", "it"];
const paths = ["", "/discover", "/devices", "/solutions", "/automations", "/gateway", "/partners", "/contact", "/shop", "/privacy"];
let passed = 0;
const results = [];
async function check(name, fn) {
  try {
    await fn();
    passed++;
    results.push(`OK   ${name}`);
  } catch (e) {
    results.push(`FAIL ${name}\n     ${String(e.message).split("\n")[0]}`);
  }
}

const browser = await chromium.launch();
const ctx = await browser.newContext({ locale: "fr-FR" });
await ctx.addCookies([{ name: "solea_prefs", value: "1", url: base }]);
const page = await ctx.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));

await check("60 pages (10 pages × 6 langues) répondent, langue et sens corrects, hreflang complet", async () => {
  for (const l of locales) {
    for (const p of paths) {
      const res = await page.goto(`${base}/${l}${p}`, { waitUntil: "domcontentloaded" });
      assert.equal(res.status(), 200, `${l}${p}`);
      assert.equal(await page.getAttribute("html", "lang"), l);
      assert.equal(await page.getAttribute("html", "dir"), l === "ar" ? "rtl" : "ltr");
      const alt = await page.$$eval('link[rel="alternate"][hreflang]', (els) => els.map((e) => e.getAttribute("hreflang")).sort());
      assert.deepEqual(alt, [...locales, "x-default"].sort(), `${l}${p} hreflang`);
      const title = await page.title();
      assert.ok(title.length > 5, `${l}${p} titre`);
      assert.equal(await page.locator("h1").count(), 1, `${l}${p} un seul h1`);
    }
  }
});

await check("aucune erreur JavaScript dans le navigateur", async () => assert.deepEqual(errors, []));

await check("page inconnue : 404 traduite", async () => {
  const res = await page.goto(`${base}/de/nicht-da`);
  assert.equal(res.status(), 404);
  assert.match(await page.textContent("h1"), /Seite nicht gefunden/);
});

await check("racine : redirection selon la langue du navigateur (arabe)", async () => {
  const c = await browser.newContext({ locale: "ar-DZ", extraHTTPHeaders: { "Accept-Language": "ar-DZ,ar;q=0.9" } });
  const p = await c.newPage();
  await p.goto(base + "/");
  assert.match(p.url(), /\/ar$/);
  await c.close();
});

await check("première visite : bandeau pays → arabe + DZD, choix mémorisé", async () => {
  const c = await browser.newContext({ locale: "ar-DZ", extraHTTPHeaders: { "Accept-Language": "ar-DZ,ar;q=0.9", "X-Country-Code": "DZ" } });
  const p = await c.newPage();
  await p.goto(`${base}/fr`);
  const banner = p.locator('[role="region"]');
  await banner.waitFor({ timeout: 5000 });
  assert.match(await banner.textContent(), /Algérie/);
  assert.match(await banner.textContent(), /DZD/);
  await banner.getByRole("button", { name: "Oui, merci" }).click();
  await p.waitForURL(/\/ar$/);
  const cookies = Object.fromEntries((await c.cookies()).map((k) => [k.name, k.value]));
  assert.equal(cookies.solea_currency, "DZD");
  assert.equal(cookies.solea_country, "DZ");
  assert.equal(cookies.solea_prefs, "1");
  await p.reload();
  await p.waitForTimeout(800);
  assert.equal(await p.locator('[role="region"]').count(), 0, "le bandeau ne revient pas");
  await c.close();
});

await check("préférences : changer langue, pays et devise à la main", async () => {
  await page.goto(`${base}/fr/devices`);
  await page.getByRole("button", { name: "Langue, pays et devise" }).click();
  await page.selectOption("#pref-country", "GB");
  assert.equal(await page.inputValue("#pref-cur"), "GBP", "devise proposée selon le pays");
  await page.selectOption("#pref-cur", "CHF");
  await page.selectOption("#pref-lang", "it");
  await page.getByRole("button", { name: "Enregistrer" }).click();
  await page.waitForURL(/\/it\/devices$/);
  const cookies = Object.fromEntries((await ctx.cookies()).map((k) => [k.name, k.value]));
  assert.equal(cookies.solea_currency, "CHF");
  assert.equal(cookies.solea_country, "GB");
  assert.equal(cookies.NEXT_LOCALE, "it");
  await page.waitForFunction(() => document.querySelector("header")?.textContent?.includes("CHF"), null, { timeout: 5000 });
});

await check("formulaire contact : sans base reliée, message clair (pas de faux succès)", async () => {
  await page.goto(`${base}/fr/contact?type=villa`);
  assert.equal(await page.inputValue("#c-type"), "villa");
  await page.fill("#c-first", "Amina");
  await page.fill("#c-last", "B.");
  await page.fill("#c-email", "amina@example.dz");
  await page.fill("#c-phone", "+213 555 12 34 56");
  await page.selectOption("#c-country", "DZ");
  await page.fill("#c-msg", "Villa de 300 m², éclairage et caméras.");
  await page.getByRole("button", { name: "Envoyer" }).click();
  const alert = page.locator('form [role="alert"]');
  await alert.waitFor();
  assert.match(await alert.textContent(), /pas encore relié|contact@solea-dz\.com/);
});

await check("formulaire Gateway : consentement obligatoire", async () => {
  await page.goto(`${base}/en/gateway`);
  await page.fill("#gw-email", "test@example.com");
  await page.selectOption("#gw-country", "FR");
  await page.getByRole("button", { name: "Notify me at launch" }).click();
  const valid = await page.$eval('input[name="consent_launch"]', (el) => el.checkValidity());
  assert.equal(valid, false);
});

await check("menu mobile", async () => {
  const c = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await c.addCookies([{ name: "solea_prefs", value: "1", url: base }]);
  const p = await c.newPage();
  await p.goto(`${base}/fr`);
  await p.getByRole("button", { name: "Menu" }).click();
  await p.locator("#mobile-menu").getByRole("link", { name: "Automatisations" }).click();
  await p.waitForURL(/\/fr\/automations$/);
  const overflow = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  assert.equal(overflow, false, "pas de défilement horizontal");
  await c.close();
});

await check("aucun défilement horizontal en arabe sur mobile (toutes les pages)", async () => {
  const c = await browser.newContext({ viewport: { width: 360, height: 780 } });
  await c.addCookies([{ name: "solea_prefs", value: "1", url: base }]);
  const p = await c.newPage();
  for (const path of paths) {
    await p.goto(`${base}/ar${path}`);
    const overflow = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert.equal(overflow, false, `/ar${path}`);
  }
  await c.close();
});

await check("SEO : sitemap (60 URL), robots, données structurées", async () => {
  const sm = await (await page.request.get(`${base}/sitemap.xml`)).text();
  assert.equal((sm.match(/<loc>/g) ?? []).length, 60);
  assert.match(sm, /hreflang="ar"/);
  const robots = await (await page.request.get(`${base}/robots.txt`)).text();
  assert.match(robots, /Sitemap: .*sitemap\.xml/);
  assert.match(robots, /Disallow: \/admin/);
  await page.goto(`${base}/fr`);
  const ld = JSON.parse(await page.textContent('script[type="application/ld+json"]'));
  assert.equal(ld["@type"], "Organization");
});

await check("en-têtes de sécurité", async () => {
  const res = await page.request.get(`${base}/fr`);
  const h = res.headers();
  assert.equal(h["x-content-type-options"], "nosniff");
  assert.equal(h["x-frame-options"], "DENY");
  assert.ok(h["strict-transport-security"]);
  assert.equal(h["x-powered-by"], undefined);
});

await check("API géolocalisation : pas de cache, suggestion correcte", async () => {
  const res = await page.request.get(`${base}/api/geo`, { headers: { "X-Country-Code": "SA", "Accept-Language": "ar" } });
  assert.match(res.headers()["cache-control"], /no-store/);
  assert.deepEqual(await res.json(), { country: "SA", locale: "ar", currency: "SAR", detected: true });
});

await browser.close();
console.log(results.join("\n"));
console.log(`\n${passed}/${results.length} tests réussis`);
process.exit(passed === results.length ? 0 : 1);
