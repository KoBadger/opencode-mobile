#!/data/data/com.termux/files/usr/bin/bash
# Restart both the OpenCode V2 server and the V1<->V2 bridge.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/stop.sh"
sleep 2
bash "$DIR/start.sh"
