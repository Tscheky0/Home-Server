# Erweiterung: Monitoring, Cloud, Reverse Proxy und Dashboard

Dieses Dokument hält **alle Entscheidungen** für die Erweiterung des Homeservers fest.
Es ist die verbindliche Referenz: Wer etwas ändert, ändert es zuerst hier.

## 1. Ziel

| Dienst | Zweck | Adresse |
|:--|:--|:--|
| Nginx Proxy Manager | Reverse Proxy, sprechende Namen, HTTPS | `https://npm.home` |
| Uptime Kuma | Erreichbarkeit überwachen, Push aufs Handy | `https://kuma.home` |
| Nextcloud | Eigene Cloud für Dateien, Fotos, Kalender | `https://cloud.home` |
| Prometheus | Metriken sammeln (nur intern, kein Proxy Host) | `http://prometheus:9090` |
| Grafana | Live Diagramme zu Server, Containern, Pi-hole | `https://grafana.home` |
| Homepage | Startseite mit Kacheln für alle Dienste | `https://dashboard.home` |
| Pi-hole (bestehend) | DNS, jetzt zusätzlich über Proxy | `https://pihole.home/admin` |
| Portainer (bestehend) | Container Verwaltung, jetzt zusätzlich über Proxy | `https://portainer.home` |

## 2. Festgelegte Entscheidungen

| # | Thema | Entscheidung | Begründung |
|:--|:--|:--|:--|
| E1 | Struktur | Jeder Dienst ist ein eigener Stack unter `docker/<name>/` mit eigener `docker-compose.yml` und `.env.example` | Gleiches Muster wie Pi-hole und Portainer, einzeln in Portainer deploybar |
| E2 | Gemeinsames Netz | Ein externes Docker Netz `proxy`, einmalig mit `docker network create proxy` angelegt. Alle Weboberflächen hängen daran | NPM erreicht die Container über ihren Namen, ohne Host Ports |
| E3 | Host Ports | Nur NPM öffnet Ports: `80` und `443` auf LAN **und** Tailscale Adresse, Admin `81` nur auf LAN. Alle neuen Dienste haben **keine** eigenen Host Ports | Eine einzige, kontrollierte Eingangstür. Weiterhin 0 offene Ports ins Internet |
| E4 | Bestehende Ports | Pi-hole `8080` und Portainer `9443` bleiben auf der LAN Adresse als Notzugang, falls NPM ausfällt | Ausfallsicherheit |
| E5 | Domain | Endung `.home`, alle Namen zeigen auf eine Adresse (`PROXY_IP`, Standard: Tailscale IP des Servers) | Funktioniert für Handys im Tailnet und für den Windows PC, sofern er im Tailnet ist |
| E6 | DNS Einträge | Wildcard im Pi-hole per `FTLCONF_misc_dnsmasq_lines: address=/home/<PROXY_IP>` | Neue Dienste brauchen keinen neuen DNS Eintrag |
| E7 | HTTPS | Eigene lokale Zertifizierungsstelle mit **mkcert**, ein Zertifikat mit allen Namen als SAN (kein `*.home`, das lehnen Browser ab). Als *Custom Certificate* in NPM hochladen. Root CA auf Windows und Handys installieren | Let's Encrypt geht nicht: `.home` ist keine öffentliche Domain und es gibt keine offenen Ports |
| E8 | Boot Reihenfolge | `net.ipv4.ip_nonlocal_bind=1` per sysctl | Docker kann Ports an die Tailscale IP binden, auch wenn `tailscale0` beim Start noch nicht oben ist |
| E9 | Dashboard | **Homepage** (gethomepage.dev), nicht Homarr | Konfiguration als YAML im Repo statt Klicken in einer Datenbank, sehr leicht |
| E10 | Docker Socket | Homepage bekommt den Socket **nicht** direkt, sondern über `docker-socket-proxy` mit nur Lesezugriff auf Container | Socket Zugriff ist Root Zugriff, so bleibt nur das Nötigste erlaubt |
| E11 | Nextcloud | Offizielles Image `nextcloud:stable-apache`, MariaDB 11.4 LTS, Redis als Cache und Sperren, eigener Cron Container | Empfohlener Aufbau laut Nextcloud Doku |
| E12 | Monitoring | Prometheus, Node Exporter (Host), cAdvisor (Container), `ekofr/pihole-exporter` (Pi-hole v6 API). Aufbewahrung 15 Tage | Deckt Server, Container und Pi-hole ab, bei begrenztem Speicher |
| E13 | Node Exporter | `network_mode: host`, hört nur auf der LAN Adresse Port `9100` | Echte Netzwerk Metriken des Hosts, aber nicht aus dem Tailnet erreichbar |
| E14 | Grafana Dashboards | Datenquelle und Dashboards per Provisioning. Dashboards werden mit `fetch-dashboards.sh` von grafana.com geladen: Node Exporter Full (1860), cAdvisor (14282), Pi-hole Exporter (10176) | Reproduzierbar, nichts muss geklickt werden |
| E15 | Benachrichtigung | Uptime Kuma schickt über **ntfy** (App, kein Konto nötig) aufs Handy. Topic ist ein langer Zufallsname | Kostenlos, einfach, funktioniert ohne Portfreigabe |
| E16 | Geheimnisse | Alle Passwörter nur in `.env` je Stack, `.env` steht in `.gitignore`. Homepage liest Geheimnisse über `HOMEPAGE_VAR_*` | Keine Zugangsdaten im Repo |
| E17 | Image Tags | `latest` wie beim bestehenden Pi-hole, außer wo Major Sprünge gefährlich sind: Nextcloud `stable`, MariaDB `11.4`, Uptime Kuma `2` | Nextcloud darf keine Major Version überspringen |
| E18 | RAM Grenzen | `mem_limit` auf den großen Containern | 4 GB RAM gesamt, kein Dienst darf den Server lahmlegen |
| E19 | Port 80 | Auf dem Server läuft **CasaOS**, dessen Gateway belegt `*:80`. NPM veröffentlicht deshalb **nur 443** (und 81 im LAN). Adressen immer mit `https://` aufrufen. Wer Port 80 für NPM will, stellt in CasaOS den WebUI Port um (z. B. 8888) und ergänzt die 80er Zeilen in `docker/proxy` | CasaOS ohne Rückfrage zu verschieben könnte den Zugriff darauf brechen |
| E20 | Pi-hole und Portainer live | Zuerst nur ans Netz `proxy` gehängt. Bei der Sicherheitsprüfung dann mit den Compose Dateien aus dem Repo neu erstellt (Volumes `pihole_pihole-data` und `portainer_data` bleiben). Beide werden seitdem per `docker compose` aus `~/homeserver` verwaltet, Pi-hole erscheint in Portainer daher als „Limited“ Stack. Die alte Portainer Stack Datei liegt als `~/homeserver/rollback-pihole-portainer.yml` | Vorher hörten Pi-hole (8080) und Portainer (9000 ohne TLS, 9443) auf allen Schnittstellen, also auch im Tailnet |
| E24 | Pi-hole Passwort | Kein `FTLCONF_webserver_api_password` in der Compose Datei. Passwort einmalig mit `pihole setpassword`, gespeichert nur als Hash im Volume | Kein Klartext Passwort in `.env` oder `docker inspect` |
| E25 | Portainer Version | Fest `portainer/portainer-ce:2.45.3` statt `lts` | Auf dem Server lief 2.45.3, ein Wechsel auf das ältere `lts` hätte die Datenbank unlesbar gemacht |
| E22 | Windows PC | Der PC löst `.home` über die **hosts Datei** auf die LAN Adresse `192.168.137.10` auf (geht immer, auch ohne Tailscale). Tailscale am PC läuft mit `--accept-dns=false`: hat es das DNS übernommen, solange der PC nicht freigegeben oder der Server offline war, ging am PC gar kein Internet mehr | Pi-hole sieht wegen Docker NAT nicht, welcher Client fragt, und kann daher nicht je nach Netz antworten |
| E23 | Automatisierung | NPM (Zertifikat, Proxy Hosts) per REST API, Uptime Kuma per `docker/uptime-kuma/setup-kuma.js` (Socket.IO im Container), Pi-hole App Passwort per `pihole-FTL --config webserver.api.app_pwhash`. Dein eigenes Pi-hole Passwort bleibt unverändert | Reproduzierbar, nichts von Hand geklickt |
| E21 | Werte des echten Servers | LAN `192.168.137.10`, Tailscale `100.x.x.x` (anonymisiert), Repo liegt auf dem Server unter `~/homeserver`, Zugangsdaten in `~/homeserver/ZUGANGSDATEN.txt` (nur für den eigenen Benutzer lesbar) | Damit Befehle und Skripte reproduzierbar sind |

