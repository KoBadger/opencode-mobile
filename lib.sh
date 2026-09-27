#!/data/data/com.termux/files/usr/bin/bash
# Shared configuration loader. Source this from every script:
#     . "$(dirname "$0")/lib.sh"
#
# Reads config.env if present, otherwise config.env.example, otherwise the
# built-in defaults below.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# defaults
OPENCODE_USER="${OPENCODE_USER:-opencode}"
OPENCODE_PASS="${OPENCODE_PASS:-change-me}"
SERVER_PORT="${SERVER_PORT:-4096}"
BRIDGE_PORT="${BRIDGE_PORT:-4097}"
BOX="${BOX:-ubuntu}"
BRIDGE_IN_CONTAINER="${BRIDGE_IN_CONTAINER:-/root/v1v2-bridge.mjs}"

# config.env wins if it exists
if [ -f "$_LIB_DIR/config.env" ]; then
  # shellcheck disable=SC1091
  . "$_LIB_DIR/config.env"
elif [ -f "$_LIB_DIR/config.env.example" ]; then
  # shellcheck disable=SC1091
  . "$_LIB_DIR/config.env.example"
fi

# Warn loudly if the placeholder password is still in place.
if [ "$OPENCODE_PASS" = "change-me" ]; then
  printf '\033[1;33m[!] Using the default password. Copy config.env.example to config.env and set OPENCODE_PASS.\033[0m\n' >&2
fi

export OPENCODE_USER OPENCODE_PASS SERVER_PORT BRIDGE_PORT BOX BRIDGE_IN_CONTAINER
