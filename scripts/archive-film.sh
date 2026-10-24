#!/usr/bin/env bash
# Lädt einen Film von archive.org in den Filme Ordner von Jellyfin.
#   ./scripts/archive-film.sh https://archive.org/details/night_of_the_living_dead
# Nimmt die größte MP4 Datei des Eintrags (beste Qualität, läuft ohne Umwandeln im Browser)
# und legt sie als "Titel (Jahr)/Titel (Jahr).mp4" ab, so erkennt Jellyfin den Film.
# Nicht alles auf archive.org ist gemeinfrei. Ohne Lizenzangabe bricht das Skript ab,
# nach eigener Prüfung (z.B. Sammlung feature_films, "Public Domain") mit FORCE=1 erneut starten.

set -euo pipefail

MEDIA_DIR="${MEDIA_DIR:-$HOME/media}"
[ $# -eq 1 ] || { echo "Aufruf: $0 <archive.org Link oder ID>"; exit 1; }

id="${1%/}"
id="${id##*/details/}"
id="${id%%/*}"

meta=$(curl -fsSL "https://archive.org/metadata/$id")
[ "$(jq -r '.metadata.identifier // empty' <<<"$meta")" = "$id" ] || { echo "Eintrag $id nicht gefunden"; exit 1; }

title=$(jq -r '.metadata.title | if type == "array" then .[0] else . end' <<<"$meta")
year=$(jq -r '(.metadata.year // .metadata.date // "") | if type == "array" then .[0] else . end | tostring | .[0:4]' <<<"$meta")
license=$(jq -r '.metadata.licenseurl // empty' <<<"$meta")
file=$(jq -r '[.files[] | select(.name | test("\\.mp4$"; "i"))] | max_by(.size | tonumber) | .name // empty' <<<"$meta")

[ -n "$file" ] || { echo "Keine MP4 Datei in $id"; exit 1; }

echo "Titel:  $title ($year)"
echo "Lizenz: ${license:-keine Angabe}"
if [ -z "$license" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "Keine Lizenz angegeben. Auf https://archive.org/details/$id prüfen, ob der Film gemeinfrei ist,"
  echo "dann mit FORCE=1 $0 $1 erneut starten."
  exit 1
fi

name=$(tr -d '/\\:*?"<>|' <<<"$title")
[ -n "$year" ] && name="$name ($year)"
dir="$MEDIA_DIR/Filme/$name"
mkdir -p "$dir"

file_url=$(jq -rn --arg f "$file" '$f | @uri')
curl -fL --retry 3 -C - -o "$dir/$name.mp4" "https://archive.org/download/$id/$file_url"

echo
echo "Fertig: $dir/$name.mp4"
echo "Jellyfin findet den Film beim nächsten Scan (Dashboard > Bibliotheken > Scannen)."
