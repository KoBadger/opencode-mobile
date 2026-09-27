#!/data/data/com.termux/files/usr/bin/bash
# Report what is running and whether both ports answer correctly.
#
# NOTE: `pgrep`/`netstat` inside Termux CANNOT see proot processes, so they give
# false "not running" results. HTTP probes are the only reliable check.
set -u

USER_NAME="opencode"
PASS="Vaporwave1127!"
SERVER_PORT=4096
BRIDGE_PORT=4097

line() { printf "  %-26s %s\n" "$1" "$2"; }

echo "=========================================="
echo " OpenCode status"
echo "=========================================="

# --- V2 server -------------------------------------------------------------
echo
echo "V2 server  (port $SERVER_PORT)"
if ! command -v curl >/dev/null 2>&1; then
  line "curl" "NOT INSTALLED (pkg install curl)"
else
  code=$(curl -s -m 6 -u "$USER_NAME:$PASS" -o /dev/null -w "%{http_code}" \
           "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null)
  case "$code" in
    200) line "status" "UP  (HTTP 200)" ;;
    401) line "status" "UP but AUTH FAILED (check password)" ;;
    000|"") line "status" "DOWN (no response)" ;;
    *)   line "status" "UNEXPECTED (HTTP $code)" ;;
  esac
  body=$(curl -s -m 6 -u "$USER_NAME:$PASS" "http://127.0.0.1:$SERVER_PORT/api/info" 2>/dev/null)
  [ -n "$body" ] && line "info" "$(echo "$body" | head -c 120)"
fi

# --- V1 bridge -------------------------------------------------------------
echo
echo "V1 bridge  (port $BRIDGE_PORT)   <- the Android app uses THIS one"
if command -v curl >/dev/null 2>&1; then
  code=$(curl -s -m 6 -u "$USER_NAME:$PASS" -o /dev/null -w "%{http_code}" \
           "http://127.0.0.1:$BRIDGE_PORT/global/health" 2>/dev/null)
  case "$code" in
    200) line "status" "UP  (HTTP 200)" ;;
    401) line "status" "UP but AUTH FAILED" ;;
    000|"") line "status" "DOWN (no response)" ;;
    *)   line "status" "UNEXPECTED (HTTP $code)" ;;
  esac
  h=$(curl -s -m 6 -u "$USER_NAME:$PASS" "http://127.0.0.1:$BRIDGE_PORT/global/health" 2>/dev/null)
  line "health" "${h:-(no body)}"
fi

# --- app hint --------------------------------------------------------------
echo
echo "App settings"
line "Server URL" "http://127.0.0.1:$BRIDGE_PORT"
line "Username" "$USER_NAME"
line "Password" "$PASS"

# --- logs ------------------------------------------------------------------
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
