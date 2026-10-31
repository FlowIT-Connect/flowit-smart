# Site Solea : image de production (Next.js « standalone »).
#   docker build -t solea-site .
#   docker run -p 3000:3000 --env-file .env solea-site
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:22-alpine AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build
# Base de géolocalisation IP gratuite DB-IP Lite (licence CC BY 4.0, attribution dans le pied de page).
# Facultative : si le téléchargement échoue, le site se contente de la langue du navigateur.
RUN mkdir -p data && (wget -qO- "https://download.db-ip.com/free/dbip-country-lite-$(date -u +%Y-%m).mmdb.gz" | gunzip > data/dbip-country-lite.mmdb || rm -f data/dbip-country-lite.mmdb)

FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0 GEOIP_DB=/app/data/dbip-country-lite.mmdb
RUN addgroup -S solea && adduser -S solea -G solea
COPY --from=build --chown=solea:solea /app/.next/standalone ./
COPY --from=build --chown=solea:solea /app/.next/static ./.next/static
COPY --from=build --chown=solea:solea /app/public ./public
COPY --from=build --chown=solea:solea /app/data ./data
USER solea
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:3000/api/geo >/dev/null || exit 1
CMD ["node", "server.js"]
