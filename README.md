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
> password `$PASS`.

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
- The phone app: **[OC Remote](https://github.com/crim50n/oc-remote)** —
  package `dev.minios.ocremote`
- Set Termux and Tailscale to **Unrestricted** battery

> **Which app?** There are several OpenCode Android clients with confusingly
> similar names and UIs. This repo was built and verified against **OC Remote**
> (`dev.minios.ocremote`). That's the one whose "Add Server" dialog and
> `Local Server` card are described here. If you install a different one, the
> bridge still works — but the menus won't match these instructions.

### 1. Get this repo onto the phone
```bash
pkg install -y git
git clone https://github.com/KoBadger/opencode-mobile ~/opencode-mobile
cd ~/opencode-mobile
```

### 2. One-shot setup
```bash
bash setup-phone.sh
```

### 2. Configure (optional but recommended)
```bash
cp config.env.example config.env
nano config.env      # set OPENCODE_PASS to your own value
```
Every script reads `config.env`, so this is the only place to change
credentials or ports. If you skip this, the server uses a well-known default
password — fine on a private tailnet, not fine on a shared network.

### 3. One-shot setup
```bash
bash setup-phone.sh
```

This does **everything**, in order:
1. installs `proot-distro` + Ubuntu (~200 MB, one time)
2. installs OpenCode V2 **inside** Ubuntu
3. copies your config into the container
4. writes the start scripts + boot hooks
5. starts the V2 server on **4096**
6. installs and starts the bridge on **4097**
7. prints a verification report

### 4. Point the app at it

| Field | Value |
|---|---|
| Server Name | `Phone` |
| **Server URL** | **`http://127.0.0.1:4097`** |
| Username | your `OPENCODE_USER` (default `opencode`) |
| Password | your `OPENCODE_PASS` |

> ⚠️ Use **4097**, not 4096. 4096 is the raw V2 server; the app can't read it.
> If the app has an "Auto-connect on app launch" toggle, turn it **on**.

### 5. Verify
```bash
bash status.sh
```
Expect the bridge to report `{"healthy":true,...}`.

---

## Daily use

```bash
bash status.sh          # what's running + health of both ports
bash start.sh           # start server (4096) + bridge (4097)
bash stop.sh            # stop both
bash restart.sh         # restart both
bash keep-alive.sh      # stop Android from killing the server (see below)
bash setup-phone.sh --uninstall   # remove everything
```

Boot persistence is automatic via `~/.termux/boot/opencode.sh`
(Termux:Boot runs it a few seconds after the device finishes booting).

### Keeping the server alive

Android kills long-running background processes three separate ways. `setup-phone.sh`
fixes none of them automatically, because two require ADB — so run this once:

```powershell
# on a PC, with wireless debugging enabled on the phone
.\keep-alive.ps1
```

```bash
# or from Termux, for the parts that don't need ADB
bash keep-alive.sh
```

| Mechanism | Why it matters | Fixed by |
|---|---|---|
| **phantom process killer** | SIGKILLs proot's children — the main culprit | `keep-alive.ps1` / `.sh` |
| battery optimisation | doze suspends Termux | ADB or manual |
| standby bucket | restricts background work | ADB |

Verify it worked: lock the phone, wait 10 minutes, then run `bash status.sh`.

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
| `setup-phone.sh` | **one-shot installer** — run this (`--uninstall` to remove it) |
| `config.env.example` | copy to `config.env` to set your password/ports |
| `lib.sh` | shared config loader (used by all scripts) |
| `start.sh` / `stop.sh` / `restart.sh` / `status.sh` | day-to-day control |
| `keep-alive.sh` / `keep-alive.ps1` | stop Android from killing the server |
| `uninstall.sh` | clean teardown |
| `v1v2-bridge.mjs` | the V1↔V2 translation proxy (zero dependencies) |
| `install-bridge-phone.sh` | just the bridge, if the server is already set up |
| `install-bridge-desktop.ps1` | run the bridge on a Windows desktop |
| `phone-setup/` | seed config (`opencode.json`) + `auth.json.example` |
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

- **`config.env`** holds your server password. It is gitignored — never commit it.
- **`~/.config/opencode/auth.json`** holds your provider API keys. It lives
  outside this repo, and `phone-setup/auth.json` is gitignored too.
- The default password in `config.env.example` is a placeholder. Change it
  before exposing the server beyond a private tailnet.
- The bridge forwards Basic auth upstream, so the phone server's password and
  the bridge's password are the same value by default. If you want them to
  differ, set `BRIDGE_USERNAME`/`BRIDGE_PASSWORD` separately when launching
  `v1v2-bridge.mjs` by hand.

---

## License

MIT — do what you like.
