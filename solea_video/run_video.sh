#!/bin/sh
# Relais vidéo MediaMTX + boîtier vidéo Solea. Arrêt du boîtier (relais figé, coupure
# Internet...) : le relais est arrêté puis tout est relancé 15 secondes plus tard.
cd /app || exit 1
stop() {
  kill "$NODE_PID" "$MTX_PID" 2>/dev/null
  exit 0
}
trap stop TERM INT
while true; do
  /mediamtx/mediamtx config/mediamtx.yml &
  MTX_PID=$!
  sleep 2
  node src/index.js &
  NODE_PID=$!
  wait "$NODE_PID"
  echo "Boîtier vidéo arrêté (code $?) : relance du relais et du boîtier dans 15 secondes."
  kill "$MTX_PID" 2>/dev/null
  wait "$MTX_PID" 2>/dev/null
  sleep 15
done
