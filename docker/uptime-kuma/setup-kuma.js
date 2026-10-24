// Ersteinrichtung von Uptime Kuma über die Socket.IO Schnittstelle:
// Admin, ntfy Benachrichtigung, alle Monitore aus docs/ERWEITERUNG.md und Status Page "homeserver".
// Läuft im Container, weil dort socket.io-client schon vorhanden ist:
//   docker exec -i -e KUMA_USER=admin -e KUMA_PASS=... -e NTFY_TOPIC=... uptime-kuma node - < setup-kuma.js

const { io } = require("/app/node_modules/socket.io-client");

const { KUMA_USER, KUMA_PASS, NTFY_TOPIC } = process.env;
const LAN = "192.168.137.10";

const socket = io("http://127.0.0.1:3001", { transports: ["websocket"] });
const call = (event, ...args) => new Promise((resolve) => socket.emit(event, ...args, resolve));

const base = {
    interval: 60,
    retryInterval: 60,
    resendInterval: 0,
    maxretries: 2,
    timeout: 48,
    active: true,
    upsideDown: false,
    ignoreTls: false,
    expiryNotification: false,
    maxredirects: 10,
    method: "GET",
    packetSize: 56,
    description: "",
    accepted_statuscodes: ["200-299"],
    conditions: [],
    kafkaProducerBrokers: [],
    kafkaProducerSaslOptions: { mechanism: "None" },
    rabbitmqNodes: [],
};

const monitors = [
    { name: "Server Ping", type: "ping", hostname: LAN },
    { name: "Pi-hole DNS", type: "dns", hostname: "google.com", dns_resolve_server: LAN, port: 53, dns_resolve_type: "A" },
    { name: "Pi-hole Web", type: "http", url: "http://pihole/admin/" },
    { name: "Portainer", type: "http", url: "https://portainer:9443", ignoreTls: true },
    { name: "Nginx Proxy Manager", type: "http", url: "http://npm:81" },
    { name: "Nextcloud", type: "keyword", url: "http://nextcloud/status.php", keyword: "\"installed\":true" },
    { name: "Grafana", type: "http", url: "http://grafana:3000/api/health" },
    { name: "Prometheus", type: "http", url: "http://prometheus:9090/-/healthy" },
    { name: "Homepage", type: "http", url: "http://homepage:3000" },
    { name: "Jellyfin", type: "keyword", url: "http://jellyfin:8096/health", keyword: "Healthy" },
    { name: "Cockpit", type: "http", url: `http://${LAN}:9090/ping` },
    { name: "Internet", type: "ping", hostname: "1.1.1.1" },
];

function fail(step, res) {
    console.error(`${step} fehlgeschlagen:`, res && res.msg);
    process.exit(1);
}

socket.on("connect", async () => {
    const needSetup = await call("needSetup");
    if (needSetup) {
        const res = await call("setup", KUMA_USER, KUMA_PASS);
        if (!res.ok) fail("setup", res);
        console.log("Admin angelegt");
    }

    // Die Monitorliste kommt direkt nach dem Login, deshalb vorher lauschen.
    // Damit legt ein zweiter Lauf nichts doppelt an.
    const monitorList = new Promise((resolve) => {
        socket.once("monitorList", (list) => resolve(Object.values(list)));
        setTimeout(() => resolve([]), 5000);
    });

    const login = await call("login", { username: KUMA_USER, password: KUMA_PASS, token: "" });
    if (!login.ok) fail("login", login);
    const existing = await monitorList;

    let notificationIDList = {};
    if (NTFY_TOPIC && existing.length === 0) {
        const res = await call("addNotification", {
            name: "ntfy Handy",
            type: "ntfy",
            ntfyserverurl: "https://ntfy.sh",
            ntfytopic: NTFY_TOPIC,
            ntfyPriority: 5,
            isDefault: true,
            applyExisting: true,
            active: true,
        }, null);
        if (!res.ok) fail("addNotification", res);
        notificationIDList = { [res.id]: true };
        console.log("ntfy Benachrichtigung angelegt, id", res.id);
    }

    const ids = [];
    for (const m of monitors) {
        const found = existing.find((e) => e.name === m.name);
        if (found) {
            console.log("existiert:", m.name);
            ids.push(found.id);
            continue;
        }
        const res = await call("add", { ...base, ...m, notificationIDList });
        if (!res.ok) fail(`add ${m.name}`, res);
        ids.push(res.monitorID);
        console.log("Monitor:", m.name, res.monitorID);
    }

    {
        const sp = await call("addStatusPage", "Homeserver", "homeserver");
        if (!sp.ok) console.log("Status Page:", sp.msg);
        const save = await call("saveStatusPage", "homeserver", {
            slug: "homeserver",
            title: "Homeserver",
            description: "Status aller Dienste",
            logo: "/icon.svg",
            theme: "dark",
            autoRefreshInterval: 300,
            showTags: false,
            showPoweredBy: false,
            showCertificateExpiry: false,
            footerText: "",
            customCSS: "",
            domainNameList: [],
            analyticsType: null,
            analyticsId: null,
            analyticsScriptUrl: null,
        }, "/icon.svg", [{ name: "Dienste", monitorList: ids.map((id) => ({ id })) }]);
        if (!save.ok) fail("saveStatusPage", save);
        console.log("Status Page homeserver gespeichert");
    }

    socket.close();
    process.exit(0);
});

socket.on("connect_error", (e) => fail("connect", { msg: e.message }));
