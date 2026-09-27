#!/data/data/com.termux/files/usr/bin/bash
# ===========================================================================
#  OpenCode on Android - UNINSTALL
#
#  Run in Termux:   bash setup-phone.sh --uninstall
#             or:   bash uninstall.sh
#
#  Removes everything setup-phone.sh created:
#    - running server + bridge processes
#    - boot hook
#    - generated start scripts
#    - the bridge file inside the container
#    - (optionally) the whole proot Ubuntu container
#
#  Your ~/.config/opencode/ config and the repo itself are KEPT by default.
# ===========================================================================
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$REPO_DIR/lib.sh"

say() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
ok() { printf "    \033[1;32m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }

if [ "${1:-}" != "--yes" ]; then
  cat <<EOF

This will remove the OpenCode phone setup:
  - server + bridge processes (ports $SERVER_PORT / $BRIDGE_PORT)
  - ~/.termux/boot/opencode.sh
  - ~/start-phone-opencode.sh, ~/start-phone-bridge.sh
  - $BRIDGE_IN_CONTAINER inside the container

Kept: ~/.config/opencode/, this repo, and (unless you say so) the container.

EOF
  printf "Continue? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

say "1/5  Stopping processes"
if [ -x "$REPO_DIR/stop.sh" ]; then
  bash "$REPO_DIR/stop.sh" || true
else
  pkill -f "v1v2-bridge.mjs" 2>/dev/null && ok "bridge stopped" || ok "bridge not running"
  pkill -9 -f proot 2>/dev/null
  pkill -9 -f opencode 2>/dev/null
fi

say "2/5  Removing boot hook"
if [ -f "$HOME/.termux/boot/opencode.sh" ]; then
  rm -f "$HOME/.termux/boot/opencode.sh" && ok "removed ~/.termux/boot/opencode.sh"
else
  ok "no boot hook present"
fi
# Remove the boot dir only if nothing else lives in it.
if [ -d "$HOME/.termux/boot" ] && [ -z "$(ls -A "$HOME/.termux/boot" 2>/dev/null)" ]; then
  rmdir "$HOME/.termux/boot" 2>/dev/null && ok "removed empty ~/.termux/boot"
fi

say "3/5  Removing generated start scripts"
for f in start-phone-opencode.sh start-phone-bridge.sh; do
  if [ -f "$HOME/$f" ]; then
    rm -f "$HOME/$f" && ok "removed ~/$f"
  else
    ok "~/$f not present"
  fi
done

say "4/5  Removing the bridge from the container"
if proot-distro login "$BOX" -- /bin/true >/dev/null 2>&1; then
  proot-distro login "$BOX" -- /bin/bash -c \
    "if [ -f $BRIDGE_IN_CONTAINER ]; then rm -f $BRIDGE_IN_CONTAINER && echo '    removed $BRIDGE_IN_CONTAINER'; else echo '    $BRIDGE_IN_CONTAINER not present'; fi"
else
  warn "container '$BOX' not reachable - skipping"
fi

say "5/5  Optionally remove the container"
if proot-distro login "$BOX" -- /bin/true >/dev/null 2>&1; then
  warn "The container still holds OpenCode and your ~/.config/opencode inside it."
  if [ "${1:-}" = "--yes" ]; then
    ok "keeping the container (pass --purge to remove it)"
  else
    printf "    Remove the WHOLE '%s' container too? [y/N] " "$BOX"
    read -r reply
    case "$reply" in
      y|Y|yes|YES)
        proot-distro remove "$BOX" && ok "container removed"
        ;;
      *) ok "container kept" ;;
    esac
  fi
fi

cat <<EOF

===========================================================================
 Uninstall complete.

 Still present:
   ~/.config/opencode/    your config + credentials
   $REPO_DIR
   the '$BOX' container   (unless you chose to remove it)

 To reinstall:  bash setup-phone.sh
===========================================================================
EOF
