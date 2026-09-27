# The OC Router — consolidated deployment state

This document merges everything learned across **two separate sessions** that
were unknowingly working the same problem:

| Session | What it was | Outcome |
|---|---|---|
| *Tailscale set up* (`ses_f5f7ae104ffe8HJbJgTDIr73TU`) | Diagnose "OpenCode desktop → Android over Tailscale stopped working" | **No fix** — probed the wrong ports |
| *V2 fork session* | Migrate the OC Remote app to speak OpenCode V2 natively | Working, but a parallel approach to this repo |

The duplication is the problem. This file is the single source of truth.

---

## 1. The one idea

OpenCode **V2** moved its whole HTTP API to `/api/*` and dropped `/global/health`.
The Android apps (OC Remote, `dev.minios.ocremote`) speak the **V1** API. That
version gap is the entire cause of "fail to load sessions" / "server is not
responding".

This repo solves it with **`v1v2-bridge.mjs`** — a dependency-free proxy that
serves the V1 API and forwards to a V2 upstream. Two valid clients therefore
exist; they must not both run:

| Approach | Status |
|---|---|
| **V1↔V2 bridge (this repo)** — stock app unchanged | **Canonical** |
| V2-native app fork (`oc-remote` branch `v2-support`) | Experimental alternative — needs a custom APK on every device |

---

## 2. Ports (the thing the earlier session got wrong)

The failed session tested **9910, 9911, 9912, 8080, 3000** — none of which are
OpenCode. The real ports are:

| Port | What | Who connects |
|---|---|---|
| **4096** | real OpenCode **V2** server | browsers, V2-native clients |
| **4097** | **V1↔V2 bridge** | **the Android app** |
| 49374 | *(this desktop only)* the OpenCode **Desktop 2.0.18** background service | its own bundled V2 clients |

> Do **not** point the app at 4096 when the upstream is V2 — use the bridge on 4097.
> On this desktop the V2 service is on **49374**, so the bridge upstream is `http://127.0.0.1:49374`.

---

## 3. Credentials — unify to one

| Where | User | Password | Source |
|---|---|---|---|
| Bridge / phone (target) | `opencode` | `Vaporwave1127!` | `config.env` → `OPENCODE_PASS` |
| Phone server (today) | `opencode` | `Vaporwave1127!` | app launch-options field |
| Desktop V2 service (today) | `opencode` | `Vaporwave1127!` | `C:\Users\joshv\.config\opencode\service.json` (backup: `service.json.bak-ocrouter`) |
| Legacy logon task `OpenCodeServe` | `KoBadger` | `Vaporwave1127!` | `start-opencode-serve.ps1` |

**Remedy:** set `config.env` and make the bridge/desktop upstream use the same
value. The bridge **forwards Basic auth upstream**, so one password covers both
hops (see `config.env.example`).

---

## 4. Tailscale inventory

| Node | Tailscale IP | OS | Notes |
|---|---|---|---|
| `vaporzr-bot` | `100.108.250.70` | Windows | this desktop; V2 server host |
| `joshs-s23-ultra` | `100.111.9.102` | Android | the phone (was `192.168.1.51`, now `192.168.1.62`) |
| `vaporzr3-1` | `100.108.250.46` | Linux | present |
| `vaporzr3` | `100.100.191.18` | Linux | **offline 13 days** — safe to remove from the tailnet |

Funnel is **on** for `vaporzr-bot.tail137f17.ts.net` (`:8443`, `:10000`, root) —
that is publicly reachable. Never expose an OpenCode server through Funnel
without auth.

---

## 5. Known gotchas (learned the hard way)

1. **Wrong ports** were the whole reason the first session failed — see §2.
2. **`/global/health` is anonymous on V1** — a 200 there does **not** mean the
   server is unauthenticated. Test a real endpoint (`/session`) before calling it "open".
3. **`content-length` framing** — the bridge must drop `content-length`/
   `transfer-encoding` when replaying a decoded body, or the app reports
   *"Unexpected status line"* / *"Unexpected JSON token at $[1].name"*.
4. **Two phone setups exist** and must be reconciled:
   - `~/opencode-local` (from `crim50n/oc-remote` scripts) — what runs today; V1 `1.17.9` on `:4096`, auth enforced.
   - `the-oc-remoter` `setup-phone.sh` — V2 + bridge in proot Ubuntu (port 4096+4097).
5. **`the-oc-remoter` uses no `config.env` yet** — only the example exists, so the
   default password applies unless one is created.
6. **Android kills proot children** — run `keep-alive.ps1` (ADB) / `keep-alive.sh`.
7. **Folder rename blocked** — `the-oc-remoter` → `the-oc-router` fails with
   "used by another process" (OneDrive sync and/or a running process). Close
   OpenCode/OneDrive sync, or rename from a plain Explorer window.

---

## 6. Bring-up (target end state)

```powershell
# Desktop: run the bridge against the Desktop V2 service
$env:UPSTREAM="http://127.0.0.1:49374"; $env:PORT="4097"
$env:UPSTREAM_USERNAME="opencode"; $env:UPSTREAM_PASSWORD="<password>"
$env:BRIDGE_USERNAME="opencode";  $env:BRIDGE_PASSWORD="<password>"
node .\v1v2-bridge.mjs
```

```bash
# Phone (Termux): V2 server + bridge
cp config.env.example config.env   # set OPENCODE_PASS
bash setup-phone.sh
bash status.sh                     # expect {"healthy":true,...}
```

App entries (final):

| Name | URL | User / Pass |
|---|---|---|
| `Phone` | `http://127.0.0.1:4097` | `opencode` / your `config.env` value |
| `Desktop` | `http://100.108.250.70:4097` | `opencode` / your `config.env` value |

Remove the redundant entries (`Home PC` V1 `:4096`, `PC V2` `:49374`) — the app
does not need to know about raw V2 ports.

---

## 7. Naming

The repo's last commit renames it **to** "The OC Remoter", but the intended
project name is **The OC Router**. Pending: rename the local folder, the README
title, and `github.com/KoBadger/the-oc-remoter` together (GitHub repo rename
needs a token with `repo` scope).
