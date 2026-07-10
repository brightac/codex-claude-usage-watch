#!/usr/bin/env bash
# Installer for codex-claude-usage-watch.
#   ./install.sh            # install CLIs + build & autostart the HUD
#   ./install.sh --no-hud   # install the CLIs only (no macOS HUD / LaunchAgent)
#   ./install.sh --uninstall
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
USER_NAME="$(id -un)"
LABEL="com.${USER_NAME}.usage-hud"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

uninstall() {
  log "Unloading & removing LaunchAgent"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  pkill -x usage-hud 2>/dev/null || true
  log "Removing installed binaries"
  rm -f "$BIN_DIR/usage-watch" "$BIN_DIR/claude-usage-watch" \
        "$BIN_DIR/codex-usage-watch" "$BIN_DIR/usage-hud"
  log "Done. (Cache in ~/.cache/usage-watch left untouched.)"
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall

command -v node >/dev/null || { echo "node is required (brew install node)"; exit 1; }

log "Installing CLIs into $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/usage-watch"        "$BIN_DIR/usage-watch"
install -m 0755 "$REPO_DIR/bin/claude-usage-watch" "$BIN_DIR/claude-usage-watch"
install -m 0755 "$REPO_DIR/bin/codex-usage-watch"  "$BIN_DIR/codex-usage-watch"

if [[ "${1:-}" == "--no-hud" ]]; then
  log "Skipping HUD (per --no-hud)."
else
  if ! command -v swiftc >/dev/null; then
    echo "swiftc not found (install Xcode Command Line Tools: xcode-select --install)."
    echo "CLIs are installed; re-run without --no-hud after installing swiftc for the HUD."
    exit 0
  fi
  log "Compiling the HUD"
  swiftc -O "$REPO_DIR/bin/usage-hud.swift" -o "$BIN_DIR/usage-hud" -framework AppKit

  log "Installing LaunchAgent ($LABEL) for login autostart"
  mkdir -p "$HOME/Library/LaunchAgents"
  sed "s/__USER__/${USER_NAME}/g" "$REPO_DIR/launchd/com.USER.usage-hud.plist" > "$PLIST"
  plutil -lint "$PLIST" >/dev/null
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  log "HUD launched and set to start at login."
fi

echo
log "Installed. Make sure ~/.local/bin is on your PATH."
echo "   Try:  usage-watch --once      (full view)"
echo "         usage-watch --line      (one line)"
echo "         The HUD is floating on your desktop now (⌘Q to dismiss, drag to move)."
