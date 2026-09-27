// Regression test for the V1 -> V2 API translation.
//
// OC Remote speaks the OpenCode V1 HTTP API. OpenCode V2 moved everything under
// /api/ and dropped /global/health, so V1 paths fall through to the web UI
// catch-all and return HTML with status 200. The app tries to parse that HTML
// as JSON, fails, and marks the server unhealthy - which reads in the UI as
// "server is not responding".
//
// Run:  node test/bridge.test.mjs
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const BRIDGE = path.join(import.meta.dirname, "..", "v1v2-bridge.mjs");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "bridge-"));

const fakeV2 = path.join(tmp, "fake-v2.mjs");
fs.writeFileSync(fakeV2, `
import http from "node:http";
http.createServer((req, res) => {
  if (req.url === "/api/info") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ version: "2.0.12", pid: 1, urls: [] }));
  }
  if (req.url === "/api/session") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ data: [] }));
  }
  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
}).listen(4096, "127.0.0.1");
`);

const procs = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function start(file, env) {
  procs.push(spawn(process.execPath, [file], { env: { ...process.env, ...env }, stdio: "ignore" }));
}

let failures = 0;
function check(name, cond, extra = "") {
  console.log((cond ? "  PASS  " : "  FAIL  ") + name + (cond ? "" : "  " + String(extra).slice(0, 200)));
  if (!cond) failures++;
}

const auth = (u, p) => "Basic " + Buffer.from(`${u}:${p}`).toString("base64");

try {
  start(fakeV2, {});
  await sleep(1200);
  start(BRIDGE, {
    PORT: "4097", HOST: "127.0.0.1", UPSTREAM: "http://127.0.0.1:4096",
    BRIDGE_USERNAME: "opencode", BRIDGE_PASSWORD: "secret",
  });
  await sleep(1500);

  console.log("V1 API surface");
  const h = await fetch("http://127.0.0.1:4097/global/health",
    { headers: { authorization: auth("opencode", "secret") } });
  const hb = await h.text();
  check("health 200", h.status === 200, h.status);
  check("health is JSON", (h.headers.get("content-type") || "").includes("json"));
  check("health says healthy:true", hb.includes('"healthy":true'), hb);
  check("health carries version", hb.includes('"version":"2.0.12"'), hb);

  console.log("path rewriting");
  const s = await fetch("http://127.0.0.1:4097/session",
    { headers: { authorization: auth("opencode", "secret") } });
  check("session passes through", s.status === 200, s.status);

  const v = await fetch("http://127.0.0.1:4097/global/version",
    { headers: { authorization: auth("opencode", "secret") } });
  check("version route", v.status === 200 && (await v.text()).includes("2.0.12"));

  console.log("auth");
  check("no credentials -> 401", (await fetch("http://127.0.0.1:4097/global/health")).status === 401);
  check("wrong password -> 401",
    (await fetch("http://127.0.0.1:4097/global/health",
      { headers: { authorization: auth("opencode", "wrong") } })).status === 401);

  console.log("unknown routes");
  check("unknown -> 404",
    (await fetch("http://127.0.0.1:4097/does-not-exist",
      { headers: { authorization: auth("opencode", "secret") } })).status === 404);
} catch (e) {
  console.log("  FAIL  exception: " + e.message);
  failures++;
} finally {
  for (const p of procs) { try { p.kill("SIGKILL"); } catch {} }
  await sleep(300);
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(failures === 0 ? "\nok - bridge translates V1 <-> V2" : `\n${failures} check(s) failed`);
process.exit(failures ? 1 : 0);
