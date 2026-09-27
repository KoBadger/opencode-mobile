#!/usr/bin/env node
/**
 * OpenCode V1 <-> V2 translation bridge
 * ------------------------------------
 * OC Remote (and other V1-era clients) speak the OpenCode V1 HTTP API:
 *   GET /global/health, /global/event, /session, /config, /app, ...
 *
 * OpenCode V2 moved everything under /api/ and dropped /global/health:
 *   GET /api/info, /api/event, /api/session, /api/config, /api/provider, /api/model
 *
 * This proxy listens on PORT (default 4097) and forwards V1-style requests to a
 * V2 upstream (default http://127.0.0.1:4096), rewriting paths and adapting the
 * handful of responses whose shape changed.
 *
 * Usage:
 *   node v1v2-bridge.mjs
 *   PORT=4097 UPSTREAM=http://127.0.0.1:4096 \
 *   UPSTREAM_USERNAME=opencode UPSTREAM_PASSWORD=secret \
 *   BRIDGE_USERNAME=opencode BRIDGE_PASSWORD=secret \
 *   node v1v2-bridge.mjs
 */

import http from "node:http";
import { URL } from "node:url";

const PORT = Number(process.env.PORT || 4097);
const HOST = process.env.HOST || "0.0.0.0";
const UPSTREAM = (process.env.UPSTREAM || "http://127.0.0.1:4096").replace(/\/+$/, "");

// Auth used when talking to the V2 upstream server.
const UPSTREAM_USERNAME = process.env.UPSTREAM_USERNAME || "";
const UPSTREAM_PASSWORD = process.env.UPSTREAM_PASSWORD || "";

// Auth the bridge itself requires from clients (optional).
const BRIDGE_USERNAME = process.env.BRIDGE_USERNAME || "";
const BRIDGE_PASSWORD = process.env.BRIDGE_PASSWORD || "";

const VERBOSE = process.env.VERBOSE === "1";

function basic(user, pass) {
  if (!user && !pass) return null;
  return "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");
}

const UPSTREAM_AUTH = basic(UPSTREAM_USERNAME, UPSTREAM_PASSWORD);

function log(...args) {
  if (VERBOSE) console.log(new Date().toISOString(), ...args);
}

/**
 * Map a V1 request path to its V2 equivalent.
 *
 * V2 namespaces almost everything under /api/. A few V1 routes have no direct
 * V2 counterpart and are handled separately (see handleSynthetic).
 */
function mapPath(pathname) {
  // Already V2-shaped - pass straight through.
  if (pathname.startsWith("/api/")) return pathname;

  // V1-only routes we synthesize locally.
  if (pathname === "/global/health" || pathname === "/global/version") return null;

  // Everything else: prefix with /api/. /global/event -> /api/event,
  // /session -> /api/session, /config -> /api/config, etc.
  let mapped = "/api" + pathname;
  mapped = mapped.replace(/^\/api\/global\//, "/api/");

  // V1 used /config/providers; V2 exposes /api/provider.
  if (mapped === "/api/config/providers") mapped = "/api/provider";

  return mapped;
}

/** Read a request body fully. */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

/** Authorize an incoming client request against BRIDGE_USERNAME/PASSWORD. */
function clientAuthorized(req) {
  if (!BRIDGE_USERNAME && !BRIDGE_PASSWORD) return true;
  const header = req.headers["authorization"] || "";
  if (!header.startsWith("Basic ")) return false;
  let decoded;
  try {
    decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  } catch {
    return false;
  }
  const idx = decoded.indexOf(":");
  const user = decoded.slice(0, idx);
  const pass = decoded.slice(idx + 1);
  return user === BRIDGE_USERNAME && pass === BRIDGE_PASSWORD;
}

function sendJson(res, status, obj) {
  const body = Buffer.from(JSON.stringify(obj));
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": body.length,
  });
  res.end(body);
}

