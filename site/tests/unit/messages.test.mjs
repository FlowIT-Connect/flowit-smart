// Les 6 langues ont exactement les mêmes clés, et aucun nom de plateforme concurrente n'apparaît.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const dir = new URL("../../messages/", import.meta.url);
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".json"));
const load = (f) => JSON.parse(fs.readFileSync(new URL(f, dir), "utf8"));

function shape(v, prefix = "") {
  if (Array.isArray(v)) return [`${prefix}[${v.length}]`, ...v.flatMap((x, i) => (typeof x === "object" ? shape(x, `${prefix}[${i}]`) : []))];
  if (v && typeof v === "object") return Object.entries(v).flatMap(([k, x]) => shape(x, prefix ? `${prefix}.${k}` : k));
  return [prefix];
}

test("6 langues présentes", () => assert.deepEqual(files.sort(), ["ar.json", "de.json", "en.json", "es.json", "fr.json", "it.json"]));

test("mêmes clés dans toutes les langues", () => {
  const ref = shape(load("fr.json")).sort();
  for (const f of files) assert.deepEqual(shape(load(f)).sort(), ref, f);
});

test("aucun texte vide", () => {
  for (const f of files) {
    const walk = (v, p) => (typeof v === "string" ? assert.ok(v.trim(), `${f} ${p}`) : v && typeof v === "object" && Object.entries(v).forEach(([k, x]) => walk(x, `${p}.${k}`)));
    walk(load(f), "");
  }
});

test("aucune plateforme concurrente citée", () => {
  const banned = /home ?assistant|tuya|smart ?life|google home|alexa|apple home|homekit|smartthings|jeedom|zigbee2mqtt|ttlock/i;
  for (const f of files) assert.doesNotMatch(fs.readFileSync(new URL(f, dir), "utf8"), banned, f);
});

test("placeholders identiques au français", () => {
  const ph = (s) => (s.match(/\{\w+\}/g) ?? []).sort().join();
  const fr = load("fr.json");
  for (const f of files) {
    const other = load(f);
    const walk = (a, b, p) => {
      if (typeof a === "string") return assert.equal(ph(b), ph(a), `${f} ${p}`);
      if (a && typeof a === "object") for (const k of Object.keys(a)) walk(a[k], b[k], `${p}.${k}`);
    };
    walk(fr, other, "");
  }
});
