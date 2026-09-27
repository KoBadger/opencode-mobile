#!/data/data/com.termux/files/usr/bin/bash
# Start the OpenCode V2 server (4096) and the V1<->V2 bridge (4097).
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

echo "Starting OpenCode (server $SERVER_PORT + bridge $BRIDGE_PORT)..."

if [ -x "$HOME/start-phone-opencode.sh" ]; then
  bash "$HOME/start-phone-opencode.sh"
else
  echo "  [!] ~/start-phone-opencode.sh missing - run setup-phone.sh first"
  exit 1
fi

echo -n "  waiting for the V2 server "
for _ in $(seq 1 25); do
  if curl -fsS -m 3 -u "$OPENCODE_USER:$OPENCODE_PASS" -o /dev/null \
       "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null; then echo " ok"; break; fi
  echo -n "."
  sleep 2
done

if [ -x "$HOME/start-phone-bridge.sh" ]; then
  bash "$HOME/start-phone-bridge.sh"
else
  echo "  [!] ~/start-phone-bridge.sh missing - run setup-phone.sh first"
  exit 1
fi

sleep 4
bash "$DIR/status.sh"