/**
 * Synthetic V1 routes.
 *
 * /global/health is the one that matters most: OC Remote calls it on connect and
 * treats a non-JSON or non-2xx reply as "server unhealthy". V2 has no equivalent,
 * so we build a V1 ServerHealth from /api/info.
 */
async function handleSynthetic(pathname, res) {
  if (pathname === "/global/health") {
    try {
      const upstream = await fetch(`${UPSTREAM}/api/info`, {
        headers: UPSTREAM_AUTH ? { authorization: UPSTREAM_AUTH } : {},
      });
      if (!upstream.ok) {
        return sendJson(res, 200, { healthy: false, version: null });
      }
      const info = await upstream.json().catch(() => ({}));
      return sendJson(res, 200, {
        healthy: true,
        version: info.version ?? null,
      });
    } catch (err) {
      log("health probe failed:", err.message);
      // Report unhealthy rather than erroring - clients render this gracefully.
      return sendJson(res, 200, { healthy: false, version: null });
    }
  }

  if (pathname === "/global/version") {
    try {
      const upstream = await fetch(`${UPSTREAM}/api/info`, {
        headers: UPSTREAM_AUTH ? { authorization: UPSTREAM_AUTH } : {},
      });
      const info = await upstream.json().catch(() => ({}));
      return sendJson(res, 200, { version: info.version ?? null });
    } catch {
      return sendJson(res, 200, { version: null });
    }
  }

  return sendJson(res, 404, { error: "not found" });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const pathname = url.pathname;
  const query = url.search;

  if (!clientAuthorized(req)) {
    res.writeHead(401, { "www-authenticate": 'Basic realm="opencode"' });
    return res.end("Unauthorized");
  }

  const mapped = mapPath(pathname);

  if (mapped === null) {
    log("V1", req.method, pathname, "-> synthetic");
    return handleSynthetic(pathname, res);
  }

  const target = `${UPSTREAM}${mapped}${query}`;
  log("V1", req.method, pathname, "-> V2", mapped);

  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) {
    if (["host", "connection", "content-length", "authorization"].includes(k)) continue;
    headers[k] = v;
  }
  if (UPSTREAM_AUTH) headers["authorization"] = UPSTREAM_AUTH;

  const hasBody = !["GET", "HEAD"].includes(req.method);
  const body = hasBody ? await readBody(req) : undefined;

  try {
    const upstream = await fetch(target, {
      method: req.method,
      headers,
      body,
      redirect: "manual",
      duplex: body ? "half" : undefined,
    });

    // Stream the response back verbatim, preserving SSE etc.
    const outHeaders = {};
    upstream.headers.forEach((value, key) => {
      if (["content-encoding", "transfer-encoding", "connection"].includes(key)) return;
      outHeaders[key] = value;
    });

    res.writeHead(upstream.status, outHeaders);

    if (!upstream.body) return res.end();

    const reader = upstream.body.getReader();
    const pump = async () => {
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          if (!res.write(Buffer.from(value))) {
            await new Promise((r) => res.once("drain", r));
          }
        }
      } catch (err) {
        log("stream error:", err.message);
      } finally {
        res.end();
      }
    };
    await pump();
  } catch (err) {
    log("upstream error:", err.message);
    if (!res.headersSent) {
      sendJson(res, 502, { error: "upstream unavailable", detail: err.message });
    } else {
      res.end();
    }
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[v1v2-bridge] listening on http://${HOST}:${PORT}`);
  console.log(`[v1v2-bridge] upstream          ${UPSTREAM}`);
  console.log(`[v1v2-bridge] upstream auth     ${UPSTREAM_AUTH ? "enabled" : "disabled"}`);
  console.log(`[v1v2-bridge] client auth       ${BRIDGE_USERNAME || BRIDGE_PASSWORD ? "enabled" : "disabled"}`);
  console.log(`[v1v2-bridge] try: curl -u USER:PASS http://127.0.0.1:${PORT}/global/health`);
});
