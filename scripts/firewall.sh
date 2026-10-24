#!/usr/bin/env bash
# Firewall (ufw) für Dienste, die direkt am Host lauschen: SSH, CasaOS, Samba, Node Exporter.
# Von Docker veröffentlichte Ports (53, 443, 81, 8080, 9443) laufen an ufw vorbei und sind
# bereits in den Compose Dateien auf LAN und Tailscale Adresse gebunden.
#   ssh -t j@192.168.137.10 "sudo ~/homeserver/scripts/firewall.sh"
# Schutz gegen Aussperren: ohne Bestätigung innerhalb von 2 Minuten wird ufw wieder abgeschaltet.

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten"; exit 1; }

LAN=192.168.137.0/24
DOCKER=172.16.0.0/12

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# Tailscale: direkte WireGuard Verbindungen und alles, was über das Tailnet kommt (Geräte brauchen Freigabe)
ufw allow 41641/udp comment 'Tailscale WireGuard'
ufw allow in on tailscale0 comment 'Tailnet'

# Aus dem LAN, also vom Windows PC
ufw allow from $LAN to any port 22 proto tcp comment 'SSH'
ufw allow from $LAN to any port 80 proto tcp comment 'CasaOS'
ufw allow from $LAN to any port 139,445 proto tcp comment 'Samba'
ufw allow from $LAN to any port 137,138 proto udp comment 'Samba'

# Prometheus im Docker Netz fragt den Node Exporter am Host ab
ufw allow from $DOCKER to any port 9100 proto tcp comment 'Node Exporter'

# NPM im Docker Netz leitet https://cockpit.home an Cockpit am Host weiter
ufw allow from $DOCKER to any port 9090 proto tcp comment 'Cockpit über NPM'

ufw --force enable
ufw status verbose

( sleep 120 && ufw --force disable && echo "Keine Bestätigung, ufw wieder abgeschaltet" | wall ) &
rollback=$!

echo
echo "Firewall ist an. Neues PowerShell Fenster öffnen und testen: ssh j@192.168.137.10"
read -r -t 115 -p "Klappt SSH im neuen Fenster? Dann hier 'ja' eingeben: " answer || true
if [ "${answer:-}" = ja ]; then
  kill $rollback
  echo "Bestätigt, Firewall bleibt an."
else
  echo "Nicht bestätigt, ufw wird in Kürze wieder abgeschaltet."
fi
