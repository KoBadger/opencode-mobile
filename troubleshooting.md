# Troubleshooting

Every entry here is a real failure that was hit while building this. Symptom →
cause → fix.

---

## The app says "server is not responding" but `curl` works

**Cause.** The Android app speaks the **OpenCode V1 HTTP API**. OpenCode **V2**
moved every route under `/api/` and removed `/global/health`. V1 paths now fall
through to the web UI's catch-all, which returns **HTML with status 200**. The
app tries to parse that HTML as JSON, throws, and marks the server unhealthy.

You can see it directly:

```bash
curl -u opencode:$PASS http://127.0.0.1:4096/global/health
# => <!doctype html> ...          <- HTML, not JSON
curl -u opencode:$PASS http://127.0.0.1:4097/global/health
# => {"healthy":true,...}         <- bridge, correct
```

**Fix.** Point the app at the **bridge port (4097)**, not the server port (4096).

---

## The "+" / Add Server dialog closes and the server never connects

**Cause.** Same V1/V2 mismatch as above. The server **is** saved — it just
immediately fails its health check and gets stuck at `isHealthy:false`.

You can confirm the save happened (the app is a debug build, so `run-as` works):

```bash
adb shell "run-as dev.minios.ocremote.debug cat \
  /data/data/dev.minios.ocremote.debug/files/datastore/opencode_prefs.preferences_pb" \
  | strings | grep -i '"url"'
```

**Fix.** As above — use the bridge port. No amount of retyping the URL fixes it.

---

## The URL field looks correct but validation fails

**Cause.** The Add Server dialog initialises the URL field to the literal string
`"http://"`. If you type without clearing it first you end up with
`http://http://...`, `validateAndNormalizeUrl()` returns null, and the confirm
handler silently does nothing.

**Fix.** Clear the field completely before typing, or type the host without a
scheme (`127.0.0.1:4097`) and let the app add `http://`.

---

## The bridge exits immediately with `Cannot find module '/root/v1v2-bridge.mjs'`

**Cause.** Inside `proot-distro`, `$HOME` is **`/root`** — *not* Termux's
`/data/data/com.termux/files/home`. Referencing a Termux path from inside the
container fails.

**Fix.** Copy the file **into** the container. The installer does this with
base64 over stdin, which avoids every proot path-mapping problem:

```bash
base64 -w0 v1v2-bridge.mjs | proot-distro login ubuntu -- \
  /bin/bash -c 'base64 -d > /root/v1v2-bridge.mjs && chmod +x /root/v1v2-bridge.mjs'
```

---

## `Cannot find module` on a path with spaces (Windows bridge)

**Cause.** `Start-Process -ArgumentList "C:\path with spaces\file.mjs"` splits the
argument.

**Fix.** Quote inside the array:

```powershell
Start-Process node -ArgumentList @("`"$script`"")
```

---

## `pgrep` / `netstat` say the server is NOT RUNNING, but it is

**Cause.** Termux cannot see processes inside proot — they live in a different
namespace. This is a **false negative**. It burns a lot of time if you trust it.

**Fix.** Always probe over HTTP instead:

```bash
curl -s -u opencode:$PASS -o /dev/null -w "HTTP:%{http_code}\n" \
  http://127.0.0.1:4096/api/info
```

---

## The server dies after a few minutes in the background

**Cause.** Android's **phantom process killer** SIGKILLs proot's child processes.
Samsung is especially aggressive about it.

**Fix.** Disable the killer (survives reboots):

```bash
adb shell settings put global settings_enable_monitor_phantom_procs false
```

Then set **Settings → Apps → Termux** and **Tailscale** to **Unrestricted**
battery. Verify both the battery whitelist and the killer setting:

```bash
adb shell dumpsys deviceidle whitelist | grep -i termux
adb shell settings get global settings_enable_monitor_phantom_procs   # want: false
```

---

## Tailscale keeps "turning off"

**Cause.** On **mobile data**, the phone tears down and re-establishes the
connection constantly, and the VPN service gets restarted with it. Right after a
restart the tunnel is briefly dead, so a connection attempt during that window
fails.

Diagnose — the service restart time is the giveaway:

```bash
adb shell dumpsys activity services com.tailscale.ipn | grep restartTime
```

**Fix.** In the Tailscale app → **Settings**, enable **Always-on VPN** (or
*Connect on demand → Always*). Android then restarts Tailscale the instant the
network returns instead of waiting for the app to notice. Connecting over Wi-Fi
also avoids it.

Note the phone-local setup (bridge on `127.0.0.1`) **does not need Tailscale at
all** — only the desktop connection does.

---

## Two Termux-based installers fighting each other

**Cause.** Some third-party installers (`crim50n/oc-remote`'s own "OpenCode
Local Runtime", for example) download **their own** Debian rootfs and create a
competing environment. Two runtimes on the same ports is guaranteed confusion.

**Fix.** Pick one. This repo uses `proot-distro ubuntu` at a fixed path. Do not
run another installer alongside it.

---

## Which port do I use?

| Port | What it is | Use with |
|---|---|---|
| **4096** | raw OpenCode **V2** server | browser UI, V2-native clients |
| **4097** | **V1↔V2 bridge** | the Android app |

Mixing these up is the single most common mistake.
