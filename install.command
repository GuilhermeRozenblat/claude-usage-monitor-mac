#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$ROOT/dist/Claude Usage Monitor.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/Claude Usage Monitor.app"
EXECUTABLE="$TARGET_APP/Contents/MacOS/ClaudeUsageMonitor"
BASE_DIR="$HOME/Library/Application Support/ClaudeUsageMonitor"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.local.claude-usage-monitor.plist"

echo "Criando Claude Usage Monitor.app..."
/bin/zsh "$ROOT/build-app.command"

mkdir -p "$TARGET_DIR"
/usr/bin/pkill -x ClaudeUsageMonitor >/dev/null 2>&1 || true
for _ in {1..20}; do
  /usr/bin/pgrep -x ClaudeUsageMonitor >/dev/null 2>&1 || break
  sleep 0.1
done
rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

"$EXECUTABLE" --install-statusline

# Limpa somente os componentes da versão antiga em Node/LaunchAgent.
launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
rm -rf "$BASE_DIR/app" "$BASE_DIR/browser-profile"

open "$TARGET_APP"

echo ""
echo "Instalação concluída."
echo "O percentual aparecerá na barra de menus do macOS."
echo "Envie uma mensagem no Claude Code para atualizar os limites."
echo ""
read -r "?Pressione Enter para fechar..."
