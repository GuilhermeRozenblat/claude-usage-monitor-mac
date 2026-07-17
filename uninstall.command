#!/bin/zsh
set -euo pipefail

APP="$HOME/Applications/Claude Usage Monitor.app"
EXECUTABLE="$APP/Contents/MacOS/ClaudeUsageMonitor"
BASE_DIR="$HOME/Library/Application Support/ClaudeUsageMonitor"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.local.claude-usage-monitor.plist"

if [[ -x "$EXECUTABLE" ]]; then
  "$EXECUTABLE" --uninstall-statusline
fi

/usr/bin/pkill -x ClaudeUsageMonitor >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
rm -rf "$APP" "$BASE_DIR"

echo "Claude Usage Monitor removido."
echo ""
read -r "?Pressione Enter para fechar..."
