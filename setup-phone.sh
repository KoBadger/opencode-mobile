#!/data/data/com.termux/files/usr/bin/bash
# ===========================================================================
#  OpenCode on Android - ONE-SHOT SETUP
#
#  Run in Termux:   bash setup-phone.sh
#
#  Installs and starts everything:
#    1. proot-distro + Ubuntu              (once, ~200MB)
#    2. OpenCode V2 inside the container
#    3. your config + auth
#    4. V2 server  -> port 4096
#    5. V1<->V2 bridge -> port 4097   (this is what the Android app needs)
#    6. boot hooks + verification
#
#  Safe to re-run: it detects what is already installed and skips it.
# ===========================================================================
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BOX="ubuntu"
BRIDGE_IN_CONTAINER="/root/v1v2-bridge.mjs"
SERVER_PORT=4096
BRIDGE_PORT=4097
USER_NAME="opencode"
PASS="Vaporwave1127!"

say() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
die() { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }

banner() {
  cat <<'EOF'
  ___                    ____          _        _   _
 / _ \ _ __   ___ _ __  / ___|___   __| | ___  | | | |
| | | | '_ \ / _ \ '_ \| |   / _ \ / _` |/ _ \ | |_| |
| |_| | |_) |  __/ | | | |__| (_) | (_| |  __/ |  _  |
 \___/| .__/ \___|_| |_|\____\___/ \__,_|\___| |_| |_|
      |_|        phone-local server + V1<->V2 bridge
EOF
}

# --------------------------------------------------------------------------
banner
say "0/7  Environment check"
command -v pkg >/dev/null 2>&1 || die "This must run inside Termux."
[ -f "$REPO_DIR/v1v2-bridge.mjs" ] || die "v1v2-bridge.mjs missing from $REPO_DIR"
echo "    repo:    $REPO_DIR"
echo "    android: $(getprop ro.build.version.release 2>/dev/null || echo '?')"

# --------------------------------------------------------------------------
say "1/7  Termux packages"
pkg update -y >/dev/null 2>&1 || true
for p in proot-distro curl; do
  if command -v "$p" >/dev/null 2>&1; then
    echo "    $p: already installed"
  else
    echo "    installing $p..."
    pkg install -y "$p" || die "could not install $p"
  fi
done

# --------------------------------------------------------------------------
say "2/7  Ubuntu container"
if proot-distro login "$BOX" -- /bin/true >/dev/null 2>&1; then
  echo "    $BOX: already installed"
else
  echo "    installing $BOX (this downloads ~200MB)..."
  proot-distro install "$BOX" || die "could not install $BOX"
fi

# --------------------------------------------------------------------------
say "3/7  OpenCode V2 inside the container"
if proot-distro login "$BOX" -- /bin/bash -c \
     'export PATH=$HOME/.opencode/bin:$PATH; command -v opencode >/dev/null' 2>/dev/null; then
  echo "    opencode: already installed"
else
  echo "    installing opencode..."
  proot-distro login "$BOX" -- /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt update -y >/dev/null 2>&1
    apt install -y curl ca-certificates >/dev/null 2>&1
    curl -fsSL https://opencode.ai/v2/install | bash
  ' || die "opencode install failed"
fi
proot-distro login "$BOX" -- /bin/bash -c \
  'export PATH=$HOME/.opencode/bin:$PATH; echo "    version: $(opencode --version 2>/dev/null || echo unknown)"'

# --------------------------------------------------------------------------
say "4/7  Config + auth into the container"
# Everything the container needs lives in its own /root, because proot cannot
# see Termux's home directory.
if [ -d "$REPO_DIR/phone-setup" ]; then
  for f in opencode.json auth.json; do
    src="$REPO_DIR/phone-setup/$f"
    [ -f "$src" ] || continue
    # base64 over stdin sidesteps every proot path-mapping problem.
    base64 -w0 "$src" | proot-distro login "$BOX" -- /bin/bash -c \
      "mkdir -p /root/.config/opencode && base64 -d > /root/.config/opencode/$f"
    echo "    installed ~/.config/opencode/$f"
  done
else
  warn "phone-setup/ not found - the container will use default providers."
  warn "Add your own ~/.config/opencode/opencode.json inside the container."
fi

# --------------------------------------------------------------------------
say "5/7  Bridge file into the container"
base64 -w0 "$REPO_DIR/v1v2-bridge.mjs" | proot-distro login "$BOX" -- /bin/bash -c \
  "base64 -d > $BRIDGE_IN_CONTAINER && chmod +x $BRIDGE_IN_CONTAINER && echo \"    wrote $BRIDGE_IN_CONTAINER (\$(wc -c < $BRIDGE_IN_CONTAINER) bytes)\""

# --------------------------------------------------------------------------
say "6/7  Start scripts + boot hooks"

# --- server (4096) ---
cat > "$HOME/start-phone-opencode.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock 2>/dev/null
pkill -9 -f proot 2>/dev/null
sleep 2
nohup proot-distro login $BOX -- /bin/bash -c \
  'export OPENCODE_SERVER_PASSWORD="$PASS"; export PATH=\$HOME/.opencode/bin:\$PATH; cd \$HOME; opencode serve --hostname 0.0.0.0 --port $SERVER_PORT --print-logs' \
  > \$HOME/server-phone.log 2>&1 &
EOS

# --- bridge (4097) ---
cat > "$HOME/start-phone-bridge.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "v1v2-bridge.mjs" 2>/dev/null
sleep 1
nohup proot-distro login $BOX -- /bin/bash -c \
  'PORT=$BRIDGE_PORT HOST=0.0.0.0 UPSTREAM=http://127.0.0.1:$SERVER_PORT \
   UPSTREAM_USERNAME=$USER_NAME UPSTREAM_PASSWORD="$PASS" \
   BRIDGE_USERNAME=$USER_NAME BRIDGE_PASSWORD="$PASS" \
   node $BRIDGE_IN_CONTAINER' \
  > \$HOME/bridge.log 2>&1 &
EOS

chmod +x "$HOME/start-phone-opencode.sh" "$HOME/start-phone-bridge.sh"
echo "    wrote ~/start-phone-opencode.sh"
echo "    wrote ~/start-phone-bridge.sh"

# --- boot hook ---
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/opencode.sh" <<'EOB'
#!/data/data/com.termux/files/usr/bin/bash
# Start the OpenCode V2 server and the V1<->V2 bridge after boot.
termux-wake-lock 2>/dev/null
sleep 25
bash "$HOME/start-phone-opencode.sh" 2>/dev/null
for _ in $(seq 1 20); do
  curl -fsS -m 3 -u opencode:Vaporwave1127! -o /dev/null \
    http://127.0.0.1:4096/api/info 2>/dev/null && break
  sleep 2
done
bash "$HOME/start-phone-bridge.sh" 2>/dev/null
EOB
chmod +x "$HOME/.termux/boot/opencode.sh"
echo "    wrote ~/.termux/boot/opencode.sh"

# --------------------------------------------------------------------------
say "7/7  Starting server + bridge"
bash "$HOME/start-phone-opencode.sh"
echo "    waiting for the V2 server..."
for _ in $(seq 1 25); do
  curl -fsS -m 3 -u "$USER_NAME:$PASS" -o /dev/null \
    "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null && break
  sleep 2
done

bash "$HOME/start-phone-bridge.sh"
sleep 6

# --------------------------------------------------------------------------
say "Verification"
echo -n "  V2 server  ($SERVER_PORT): "
curl -s -m 8 -u "$USER_NAME:$PASS" "http://127.0.0.1:$SERVER_PORT/api/info" || echo "(no response)"
echo
echo -n "  V1 bridge  ($BRIDGE_PORT): "
curl -s -m 8 -u "$USER_NAME:$PASS" "http://127.0.0.1:$BRIDGE_PORT/global/health" || echo "(no response)"
echo
echo
echo "  --- bridge.log ---"
tail -6 "$HOME/bridge.log" 2>/dev/null | sed 's/^/  /'

cat <<EOF

===========================================================================
 DONE

 In the OC Remote app, add a server:

   Server Name   Phone
   Server URL    http://127.0.0.1:$BRIDGE_PORT      <-- $BRIDGE_PORT, not $SERVER_PORT
   Username      $USER_NAME
   Password      $PASS

 The bridge must report {"healthy":true,...} above. If it does and the app
 still says "not responding", see troubleshooting.md.
===========================================================================
EOF