## Stand am 23.10.2026

Umgesetzt und geprüft auf dem Server: alle Container laufen, alle 7 `https://*.home` Adressen antworten über NPM mit dem eigenen Zertifikat,
Prometheus erreicht alle 4 Ziele (Pi-hole meldet 280.282 geblockte Domains), Grafana hat die 3 Dashboards, Nextcloud 34 ist installiert (Redis, Cron),
Uptime Kuma hat 10 Monitore, ntfy und die Status Page `homeserver`.

Offen (braucht dich):

- [x] `sudo cp ~/homeserver/config/sysctl/99-nonlocal-bind.conf /etc/sysctl.d/ && sudo sysctl --system` (E8)
- [ ] ntfy App aufs Handy, Topic aus `~/homeserver/ZUGANGSDATEN.txt` abonnieren (E15)
- [x] `certs/rootCA.pem` auf Windows installiert (LocalMachine\Root, per certutil)
- [ ] `certs/rootCA.pem` auf den Handys installieren (E7)
- [x] Windows PC: Tailscale mit `--accept-dns=false` (übernimmt nie das DNS des PCs) und hosts Einträge `192.168.137.10 <name>.home`, Sicherung als `hosts.bak-homeserver` (E22)
- [ ] Portainer Access Token anlegen und als `HOMEPAGE_VAR_PORTAINER_KEY` in `docker/homepage/.env` eintragen, dann `docker compose up -d`
- [x] Pi-hole und Portainer nur noch im LAN gebunden, Port 9000 ohne TLS entfernt (E20)
- [ ] CasaOS hört auf `*:80` in allen Netzen (auch Tailnet). Falls nicht genutzt: `sudo casaos-uninstall`
- [ ] Samba (139, 445) hat keine Freigaben, läuft aber in allen Netzen. Falls nicht genutzt: `sudo systemctl disable --now smbd nmbd`

