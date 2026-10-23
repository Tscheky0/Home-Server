#!/usr/bin/env bash
# Erzeugt eine lokale Zertifizierungsstelle (mkcert) und ein Zertifikat für alle .home Namen.
# Ergebnis in ./certs: home.crt und home.key, in NPM als Custom Certificate hochladen.
# rootCA.pem auf Windows (Vertrauenswürdige Stammzertifizierungsstellen) und Handys installieren.
# Kein *.home Wildcard: Browser akzeptieren Wildcards direkt unter einer Endung nicht.
# Braucht kein sudo: mkcert landet in ~/.local/bin, die CA in ~/.local/share/mkcert.

set -euo pipefail

NAMES=(npm.home pihole.home portainer.home kuma.home cloud.home grafana.home dashboard.home)
export CAROOT="${CAROOT:-$HOME/.local/share/mkcert}"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v mkcert >/dev/null; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/mkcert" "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
  chmod +x "$HOME/.local/bin/mkcert"
fi

cd "$(dirname "$0")/.."
mkdir -p certs
mkcert -cert-file certs/home.crt -key-file certs/home.key "${NAMES[@]}"
cp "$CAROOT/rootCA.pem" certs/rootCA.pem
chmod 600 certs/home.key

echo
echo "Fertig. Dateien in $(pwd)/certs:"
ls -l certs
echo "rootCA-key.pem in $CAROOT niemals weitergeben."
