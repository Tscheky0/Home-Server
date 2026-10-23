#!/usr/bin/env bash
# Lädt die Grafana Dashboards von grafana.com und bindet sie an die
# provisionierte Datenquelle (uid prometheus). Einmal vor dem ersten Start ausführen.

set -euo pipefail
cd "$(dirname "$0")"
mkdir -p grafana/dashboards

declare -A DASHBOARDS=(
  [node-exporter-full]=1860
  [cadvisor]=14282
  [pihole]=10176
)

for name in "${!DASHBOARDS[@]}"; do
  id=${DASHBOARDS[$name]}
  echo "Lade $name ($id)"
  curl -fsSL "https://grafana.com/api/dashboards/$id/revisions/latest/download" \
    | sed -E 's/\$\{DS_[A-Z0-9_]+\}/prometheus/g' \
    > "grafana/dashboards/$name.json"
done

ls -l grafana/dashboards
