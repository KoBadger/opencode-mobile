#!/data/data/com.termux/files/usr/bin/bash
# Report what is running and whether both ports answer correctly.
#
# NOTE: `pgrep`/`netstat` inside Termux CANNOT see proot processes, so they give
# false "not running" results. HTTP probes are the only reliable check.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

line() { printf "  %-26s %s\n" "$1" "$2"; }

echo "=========================================="
echo " OpenCode status"
echo "=========================================="

probe() { # url -> http code
  curl -s -m 6 -u "$OPENCODE_USER:$OPENCODE_PASS" -o /dev/null -w "%{http_code}" "$1" 2>/dev/null
}

judge() { # code -> label
  case "$1" in
    200)      echo "UP  (HTTP 200)" ;;
    401)      echo "UP but AUTH FAILED (check OPENCODE_PASS in config.env)" ;;
    000|"")   echo "DOWN (no response)" ;;
    *)        echo "UNEXPECTED (HTTP $1)" ;;
  esac
}

if ! command -v curl >/dev/null 2>&1; then
  echo
  echo "curl is not installed. Run:  pkg install curl"
  exit 1
fi

echo
echo "V2 server  (port $SERVER_PORT)"
line "status" "$(judge "$(probe "http://127.0.0.1:$SERVER_PORT/api/info")")"
info=$(curl -s -m 6 -u "$OPENCODE_USER:$OPENCODE_PASS" "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null)
[ -n "$info" ] && line "info" "$(echo "$info" | head -c 120)"

echo
echo "V1 bridge  (port $BRIDGE_PORT)   <- the Android app uses THIS one"
line "status" "$(judge "$(probe "http://127.0.0.1:$BRIDGE_PORT/global/health")")"
health=$(curl -s -m 6 -u "$OPENCODE_USER:$OPENCODE_PASS" "http://127.0.0.1:$BRIDGE_PORT/global/health" 2>/dev/null)
line "health" "${health:-(no body)}"

echo
echo "App settings"
line "Server URL" "http://127.0.0.1:$BRIDGE_PORT"
line "Username" "$OPENCODE_USER"
line "Password" "$OPENCODE_PASS"

echo
echo "Logs"
line "server" "~/server-phone.log  ($(wc -l < "$HOME/server-phone.log" 2>/dev/null || echo 0) lines)"
line "bridge" "~/bridge.log        ($(wc -l < "$HOME/bridge.log" 2>/dev/null || echo 0) lines)"
if [ -s "$HOME/bridge.log" ] && grep -qi "error\|cannot find\|EADDRINUSE" "$HOME/bridge.log" 2>/dev/null; then
  echo
  echo "  [!] bridge.log mentions an error:"
  grep -i "error\|cannot find\|EADDRINUSE" "$HOME/bridge.log" 2>/dev/null | tail -3 | sed 's/^/      /'
fi
echo
