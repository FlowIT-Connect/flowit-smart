// Météo du logement pour les automatisations (vent, rafales, pluie, température,
// lever / coucher du soleil). Fournisseur réglable :
//   WEATHER_PROVIDER=open-meteo (par défaut, gratuit pour les essais)
//   WEATHER_API_KEY=…            (offre commerciale Open-Meteo : customer-api.open-meteo.com)
// Les automatisations ne dépendent jamais du téléphone : la passerelle lit la météo elle-même.

const FREE_URL = 'https://api.open-meteo.com/v1/forecast';
const PAID_URL = 'https://customer-api.open-meteo.com/v1/forecast';

/** Nombre fini ou null. */
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** Heure locale Open-Meteo ("2026-11-01T06:58") + décalage UTC en secondes → Date. */
function localToDate(text, offsetSeconds) {
  if (typeof text !== 'string') return null;
  const ms = Date.parse(`${text}:00Z`);
  return Number.isFinite(ms) ? new Date(ms - (offsetSeconds ?? 0) * 1000) : null;
}

/**
 * Lit la météo actuelle. Renvoie
 * { wind_speed, wind_gust, precipitation, temperature, is_day, sunrise, sunset, observed_at, source }
 * (vent en km/h, pluie en mm, température en °C, heures en Date).
 */
export async function fetchWeather({ latitude, longitude, apiKey = null, fetchImpl = fetch, timeoutMs = 10_000 }) {
  const params = new URLSearchParams({
    latitude: Number(latitude).toFixed(4),
    longitude: Number(longitude).toFixed(4),
    current: 'temperature_2m,precipitation,wind_speed_10m,wind_gusts_10m,is_day',
    daily: 'sunrise,sunset',
    timezone: 'auto',
    forecast_days: '1',
    wind_speed_unit: 'kmh',
  });
  if (apiKey) params.set('apikey', apiKey);
  const res = await fetchImpl(`${apiKey ? PAID_URL : FREE_URL}?${params}`, { signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`Météo indisponible (HTTP ${res.status})`);
  const j = await res.json();
  const c = j.current ?? {};
  const offset = num(j.utc_offset_seconds) ?? 0;
  return {
    wind_speed: num(c.wind_speed_10m),
    wind_gust: num(c.wind_gusts_10m),
    precipitation: num(c.precipitation),
    temperature: num(c.temperature_2m),
    is_day: c.is_day === 1 ? true : c.is_day === 0 ? false : null,
    sunrise: localToDate(j.daily?.sunrise?.[0], offset),
    sunset: localToDate(j.daily?.sunset?.[0], offset),
    observed_at: localToDate(c.time, offset) ?? new Date(),
    source: apiKey ? 'open-meteo-pro' : 'open-meteo',
  };
}

/** Valeur d'une mesure météo utilisée par un déclencheur ou une condition. */
export function weatherMetric(weather, metric) {
  if (!weather) return null;
  switch (metric) {
    case 'wind_speed':
    case 'wind_gust':
    case 'precipitation':
    case 'temperature':
      return num(weather[metric]);
    default:
      return null;
  }
}
