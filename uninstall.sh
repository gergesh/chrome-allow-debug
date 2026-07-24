#!/usr/bin/env bash
#
# uninstall.sh — stop and remove the ChromeAllowDebug daemon, app, CLI, and logs.

set -euo pipefail

LABEL="${LABEL:-com.yoav.chrome-allow-debug}"
APP_DIR="${APP_DIR:-$HOME/Applications/ChromeAllowDebug.app}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/chrome-allow-debug.log"
UID_="$(id -u)"

echo "==> Stopping the launchd agent"
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true

echo "==> Removing files"
rm -f "$PLIST"
rm -rf "$APP_DIR"
rm -f "$BIN_DIR/chrome-allow-debug"
rm -f "$LOG"

cat <<DONE
✅ Uninstalled.

Note: macOS keeps a leftover (now-broken) "ChromeAllowDebug" entry in
System Settings › Privacy & Security › Accessibility. Remove it there
with the – button if you want a clean list.
DONE
