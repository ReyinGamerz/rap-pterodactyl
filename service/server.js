"use strict";
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const HOST = process.env.RAPELZ_BACKUP_API_HOST || "127.0.0.1";
const PORT = Number(process.env.RAPELZ_BACKUP_API_PORT || "8787");
const TOKEN = process.env.RAPELZ_BACKUP_API_TOKEN || "";
const CATALOG = process.env.RAPELZ_BACKUP_CATALOG || "/var/lib/rapelz-backup-service/catalog.json";
const ALLOWED_ORIGIN = process.env.RAPELZ_BACKUP_ALLOWED_ORIGIN || "";
const MAX_PER_PAGE = 100;

function send(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer"
  });
  res.end(body);
}
function constantTimeEqual(a, b) {
  const aa = Buffer.from(a);
  const bb = Buffer.from(b);
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb);
}
function readCatalog() {
  const raw = fs.readFileSync(CATALOG, "utf8");
  const parsed = JSON.parse(raw);
  if (!parsed || parsed.schema_version !== 1 || !Array.isArray(parsed.backups) || !Array.isArray(parsed.nodes)) {
    throw new Error("Catalog schema invalid");
  }
  return parsed;
}
function safeText(v, max = 160) {
  return typeof v === "string" ? v.slice(0, max) : "";
}
function validDate(v) {
  return !v || /^\d{4}-\d{2}-\d{2}$/.test(v);
}
function sanitizeBackup(b) {
  return {
    id: safeText(b.id, 120),
    source_kind: safeText(b.source_kind, 32),
    source_id: safeText(b.source_id, 80),
    node_id: safeText(b.node_id, 80),
    node_name: safeText(b.node_name, 120),
    server_uuid: safeText(b.server_uuid, 80),
    name: safeText(b.name, 180),
    created_at_utc: safeText(b.created_at_utc, 40),
    size_bytes: Number.isSafeInteger(b.size_bytes) && b.size_bytes >= 0 ? b.size_bytes : 0,
    status: ["succeeded", "failed", "running", "verifying", "queued", "unverified"].includes(b.status) ? b.status : "unverified",
    verified: b.verified === true,
    sha256: /^[a-f0-9]{64}$/i.test(b.sha256 || "") ? b.sha256 : null,
    manifest_key: safeText(b.manifest_key, 300)
  };
}
const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS") {
    if (ALLOWED_ORIGIN && req.headers.origin === ALLOWED_ORIGIN) {
      res.writeHead(204, { "access-control-allow-origin": ALLOWED_ORIGIN, "access-control-allow-methods": "GET, OPTIONS", "access-control-allow-headers": "authorization, content-type", "vary": "Origin" });
      return res.end();
    }
    return send(res, 403, { error: "origin_not_allowed" });
  }
  if (ALLOWED_ORIGIN && req.headers.origin && req.headers.origin !== ALLOWED_ORIGIN) return send(res, 403, { error: "origin_not_allowed" });
  if (!TOKEN || TOKEN.length < 32) return send(res, 503, { error: "service_not_configured" });
  const header = req.headers.authorization || "";
  const supplied = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!supplied || !constantTimeEqual(supplied, TOKEN)) return send(res, 401, { error: "unauthorized" });
  if (req.method !== "GET") return send(res, 405, { error: "method_not_allowed" });

  let url;
  try { url = new URL(req.url, "http://127.0.0.1"); } catch { return send(res, 400, { error: "invalid_url" }); }
  if (url.pathname === "/health") return send(res, 200, { status: "ok", mode: "read-only-catalog", timestamp: new Date().toISOString() });
  let catalog;
  try { catalog = readCatalog(); } catch { return send(res, 503, { error: "catalog_unavailable" }); }
  if (url.pathname === "/v1/nodes") {
    const nodes = catalog.nodes.map(n => ({
      id: safeText(n.id, 80), pterodactyl_node_id: Number.isSafeInteger(n.pterodactyl_node_id) ? n.pterodactyl_node_id : null,
      name: safeText(n.name, 120), hostname: safeText(n.hostname, 180),
      enabled: n.enabled === true, last_seen_at: safeText(n.last_seen_at, 40), status: ["online", "offline", "unknown"].includes(n.status) ? n.status : "unknown"
    }));
    return send(res, 200, { data: nodes, total: nodes.length });
  }
  if (url.pathname === "/v1/backups") {
    const node = safeText(url.searchParams.get("node_id"), 80);
    const kind = safeText(url.searchParams.get("kind"), 32);
    const status = safeText(url.searchParams.get("status"), 32);
    const q = safeText(url.searchParams.get("q"), 120).toLowerCase();
    const from = url.searchParams.get("from") || "";
    const to = url.searchParams.get("to") || "";
    if (!validDate(from) || !validDate(to)) return send(res, 400, { error: "invalid_date_filter" });
    const page = Math.max(1, Number.parseInt(url.searchParams.get("page") || "1", 10) || 1);
    const perPage = Math.min(MAX_PER_PAGE, Math.max(1, Number.parseInt(url.searchParams.get("per_page") || "25", 10) || 25));
    let all = catalog.backups.map(sanitizeBackup).filter(b =>
      (!node || node === "all" || b.node_id === node || (node === "panel" && b.source_kind === "panel")) &&
      (!kind || kind === "all" || b.source_kind === kind) &&
      (!status || status === "all" || b.status === status) &&
      (!from || b.created_at_utc.slice(0, 10) >= from) &&
      (!to || b.created_at_utc.slice(0, 10) <= to) &&
      (!q || [b.id,b.source_id,b.node_name,b.server_uuid,b.name,b.source_kind].some(v => v.toLowerCase().includes(q)))
    );
    all.sort((a,b) => b.created_at_utc.localeCompare(a.created_at_utc));
    const total = all.length;
    const data = all.slice((page - 1) * perPage, page * perPage);
    return send(res, 200, { data, pagination: { page, per_page: perPage, total, pages: Math.ceil(total / perPage) } });
  }
  const match = url.pathname.match(/^\/v1\/backups\/([a-zA-Z0-9._-]{1,120})$/);
  if (match) {
    const found = catalog.backups.find(b => b.id === match[1]);
    if (!found) return send(res, 404, { error: "backup_not_found" });
    return send(res, 200, { data: sanitizeBackup(found) });
  }
  return send(res, 404, { error: "not_found" });
});
server.listen(PORT, HOST, () => process.stdout.write("Rapelz read-only backup catalogue listening on " + HOST + ":" + PORT + "\n"));
