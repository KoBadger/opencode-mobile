#!/data/data/com.termux/files/usr/bin/bash
# ===========================================================================
#  Keep the OpenCode server alive - background-kill hardening
#
#  Run in Termux:   bash keep-alive.sh
#
#  Android aggressively SIGKILLs long-running background processes, and
#  Samsung is worse than most. Three separate mechanisms are involved; this
#  script addresses every one it can reach:
#
#    1. phantom process killer  -> kills proot's CHILD processes
#    2. battery optimisation    -> doze suspends the app
#    3. standby bucket          -> restricts background work
#
#  Some of these need elevated access (adb or root). The script detects what
#  is available and does as much as it can, then tells you exactly what it
#  could not do and how to finish it.
#
#  If you have wireless debugging on, run this on a COMPUTER instead:
#     bash keep-alive.sh --adb <phone-ip>:<port>
# ===========================================================================
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$REPO_DIR/lib.sh"

say()  { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
ok()   { printf "    \033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "    \033[1;33m[!]\033[0m %s\n" "$*"; }
bad()  { printf "    \033[1;31m[x]\033[0m %s\n" "$*"; }

# --------------------------------------------------------------------------
# Which mode? If adb is available (on this machine, or a remote one we can
# reach), prefer it - it can change settings Termux cannot.
ADB=""
if command -v adb >/dev/null 2>&1; then
  ADB="adb"
elif command -v "$PREFIX/bin/adb" >/dev/null 2>&1; then
  ADB="$PREFIX/bin/adb"
fi

if [ "${1:-}" = "--adb" ] && [ -n "${2:-}" ]; then
  ADB="adb"
  say "Connecting to $2"
  adb connect "$2" >/dev/null 2>&1 || true
fi

run_setting() { # key value  -> works in whichever mode we have
  local key="$1" val="$2" got
  if [ -n "$ADB" ]; then
    $ADB shell "settings put global $key $val" >/dev/null 2>&1 || return 1
    got=$($ADB shell "settings get global $key" 2>/dev/null | tr -d '\r')
  else
    # Termux can sometimes still write global settings for its own uid.
    settings put global "$key" "$val" >/dev/null 2>&1 || return 1
    got=$(settings get global "$key" 2>/dev/null | tr -d '\r')
  fi
  [ "$got" = "$val" ]
}

say "Environment"
if [ -n "$ADB" ]; then
  if $ADB get-state >/dev/null 2>&1; then
    ok "adb connected: $($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  else
    ADB=""
    warn "adb present but no device connected - falling back to Termux-only"
  fi
fi
[ -n "$ADB" ] || warn "no adb - Termux-only mode (some fixes will need manual steps)"

# --------------------------------------------------------------------------
say "1/3  Phantom process killer"
# This is the one that actually kills proot children. Android 12+ only.
if run_setting settings_enable_monitor_phantom_procs false; then
  ok "phantom process killer DISABLED"
else
  bad "could not change it"
  warn "do this once from a computer with wireless debugging on:"
  warn "  adb shell settings put global settings_enable_monitor_phantom_procs false"
fi

# --------------------------------------------------------------------------
say "2/3  Battery optimisation"
pkg_whitelisted() {
  local pkg="$1"
  if [ -n "$ADB" ]; then
    $ADB shell dumpsys deviceidle whitelist 2>/dev/null | grep -q "$pkg"
  else
    return 1  # cannot read this without elevation
  fi
}

for pkg in com.termux com.termux.boot com.tailscale.ipn; do
  if pkg_whitelisted "$pkg"; then
    ok "$pkg already unrestricted"
  elif [ -n "$ADB" ]; then
    $ADB shell "cmd deviceidle whitelist +$pkg" >/dev/null 2>&1 \
      && ok "$pkg added to whitelist" \
      || warn "$pkg could not be whitelisted"
  else
    warn "$pkg - set to Unrestricted manually (Settings > Apps > $pkg > Battery)"
  fi
done

# --------------------------------------------------------------------------
say "3/3  Standby bucket"
if [ -n "$ADB" ]; then
  for pkg in com.termux com.tailscale.ipn; do
    $ADB shell "am set-standby-bucket $pkg active" >/dev/null 2>&1
    bucket=$($ADB shell "am get-standby-bucket $pkg" 2>/dev/null | tr -d '\r')
    if [ "$bucket" = "5" ]; then
      ok "$pkg is ACTIVE (bucket 5)"
    else
      warn "$pkg bucket is $bucket (want 5)"
    fi
  done
else
  warn "needs adb - skip"
fi

# --------------------------------------------------------------------------
say "Summary"
cat <<EOF

  The phantom-process killer is the one that was killing the OpenCode
  server after a few minutes. Verify at any time with:

    adb shell settings get global settings_enable_monitor_phantom_procs   # want: false

  Then confirm the server survives a lock-screen test:

    bash "$REPO_DIR/status.sh"
    # lock the phone, wait 10 minutes, run status.sh again

  Server URL for the app:  http://127.0.0.1:$BRIDGE_PORT
EOF
