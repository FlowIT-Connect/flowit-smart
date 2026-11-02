// Captures d'écran : node scripts/screenshots.mjs <url de base> <dossier> [chemins...]
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const [base = "http://localhost:3100", out = "screenshots-tmp", ...paths] = process.argv.slice(2);
const sizes = { desktop: { width: 1440, height: 900 }, tablet: { width: 820, height: 1180 }, mobile: { width: 390, height: 844 } };
const list = paths.length ? paths : ["/fr"];
const browser = await chromium.launch();
for (const p of list) {
  for (const [name, viewport] of Object.entries(sizes)) {
    if (process.env.ONLY && !process.env.ONLY.split(",").includes(name)) continue;
    const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, locale: "fr-FR" });
    await ctx.addCookies([{ name: "solea_prefs", value: "1", url: base }]);
    const page = await ctx.newPage();
    await page.goto(base + p, { waitUntil: "load" });
    await page.evaluate(() => document.querySelectorAll(".reveal").forEach((e) => e.classList.add("is-visible")));
    await page.waitForTimeout(400);
    const file = `${out}/${p.replace(/\//g, "_").replace(/^_/, "") || "home"}_${name}.png`;
    await page.screenshot({ path: file, fullPage: process.env.FULL !== "0" });
    console.log(file);
    await ctx.close();
  }
}
await browser.close();
