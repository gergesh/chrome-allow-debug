#!/usr/bin/env bash
#
# install.sh — build ChromeAllowDebug, install it as a launchd agent, and install
# the optional `chrome-allow-debug` CLI. Idempotent: safe to re-run to update.

set -euo pipefail

# ---- configuration (override via env if you like) ----------------------------
LABEL="${LABEL:-com.yoav.chrome-allow-debug}"
BUNDLE_ID="${BUNDLE_ID:-com.yoav.chromeallowdebug}"
APP_DIR="${APP_DIR:-$HOME/Applications/ChromeAllowDebug.app}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/chrome-allow-debug.log"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC="$APP_DIR/Contents/MacOS/ChromeAllowDebug"

command -v swiftc >/dev/null || { echo "error: swiftc not found (install Xcode or the Command Line Tools)." >&2; exit 1; }

echo "==> Compiling ChromeAllowDebug"
mkdir -p "$APP_DIR/Contents/MacOS"
swiftc -O -o "$EXEC" "$REPO_DIR/Sources/ChromeAllowDebug.swift" \
  -framework AppKit -framework ApplicationServices

echo "==> Writing app bundle Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>ChromeAllowDebug</string>
    <key>CFBundleDisplayName</key>     <string>Chrome Allow Debug</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>ChromeAllowDebug</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>LSBackgroundOnly</key>        <true/>
</dict>
</plist>
PLISTEOF

echo "==> Ad-hoc signing (stable identifier so the Accessibility grant persists)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "==> Installing CLI to $BIN_DIR/chrome-allow-debug"
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/chrome-allow-debug" "$BIN_DIR/chrome-allow-debug"

echo "==> Writing LaunchAgent $PLIST"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXEC</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLISTEOF

echo "==> (Re)loading the launchd agent"
UID_="$(id -u)"
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$PLIST"
launchctl kickstart -k "gui/$UID_/$LABEL"

echo "==> Opening the Accessibility settings pane"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

cat <<DONE

✅ Installed.

ONE manual step (required once): in System Settings ›
Privacy & Security › Accessibility, enable "ChromeAllowDebug".
If it isn't listed, click +, press ⌘⇧G, and add:
  $APP_DIR

No restart needed — the daemon re-checks every second and starts
working the instant you enable it.

Watch it:   tail -f "$LOG"
Uninstall:  ./uninstall.sh
DONE
