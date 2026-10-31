import { test } from "node:test";
import assert from "node:assert/strict";
import { suggest, parseAcceptLanguage } from "../../src/lib/locales.ts";
import { convert, formatPrice } from "../../src/lib/money.ts";

test("Algérie : arabe si le navigateur préfère l'arabe, sinon français, en DZD", () => {
  assert.deepEqual(suggest("DZ", "ar-DZ,ar;q=0.9,fr;q=0.8"), { country: "DZ", locale: "ar", currency: "DZD" });
  assert.deepEqual(suggest("DZ", "fr-FR,fr;q=0.9"), { country: "DZ", locale: "fr", currency: "DZD" });
  assert.deepEqual(suggest("DZ", "en-US"), { country: "DZ", locale: "fr", currency: "DZD" });
});

test("exemples du cahier des charges", () => {
  assert.deepEqual(suggest("FR", "fr"), { country: "FR", locale: "fr", currency: "EUR" });
  assert.deepEqual(suggest("US", "en-US"), { country: "US", locale: "en", currency: "USD" });
  assert.deepEqual(suggest("GB", "en-GB"), { country: "GB", locale: "en", currency: "GBP" });
  assert.deepEqual(suggest("DE", "de-DE"), { country: "DE", locale: "de", currency: "EUR" });
  assert.deepEqual(suggest("ES", "es-ES"), { country: "ES", locale: "es", currency: "EUR" });
  assert.deepEqual(suggest("SA", "ar-SA"), { country: "SA", locale: "ar", currency: "SAR" });
  assert.deepEqual(suggest("AE", "en-AE,en"), { country: "AE", locale: "en", currency: "AED" });
  assert.deepEqual(suggest("AE", "ar"), { country: "AE", locale: "ar", currency: "AED" });
});

test("sans pays détecté : région du navigateur, puis langue du navigateur", () => {
  assert.equal(suggest(null, "fr-DZ,fr;q=0.9").country, "DZ");
  assert.deepEqual(suggest(null, "it"), { country: "INT", locale: "it", currency: "EUR" });
  assert.deepEqual(suggest(null, "ja-JP"), { country: "INT", locale: "en", currency: "EUR" });
  assert.deepEqual(suggest("XX", null), { country: "INT", locale: "en", currency: "EUR" });
});

test("lecture de Accept-Language", () => {
  assert.deepEqual(parseAcceptLanguage("en;q=0.5, ar-DZ, fr;q=0.8"), [{ lang: "ar", region: "DZ" }, { lang: "fr", region: undefined }, { lang: "en", region: undefined }]);
  assert.deepEqual(parseAcceptLanguage(""), []);
});

test("conversion et arrondi par devise", () => {
  assert.equal(convert(100, "EUR", "EUR"), 100);
  assert.equal(convert(10, "EUR", "DZD") % 10, 0);
  assert.match(formatPrice(1234.5, "EUR", "fr"), /1\s?234,50\s?€/);
  assert.match(formatPrice(15000, "DZD", "ar"), /15[.,\s\u202f]?000/);
});
