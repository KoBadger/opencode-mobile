#!/data/data/com.termux/files/usr/bin/bash
# Stop the OpenCode V2 server and the V1<->V2 bridge.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

echo "Stopping OpenCode server + bridge..."

# Bridge first, so it doesn't hammer a dying upstream.
pkill -f "v1v2-bridge.mjs" 2>/dev/null && echo "  bridge stopped" || echo "  bridge was not running"
proot-distro login "$BOX" -- /bin/bash -c 'pkill -f v1v2-bridge.mjs 2>/dev/null' 2>/dev/null

# Then the server (this also tears down the proot session).
pkill -9 -f proot 2>/dev/null && echo "  server stopped" || echo "  server was not running"
pkill -9 -f opencode 2>/dev/null

sleep 2
for port in "$SERVER_PORT" "$BRIDGE_PORT"; do
  command -v fuser >/dev/null 2>&1 && fuser -k "${port}/tcp" 2>/dev/null
done

echo "Done."
