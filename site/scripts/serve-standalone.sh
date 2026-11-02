#!/bin/sh
# Lance la version compilée (sortie « standalone ») sur le port $PORT (3100 par défaut).
set -e
cd "$(dirname "$0")/.."
rm -rf .next/standalone/public .next/standalone/.next/static
cp -r public .next/standalone/public
cp -r .next/static .next/standalone/.next/static
cd .next/standalone
PORT="${PORT:-3100}" HOSTNAME="${HOSTNAME:-127.0.0.1}" exec node server.js
