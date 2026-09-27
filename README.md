# OpenCode on Android — phone-local server + desktop, one bridge

Run OpenCode **directly on your phone** and use it from the
[OC Remote](https://github.com/crim50n/oc-remote) Android app — with an optional
connection to your desktop over Tailscale.

> **TL;DR**
> ```bash
> # In Termux on the phone:
> pkg install -y git && git clone <repo> ~/opencode-mobile
> bash ~/opencode-mobile/setup-phone.sh
> ```
> Then in the app add a server: **`http://127.0.0.1:4097`**, user `opencode`,
> password `Vaporwave1127!`.

---

## Why this repo exists

Getting OpenCode running on Android is a chain of non-obvious problems. Every
one of them is solved here, so you don't have to rediscover them:

| Problem | Why it happens | Solution |
|---|---|---|
| `npm i -g opencode-ai` refuses to install on Android | package.json declares `os: darwin/linux/win32` only | run OpenCode inside **proot-distro Ubuntu** |
| The Linux binary won't run natively in Termux | it's glibc-linked & non-PIE; Android is bionic | same — run it in the container |
| The Android app says **"server is not responding"** even though `curl` works | the app speaks the **V1 HTTP API** (`/global/health`); OpenCode **V2** moved everything to `/api/*` and dropped `/global/health` | the **V1↔V2 bridge** in this repo |
| The app's "Save" seems to do nothing | V1 health check can't parse V2's HTML catch-all response, so servers save as `isHealthy:false` | same bridge |
| Server dies in the background | Android's phantom-process killer SIGKILLs proot children | `settings put global settings_enable_monitor_phantom_procs false` |
| Bridge can't find its file | proot's `$HOME` is `/root`, not Termux's home | installer copies the bridge **into** the container |

---

## Architecture

```
┌─────────────────────────── Phone ────────────────────────────┐
│                                                              │
│  OC Remote app ──► 127.0.0.1:4097 ──► bridge ──► 127.0.0.1:4096 │
│                     (V1 API)         (this repo)  (V2 server) │
│                                                  inside proot │
│                                                      Ubuntu   │
└──────────────────────────────────────────────────────────────┘
                    ▲
                    │ Tailscale (optional)
                    │
        Desktop OpenCode V2 server  100.108.250.70:4096
```

Two servers, two clients:

| Port | What | Who uses it |
|---|---|---|
| **4096** | real OpenCode V2 server | phone web UI, V2-native clients |
| **4097** | **V1↔V2 bridge** | **OC Remote app** |

---

## Install (phone)

### 0. Prerequisites
- **Termux** and **Termux:Boot** from **F-Droid** (not the Play Store build)
- Set Termux + Tailscale to **Unrestricted** battery
- The phone app: [OC Remote](https://github.com/crim50n/oc-remote)

### 1. Get this repo onto the phone
```bash
pkg install -y git
git clone <repo-url> ~/opencode-mobile
cd ~/opencode-mobile
```

### 2. One-shot setup
```bash
bash setup-phone.sh
```

This does **everything**, in order:
1. installs `proot-distro` + Ubuntu (~200 MB, one time)
2. installs OpenCode V2 **inside** Ubuntu
3. copies your config in (`phone-setup/`)
4. writes the start scripts + boot hooks
5. starts the V2 server on **4096**
6. installs and starts the bridge on **4097**
7. prints a verification report

### 3. Point the app at it

| Field | Value |
|---|---|
| Server Name | `Phone` |
| **Server URL** | **`http://127.0.0.1:4097`** |
| Username | `opencode` |
| Password | `Vaporwave1127!` |

> ⚠️ Use **4097**, not 4096. 4096 is the raw V2 server; the app can't read it.
> If the app has an "Auto-connect on app launch" toggle, turn it **on**.

### 4. Verify
```bash
bash status.sh
```
Expect `/global/health` → `{"healthy":true,...}`.

---

## Daily use

```bash
bash status.sh          # what's running + health of both ports
bash start.sh           # start server (4096) + bridge (4097)
bash stop.sh            # stop both
bash restart.sh         # restart both
```

Boot persistence is automatic via `~/.termux/boot/opencode.sh`
(Termux:Boot runs it a few seconds after the device finishes booting).

### Connecting to the desktop too
Add a **second** server in the app pointing at your desktop's Tailscale IP:

| Field | Value |
|---|---|
| Server Name | `Desktop` |
| Server URL | `http://<desktop-tailscale-ip>:4096` |
| Username / Password | your desktop server credentials |

The desktop server runs the **same bridge** (see `install-bridge-desktop.*`), so
if that desktop is also V2, point the app at `:4097` there too.

---

## Files

| File | Purpose |
|---|---|
| `setup-phone.sh` | **one-shot installer** — run this |
| `start.sh` / `stop.sh` / `restart.sh` / `status.sh` | day-to-day control |
| `v1v2-bridge.mjs` | the V1↔V2 translation proxy (zero dependencies) |
| `install-bridge-phone.sh` | just the bridge, if the server is already set up |
| `install-bridge-desktop.ps1` | run the bridge on a Windows desktop |
| `phone-setup/` | config transferred into the container (`opencode.json`, `auth.json`) |
| `troubleshooting.md` | symptom → cause → fix, drawn from real failures |

---

## Manual bridge use (any platform)

The bridge is a single dependency-free Node script. Point `UPSTREAM` at any
OpenCode V2 server and it will serve the V1 API on `PORT`:

```bash
PORT=4097 \
UPSTREAM=http://127.0.0.1:4096 \
UPSTREAM_USERNAME=opencode UPSTREAM_PASSWORD=secret \
BRIDGE_USERNAME=opencode     BRIDGE_PASSWORD=secret \
node v1v2-bridge.mjs
```

Verify:
```bash
curl -u opencode:secret http://127.0.0.1:4097/global/health
# {"healthy":true,"version":"2.0.12"}
```

---

## Security note

Credentials in this repo are placeholders for a **private Tailscale network**.
Before exposing anything beyond your tailnet, change the passwords and treat
`phone-setup/auth.json` as a secret.

---

## License

MIT — do what you like.
