import { test } from "node:test";
import assert from "node:assert/strict";
import { countryFromHeaders } from "../../src/lib/geo-headers.ts";

test("pays lu dans les en-têtes Cloudflare et Netlify", () => {
  assert.equal(countryFromHeaders(new Headers({ "cf-ipcountry": "dz" })), "DZ");
  assert.equal(countryFromHeaders(new Headers({ "x-country": "FR" })), "FR");
  const geo = Buffer.from(JSON.stringify({ country: { code: "CA", name: "Canada" } })).toString("base64");
  assert.equal(countryFromHeaders(new Headers({ "x-nf-geo": geo })), "CA");
  assert.equal(countryFromHeaders(new Headers({ "x-nf-geo": "pas du base64 !" })), null);
  assert.equal(countryFromHeaders(new Headers({ "cf-ipcountry": "XX" })), null);
});
