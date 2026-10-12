// Static server for local preview + PostgreSQL pick-sync API.
// Usage:  node server.js   →   http://localhost:3000
//
// The browser app keeps picks in localStorage (instant, offline) and
// mirrors them to the `picks` table via /api/picks so they survive
// cleared browser data. If PostgreSQL is unreachable the site still
// works — the API just reports 503 and the app stays on localStorage.
//
// Connection settings come from the standard PG* environment variables
// and default to the local peer-authenticated socket:
//   PGHOST=/var/run/postgresql  PGPORT=5432
//   PGDATABASE=digital_toolkit  PGUSER=<your OS user>
// On a remote server set e.g. PGHOST=db.example.com PGUSER=... PGPASSWORD=...
const http = require("http");
const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

const PORT = process.env.PORT || 3000;
const ROOT = __dirname;
const PROFILE_ID = process.env.PROFILE_ID || "default";

const dbConfig = {
  host: process.env.PGHOST || "/var/run/postgresql",
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || "digital_toolkit",
  user: process.env.PGUSER || process.env.USER || "zetnovs",
  password: process.env.PGPASSWORD || undefined,
  max: 5,
  idleTimeoutMillis: 30000,
};

const pool = new Pool(dbConfig);
pool.on("error", (err) => console.error("⚠️  PostgreSQL pool error:", err.message));

/* Quote a PG identifier for the few statements that can't take parameters. */
const quoteIdent = (s) => `"${String(s).replace(/"/g, '""')}"`;

/* Create the database if it doesn't exist (must connect to 'postgres' first). */
async function ensureDatabase() {
  const admin = new Pool({ ...dbConfig, database: "postgres" });
  try {
    const { rows } = await admin.query(
      "SELECT 1 FROM pg_database WHERE datname = $1", [dbConfig.database]
    );
    if (!rows.length) {
      await admin.query(`CREATE DATABASE ${quoteIdent(dbConfig.database)}`);
      console.log(`📁 Created database ${dbConfig.database}`);
    }
  } finally {
    await admin.end();
  }
}

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS picks (
      profile_id   TEXT PRIMARY KEY,
      os_list      JSONB NOT NULL DEFAULT '[]'::jsonb,
      browser_list JSONB NOT NULL DEFAULT '[]'::jsonb,
      updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

/* Basic shape validation for posted picks. Returns { osList, browserList } or null. */
function sanitizePicks(body) {
  if (!body || typeof body !== "object") return null;
  const clean = (v) =>
    Array.isArray(v) &&
    v.length <= 24 &&
    v.every((x) => typeof x === "string" && x.length > 0 && x.length <= 64);
  const osList = body.osList, browserList = body.browserList;
  if (!clean(osList) || !clean(browserList)) return null;
  return { osList: [...new Set(osList)], browserList: [...new Set(browserList)] };
}

function readBody(req, limit = 16 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) { reject(new Error("body too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function json(res, status, obj) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  res.end(JSON.stringify(obj));
}

/* ---------- Picks API ---------- */
async function handleApi(req, res, urlPath) {
  try {
    if (urlPath === "/api/picks" && req.method === "GET") {
      const { rows } = await pool.query(
        "SELECT os_list, browser_list, updated_at FROM picks WHERE profile_id = $1", [PROFILE_ID]
      );
      if (!rows.length) return json(res, 200, { ok: true, picks: null });
      const r = rows[0];
      return json(res, 200, {
        ok: true,
        picks: { osList: r.os_list, browserList: r.browser_list, updatedAt: r.updated_at }
      });
    }

    if (urlPath === "/api/picks" && req.method === "POST") {
      const picks = sanitizePicks(JSON.parse((await readBody(req)) || "null"));
      if (!picks) return json(res, 400, { ok: false, error: "osList/browserList must be small string arrays" });
      const { rows } = await pool.query(
        `INSERT INTO picks (profile_id, os_list, browser_list, updated_at)
         VALUES ($1, $2::jsonb, $3::jsonb, now())
         ON CONFLICT (profile_id) DO UPDATE
           SET os_list = EXCLUDED.os_list,
               browser_list = EXCLUDED.browser_list,
               updated_at = now()
         RETURNING os_list, browser_list, updated_at`,
        [PROFILE_ID, JSON.stringify(picks.osList), JSON.stringify(picks.browserList)]
      );
      const r = rows[0];
      return json(res, 200, {
        ok: true,
        picks: { osList: r.os_list, browserList: r.browser_list, updatedAt: r.updated_at }
      });
    }

    return json(res, 404, { ok: false, error: "unknown API route" });
  } catch (err) {
    console.error("⚠️  API error:", err.message);
    return json(res, 503, { ok: false, error: "database unavailable" });
  }
}

/* ---------- Static files ---------- */
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js":   "text/javascript; charset=utf-8",
  ".css":  "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg":  "image/svg+xml",
  ".png":  "image/png",
  ".jpg":  "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".gif":  "image/gif",
  ".ico":  "image/x-icon",
  ".txt":  "text/plain; charset=utf-8"
};

function serveStatic(req, res, urlPath) {
  let filePath = path.join(ROOT, urlPath);
  // Prevent path traversal outside ROOT
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403).end("Forbidden");
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { "Content-Type": "text/plain" }).end("404 Not Found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split("?")[0]);
  if (urlPath === "/") urlPath = "/index.html";
  if (urlPath.startsWith("/api/")) return handleApi(req, res, urlPath);
  return serveStatic(req, res, urlPath);
});

server.listen(PORT, async () => {
  console.log(`✅ Digital Toolkit running at http://localhost:${PORT}`);
  try {
    await ensureDatabase();
    await ensureSchema();
    const { rows } = await pool.query("SELECT version()");
    console.log(`🐘 PostgreSQL connected — ${rows[0].version.split(",")[0]}`);
    console.log(`   database: ${dbConfig.database} · profile: ${PROFILE_ID}`);
  } catch (err) {
    console.error(`⚠️  PostgreSQL not available (${err.message})`);
    console.error("   The site still works; picks will only be kept in localStorage.");
  }
});
