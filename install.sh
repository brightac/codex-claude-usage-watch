#!/usr/bin/env bash
# Installer for codex-claude-usage-watch.
#   ./install.sh            # install CLIs + build "Usage Watch.app" + autostart
#   ./install.sh --no-hud   # install the CLIs only (no app / LaunchAgent)
#   ./install.sh --uninstall
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
USER_NAME="$(id -un)"
LABEL="com.${USER_NAME}.usage-hud"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_NAME="Usage Watch.app"
# /Applications if writable, else ~/Applications
if [ -w /Applications ]; then APP_DIR="/Applications"; else APP_DIR="$HOME/Applications"; fi
APP="$APP_DIR/$APP_NAME"
APP_EXE="$APP/Contents/MacOS/usage-hud"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

uninstall() {
  log "Unloading & removing LaunchAgent"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  pkill -x usage-hud 2>/dev/null || true
  log "Removing app + CLIs"
  rm -rf "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME"
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
  log "Skipping app (per --no-hud)."
else
  if ! command -v swiftc >/dev/null; then
    echo "swiftc not found (install Xcode Command Line Tools: xcode-select --install)."
    echo "CLIs are installed; re-run without --no-hud after installing swiftc for the app."
    exit 0
  fi

  log "Building $APP_NAME in $APP_DIR"
  pkill -x usage-hud 2>/dev/null || true
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  swiftc -O "$REPO_DIR/bin/usage-hud.swift" -o "$APP_EXE" -framework AppKit
  cp "$REPO_DIR/bin/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  cat > "$APP/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Usage Watch</string>
  <key>CFBundleDisplayName</key><string>Usage Watch</string>
  <key>CFBundleExecutable</key><string>usage-hud</string>
  <key>CFBundleIdentifier</key><string>${LABEL}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLISTEOF
  plutil -lint "$APP/Contents/Info.plist" >/dev/null
  touch "$APP"   # nudge Finder to pick up the icon

  log "Installing LaunchAgent ($LABEL) for login autostart"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>${APP_EXE}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/tmp/usage-hud.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/usage-hud.err.log</string>
</dict></plist>
PLISTEOF
  plutil -lint "$PLIST" >/dev/null
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  log "Usage Watch launched and set to start at login."
fi

echo
log "Installed. Make sure ~/.local/bin is on your PATH."
echo "   CLIs:  usage-watch --once | --line | -i <sec>"
echo "   App:   \"$APP\"  (menu-bar app; ⌘T skin · ⌘R refresh · ⌘Q quit)"