## 3. Speicherbudget (4 GB RAM)

| Stack | Grenze | Typisch |
|:--|:--|:--|
| Pi-hole | | ~100 MB |
| Portainer | | ~50 MB |
| NPM | 256 MB | ~100 MB |
| Uptime Kuma | 256 MB | ~120 MB |
| Nextcloud (App, DB, Redis, Cron) | 768 + 512 + 128 MB | ~600 MB |
| Monitoring (Prometheus, Grafana, Exporter, cAdvisor) | 512 + 384 + 64 + 64 + 192 MB | ~550 MB |
| Homepage und Socket Proxy | 192 + 64 MB | ~130 MB |
| **Summe** | | **~1,5 GB** plus Ubuntu ~400 MB |

Empfehlung: 2 GB Swap anlegen, falls nicht vorhanden (`swapon --show`).

## 4. Reihenfolge der Inbetriebnahme

1. `config/sysctl/99-nonlocal-bind.conf` nach `/etc/sysctl.d/` kopieren, `sudo sysctl --system`
2. `docker network create proxy` (der eigene Benutzer ist in der Gruppe `docker`, kein sudo nötig)
3. Pi-hole und Portainer ans Netz hängen (`docker network connect proxy pihole`, ebenso `portainer`) und die `.home` Regel setzen (E20)
4. `docker/proxy` starten, Zertifikat mit `scripts/make-certs.sh` erzeugen, in NPM hochladen
5. Proxy Hosts laut Tabelle 5 anlegen
6. `docker/monitoring/fetch-dashboards.sh`, dann `docker/uptime-kuma`, `docker/nextcloud`, `docker/monitoring`, `docker/homepage` starten
7. Uptime Kuma: `docker exec -i -e KUMA_USER=... -e KUMA_PASS=... -e NTFY_TOPIC=... uptime-kuma node - < docker/uptime-kuma/setup-kuma.js`
8. Nextcloud: `occ config:app:set serverinfo token` und `occ background:cron`
9. Root CA auf Windows und Handys installieren

Nach dem Kopieren per scp: Ordner auf `755` setzen, sonst kann Grafana die Provisioning Dateien nicht lesen.

Die Stacks Monitoring und Homepage binden Dateien aus dem Repo ein (`./prometheus`, `./grafana`, `./config`).
Sie werden deshalb per `sudo docker compose up -d` im geklonten Repo auf dem Server gestartet,
oder in Portainer als Stack aus dem Git Repository, nicht über den Web Editor.

## 5. Proxy Hosts in NPM

Alle mit dem Custom Certificate, *Force SSL* und *HTTP/2* an. *Websockets Support* an, wo vermerkt.

| Domain | Schema | Ziel | Port | Websockets |
|:--|:--|:--|:--|:--|
| `npm.home` | http | `npm` | 81 | |
| `pihole.home` | http | `pihole` | 80 | |
| `portainer.home` | https | `portainer` | 9443 | ja |
| `kuma.home` | http | `uptime-kuma` | 3001 | ja |
| `cloud.home` | http | `nextcloud` | 80 | |
| `grafana.home` | http | `grafana` | 3000 | ja |
| `dashboard.home` | http | `homepage` | 3000 | |

Für `cloud.home` unter *Advanced* eintragen:

```nginx
client_max_body_size 10G;
proxy_request_buffering off;
```

## 6. Monitore in Uptime Kuma

| Name | Typ | Ziel |
|:--|:--|:--|
| Server Ping | Ping | `192.168.137.10` |
| Pi-hole DNS | DNS | Resolver `192.168.137.10` (Kuma braucht eine IP), Port 53, Name `google.com` |

| Pi-hole Web | HTTP | `http://pihole/admin/` |
| Portainer | HTTP | `https://portainer:9443` (Zertifikatsfehler ignorieren) |
| NPM | HTTP | `http://npm:81` |
| Nextcloud | HTTP Keyword | `http://nextcloud/status.php`, Keyword `"installed":true` |
| Grafana | HTTP | `http://grafana:3000/api/health` |
| Prometheus | HTTP | `http://prometheus:9090/-/healthy` |
| Homepage | HTTP | `http://homepage:3000` |
| Internet | Ping | `1.1.1.1` |

## 7. Bewusst nicht gemacht

| Was | Warum nicht |
|:--|:--|
| Ports ins Internet öffnen | Widerspricht dem Sicherheitskonzept, alles läuft über Tailscale |
| Homarr | Homepage gewählt (E9) |
| Tailscale HTTPS (`*.ts.net`) | Nur ein Name pro Gerät, passt nicht zu mehreren Diensten |
| Alertmanager | Alarme laufen über Uptime Kuma, spart RAM |
