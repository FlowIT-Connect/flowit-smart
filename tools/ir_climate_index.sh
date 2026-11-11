#!/usr/bin/env bash
# Régénère l'index des télécommandes de clim Broadlink (bibliothèque libre SmartIR, licence MIT)
# pour la passerelle et l'app. Usage : tools/ir_climate_index.sh <dossier SmartIR cloné>
# Penser à mettre SMARTIR_COMMIT (bridge/src/adapters/broadlink.js) au commit utilisé.
set -euo pipefail
src="${1:?dossier SmartIR}/codes/climate"
out=bridge/src/adapters/ir_climate_index.json
for f in "$src"/*.json; do
  id=$(basename "$f" .json)
  jq -c --argjson id "$id" 'select(.supportedController=="Broadlink" and .commandsEncoding=="Base64" and (.commands.off|type)=="string" and (.operationModes|type)=="array")
    | {id:$id, brand:(.manufacturer|tostring|gsub("^\\s+|\\s+$";"")), models:[(.supportedModels//[])[]|tostring],
       modes:.operationModes, fans:(.fanModes//[]), swings:(.swingModes//[]), min:.minTemperature, max:.maxTemperature, step:(.precision//1)}' "$f" 2>/dev/null || true
done | jq -s -c 'sort_by((.brand|ascii_downcase), .id)' > "$out"
cp "$out" app/assets/ir/climate_index.json
echo "$(jq length "$out") télécommandes"
