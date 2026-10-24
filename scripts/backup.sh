#!/usr/bin/env bash
# Nächtliches Backup aller wichtigen Docker Volumes, der Configs und der eigenen CA.
# Läuft per cron um 3:30 (crontab -l), Ergebnis in BACKUP_DIR/<Datum>, die letzten KEEP Tage bleiben.
#   30 3 * * * $HOME/homeserver/scripts/backup.sh >> $HOME/backups/backup.log 2>&1
# Nextcloud Datenbank als SQL Dump, die übrigen Volumes als tar.gz. Die Container eines Volumes
# werden dafür kurz gestoppt, damit SQLite Datenbanken (Uptime Kuma, Grafana, Pi-hole) konsistent sind.
# Prometheus Daten, Jellyfin Cache und Redis fehlen bewusst, sie bauen sich von selbst wieder auf.
#
# Wiederherstellen eines Volumes (Container vorher stoppen):
#   docker run --rm -v <volume>:/v -v ~/backups/<Datum>:/b alpine sh -c "rm -rf /v/* && tar xzf /b/<volume>.tar.gz -C /v"
# Nextcloud Datenbank:
#   gunzip -c ~/backups/<Datum>/nextcloud-db.sql.gz | docker exec -i nextcloud-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
KEEP="${KEEP:-3}"
VOLUMES=(
  pihole_pihole-data
  proxy_npm-data
  proxy_npm-letsencrypt
  portainer_data
  uptime-kuma_uptime-kuma-data
  monitoring_grafana-data
  jellyfin_jellyfin-config
  nextcloud_nextcloud-html
)

dest="$BACKUP_DIR/$(date +%F)"
mkdir -p "$dest"
echo "=== Backup $(date '+%F %T') nach $dest"

occ() { docker exec -u www-data nextcloud php occ "$@" >/dev/null; }

# Falls etwas schiefgeht, gestoppte Container und Nextcloud trotzdem wieder freigeben
stopped=""
maintenance=0
cleanup() {
  if [ -n "$stopped" ]; then docker start $stopped >/dev/null; fi
  if [ "$maintenance" = 1 ]; then occ maintenance:mode --off; fi
}
trap cleanup EXIT

docker exec nextcloud-db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --all-databases' \
  | gzip > "$dest/nextcloud-db.sql.gz"
echo "nextcloud-db.sql.gz $(du -h "$dest/nextcloud-db.sql.gz" | cut -f1)"

for v in "${VOLUMES[@]}"; do
  if [ "$v" = nextcloud_nextcloud-html ]; then
    # Nextcloud nicht stoppen: das Kopieren dauert Minuten und Uptime Kuma würde Alarm schlagen.
    # Der Wartungsmodus hält Schreibzugriffe und Cron an, status.php meldet weiter "installed":true.
    occ maintenance:mode --on
    maintenance=1
  else
    stopped=$(docker ps -q --filter volume="$v" | tr '\n' ' ')
    if [ -n "$stopped" ]; then docker stop $stopped >/dev/null; fi
  fi
  docker run --rm -v "$v":/v:ro -v "$dest":/b alpine \
    sh -c "tar czf /b/$v.tar.gz -C /v . && chown $(id -u):$(id -g) /b/$v.tar.gz"
  if [ "$maintenance" = 1 ]; then
    occ maintenance:mode --off
    maintenance=0
  elif [ -n "$stopped" ]; then
    docker start $stopped >/dev/null
    stopped=""
  fi
  echo "$v.tar.gz $(du -h "$dest/$v.tar.gz" | cut -f1)"
done

tar czf "$dest/configs.tar.gz" -C "$HOME" homeserver .local/share/mkcert
chmod 600 "$dest"/*
echo "configs.tar.gz $(du -h "$dest/configs.tar.gz" | cut -f1)"

ls -1d "$BACKUP_DIR"/20??-??-?? | head -n -"$KEEP" | xargs -r rm -rf
echo "Fertig, vorhanden: $(ls -1d "$BACKUP_DIR"/20??-??-?? | xargs -n1 basename | tr '\n' ' ')"
