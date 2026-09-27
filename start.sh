#!/data/data/com.termux/files/usr/bin/bash
# Start the OpenCode V2 server (4096) and the V1<->V2 bridge (4097).
set -u
echo "Starting OpenCode (server 4096 + bridge 4097)..."
[ -x "$HOME/start-phone-opencode.sh" ] && bash "$HOME/start-phone-opencode.sh" || echo "  [!] start-phone-opencode.sh missing - run setup-phone.sh"

echo -n "  waiting for the V2 server "
for _ in $(seq 1 25); do
  if curl -fsS -m 3 -u opencode:Vaporwave1127! -o /dev/null \
       http://127.0.0.1:4096/api/info 2>/dev/null; then echo "ok"; break; fi
  echo -n "."
  sleep 2
done

[ -x "$HOME/start-phone-bridge.sh" ] && bash "$HOME/start-phone-bridge.sh" || echo "  [!] start-phone-bridge.sh missing - run setup-phone.sh"
sleep 4
bash "$(dirname "$0")/status.sh"
