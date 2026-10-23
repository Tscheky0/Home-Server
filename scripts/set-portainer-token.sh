#!/usr/bin/env bash
# Trägt ein Portainer Access Token für die Homepage Kachel ein.
# Token anlegen: https://portainer.home > oben rechts Benutzer > My account > Access tokens > Add access token
# Das Token wird verdeckt abgefragt und landet nur in docker/homepage/.env (nicht im Repo).

set -euo pipefail
cd "$(dirname "$0")/.."
ENV=docker/homepage/.env

read -rsp "Portainer Access Token (ptr_...): " TOKEN; echo
[[ "$TOKEN" == ptr_* ]] || { echo "Das sieht nicht wie ein Portainer Token aus (beginnt mit ptr_)."; exit 1; }

# Umgebungs ID der lokalen Docker Umgebung herausfinden
ENVID=$(curl -sk -H "X-API-Key: $TOKEN" https://192.168.137.10:9443/api/endpoints \
  | jq -r 'map(select(.Type==1 or .Type==2)) | .[0].Id // empty')
[ -n "$ENVID" ] || { echo "Token ungültig oder keine Docker Umgebung gefunden."; exit 1; }

sed -i "s|^HOMEPAGE_VAR_PORTAINER_KEY=.*|HOMEPAGE_VAR_PORTAINER_KEY=$TOKEN|" "$ENV"
sed -i "s|^HOMEPAGE_VAR_PORTAINER_ENV=.*|HOMEPAGE_VAR_PORTAINER_ENV=$ENVID|" "$ENV"
(cd docker/homepage && docker compose up -d --force-recreate homepage >/dev/null 2>&1)
echo "Eingetragen (Umgebung $ENVID). Homepage startet neu, in etwa 30 Sekunden neu laden."
