#!/data/data/com.termux/files/usr/bin/bash
# ===========================================================================
#  Bridge-only installer
#
#  Use this when the OpenCode V2 server is ALREADY running on 4096 and you only
#  need the V1<->V2 bridge on 4097 (for the OC Remote app).
#
#  If you have not set anything up yet, run setup-phone.sh instead - it does
#  this and everything else.
#
#  Run in Termux:   bash install-bridge-phone.sh
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
die() { printf "\033[1;31m[x] %s\033[0m\n" "$*"; exit 1; }

[ -f "$REPO_DIR/v1v2-bridge.mjs" ] || die "v1v2-bridge.mjs not found next to this script."

say "1/4  Copying the bridge INTO the container"
# proot's $HOME is /root, which is why the file must live there - not in Termux.
base64 -w0 "$REPO_DIR/v1v2-bridge.mjs" | proot-distro login "$BOX" -- /bin/bash -c \
  "base64 -d > $BRIDGE_IN_CONTAINER && chmod +x $BRIDGE_IN_CONTAINER && echo \"    wrote $BRIDGE_IN_CONTAINER (\$(wc -c < $BRIDGE_IN_CONTAINER) bytes)\"" \
  || die "could not copy the bridge into $BOX"

say "2/4  Checking the V2 server on $SERVER_PORT"
if ! curl -fsS -m 5 -u "$USER_NAME:$PASS" -o /dev/null \
      "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null; then
  echo "    not responding - starting it"
  [ -x "$HOME/start-phone-opencode.sh" ] && bash "$HOME/start-phone-opencode.sh"
  for _ in $(seq 1 20); do
    curl -fsS -m 3 -u "$USER_NAME:$PASS" -o /dev/null \
      "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null && break
    sleep 2
  done
fi
echo -n "    upstream: "
curl -s -m 5 -u "$USER_NAME:$PASS" "http://127.0.0.1:$SERVER_PORT/api/info" || echo "(no response)"
echo

say "3/4  Writing the launcher and starting the bridge"
cat > "$HOME/start-phone-bridge.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
# Start the V1<->V2 bridge on $BRIDGE_PORT
pkill -f "v1v2-bridge.mjs" 2>/dev/null
sleep 1
nohup proot-distro login $BOX -- /bin/bash -c \
  'PORT=$BRIDGE_PORT HOST=0.0.0.0 UPSTREAM=http://127.0.0.1:$SERVER_PORT \
   UPSTREAM_USERNAME=$USER_NAME UPSTREAM_PASSWORD="$PASS" \
   BRIDGE_USERNAME=$USER_NAME BRIDGE_PASSWORD="$PASS" \
   node $BRIDGE_IN_CONTAINER' \
  > \$HOME/bridge.log 2>&1 &
EOS
chmod +x "$HOME/start-phone-bridge.sh"
bash "$HOME/start-phone-bridge.sh"
sleep 5

say "4/4  Verification"
tail -6 "$HOME/bridge.log" 2>/dev/null | sed 's/^/    /'
echo
echo -n "    V1 /global/health : "
curl -s -m 8 -u "$USER_NAME:$PASS" "http://127.0.0.1:$BRIDGE_PORT/global/health" || echo "(no response)"
echo
echo
echo "  Point the app at:  http://127.0.0.1:$BRIDGE_PORT"
echo
