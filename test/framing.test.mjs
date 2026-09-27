// Regression test for response framing.
//
// Symptom this guards against, as seen in the OC Remote app:
//
//   Unexpected status line: 9q0fMP1h8wn7JyIlfFPelpmbwWuBtY5G4...
//   Illegal input: Unexpected JSON token at offset 281: Expected quotation
//     mark '"', but had ':' instead at path: $[1].name
//
// Cause: the bridge replayed the upstream's content-length while streaming
// fetch's DECODED body. For chunked or compressed upstreams those lengths
// disagree, so the client read the wrong number of bytes and started its next
// read mid-payload.
//
// Run:  node test/framing.test.mjs
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import http from "node:http";

const BRIDGE = path.join(import.meta.dirname, "..", "v1v2-bridge.mjs");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "framing-"));

const ICON = "data:image/jpeg;base64," + "9j/4AAQSkZJRg".repeat(4000);
const AGENTS = [
  { name: "build", icon: { override: ICON } },
  { name: "plan", icon: { override: ICON } },
  { name: "general", icon: { override: ICON } },
];
const EXPECTED = Buffer.byteLength(JSON.stringify(AGENTS));

// Upstream answers the big route with CHUNKED encoding and no content-length,
// which is how a large payload often arrives in practice.
const fakeV2 = path.join(tmp, "fake-v2.mjs");
fs.writeFileSync(fakeV2, `
import http from "node:http";
const ICON = ${JSON.stringify(ICON)};
const AGENTS = [
  { name: "build", icon: { override: ICON } },
  { name: "plan", icon: { override: ICON } },
  { name: "general", icon: { override: ICON } },
];
http.createServer((req, res) => {
  if (req.url === "/api/info") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ version: "2.0.12", pid: 1, urls: [] }));
  }
  if (req.url === "/api/agent") {
    res.writeHead(200, { "content-type": "application/json" });
    const body = JSON.stringify(AGENTS);
    res.write(body.slice(0, 100));
    res.write(body.slice(100));
    return res.end();
  }
  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
}).listen(4096, "127.0.0.1");
`);

const procs = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function start(file, env) {
  procs.push(spawn(process.execPath, [file], {
    env: { ...process.env, ...env },
    stdio: "ignore",
  }));
}

let failures = 0;
function check(name, cond, extra = "") {
  console.log((cond ? "  PASS  " : "  FAIL  ") + name + (cond ? "" : "  " + String(extra).slice(0, 200)));
  if (!cond) failures++;
}

const AUTH = "Basic " + Buffer.from("opencode:secret").toString("base64");

function get(port, urlPath, agent) {
  return new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port, path: urlPath, method: "GET", agent,
               headers: { authorization: AUTH } }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    }).on("error", reject);
  });
}

try {
  start(fakeV2, {});
  await sleep(1200);
  start(BRIDGE, {
    PORT: "4097", HOST: "127.0.0.1", UPSTREAM: "http://127.0.0.1:4096",
    BRIDGE_USERNAME: "opencode", BRIDGE_PASSWORD: "secret",
  });
  await sleep(1500);

  console.log("oversized JSON payload (chunked upstream)");
  const r = await get(4097, "/agent");
  check("status 200", r.status === 200, r.status);
  check("content-length not forwarded", r.headers["content-length"] === undefined,
    "content-length=" + r.headers["content-length"]);
  check("framed as chunked", (r.headers["transfer-encoding"] || "").includes("chunked"),
    r.headers["transfer-encoding"]);
  check("body length exact", r.body.length === EXPECTED, `${r.body.length} != ${EXPECTED}`);

  let parsed = null, err = null;
  try { parsed = JSON.parse(r.body.toString("utf8")); } catch (e) { err = e.message; }
  check("body parses as JSON", parsed !== null, err);
  if (parsed) {
    check("3 entries", parsed.length === 3, parsed.length);
    check("$[1].name is a string", typeof parsed[1].name === "string", typeof parsed[1].name);
    check("icons intact", parsed.every((a) => a.icon.override === ICON));
  }

  // A framing bug corrupts the SECOND response on a reused connection.
  console.log("two requests on one keep-alive connection");
  const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
  try {
    const a = await get(4097, "/agent", agent);
    const b = await get(4097, "/agent", agent);
    let ok = true, why = "";
    for (const [i, res] of [a, b].entries()) {
      try { if (JSON.parse(res.body.toString("utf8")).length !== 3) { ok = false; why = `req${i} wrong size`; } }
      catch (e) { ok = false; why = `req${i} parse error: ${e.message}`; }
    }
    check("both reuse responses intact", ok, why);
  } finally {
    agent.destroy();
  }
} catch (e) {
  console.log("  FAIL  exception: " + e.message);
  failures++;
} finally {
  for (const p of procs) { try { p.kill("SIGKILL"); } catch {} }
  await sleep(300);
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(failures === 0 ? "\nok - framing intact" : `\n${failures} check(s) failed`);
process.exit(failures ? 1 : 0);
