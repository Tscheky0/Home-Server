#!/usr/bin/env bash
# Cockpit als Weboberfläche für den Server: Logs (auch geblockte Pakete der Firewall), Dienste,
# Updates, Speicher und ein Terminal im Browser. Erreichbar nur als https://cockpit.home über NPM.
#   ssh -t j@192.168.137.10 "sudo ~/homeserver/scripts/install-cockpit.sh"
# Ohne cockpit-networkmanager: der würde NetworkManager nachziehen, der Server läuft aber mit
# Netplan und systemd-networkd (siehe docs/ERWEITERUNG.md).

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo starten"; exit 1; }

LAN_IP=192.168.137.10

apt-get update -q
apt-get install -y --no-install-recommends cockpit-ws cockpit-system cockpit-bridge cockpit-storaged cockpit-packagekit

# Hinter NPM: TLS endet am Proxy, Cockpit spricht intern HTTP und vertraut dem Header von NPM
mkdir -p /etc/cockpit
cat > /etc/cockpit/cockpit.conf <<EOF
[WebService]
Origins = https://cockpit.home wss://cockpit.home
ProtocolHeader = X-Forwarded-Proto
AllowUnencrypted = true
EOF

# Nur auf der LAN Adresse lauschen, nicht auf Tailscale. FreeBind, falls die Adresse beim Booten noch fehlt.
mkdir -p /etc/systemd/system/cockpit.socket.d
cat > /etc/systemd/system/cockpit.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=$LAN_IP:9090
FreeBind=yes
EOF

# NPM im Docker Netz darf Cockpit erreichen, sonst niemand
ufw allow from 172.16.0.0/12 to any port 9090 proto tcp comment 'Cockpit über NPM'

# Firewall Logs für Cockpit lesbar machen (geblockte Pakete erscheinen als [UFW BLOCK])
ufw logging low

systemctl daemon-reload
systemctl enable --now cockpit.socket
systemctl restart cockpit.socket

echo
ss -tlnH | grep ':9090' && echo "Cockpit lauscht auf $LAN_IP:9090. Login mit dem normalen Server Benutzer."
