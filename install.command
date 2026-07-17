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
# Copia ao lado e só depois troca: um `rm -rf` antes da cópia deixava o
# utilizador sem app nenhum se o ditto falhasse (disco cheio, pasta protegida).
rm -rf "$TARGET_APP.new"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP.new"
rm -rf "$TARGET_APP"
mv "$TARGET_APP.new" "$TARGET_APP"

# Limpa os componentes da versão antiga antes de configurar: se a configuração
# falhar, o que resta é uma instalação limpa e não uma meia-instalação com o
# LaunchAgent velho ainda carregado.
launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
rm -rf "$BASE_DIR/app" "$BASE_DIR/browser-profile"

if ! "$EXECUTABLE" --install-statusline; then
  echo "" >&2
  echo "O app foi instalado, mas a status line do Claude Code não pôde ser" >&2
  echo "configurada. A causa mais comum é ~/.claude/settings.json com JSON" >&2
  echo "inválido: corrija o arquivo e rode este script outra vez." >&2
  exit 1
fi

open "$TARGET_APP"

echo ""
echo "Instalação concluída."
echo "O percentual aparecerá na barra de menus do macOS."
echo "Envie uma mensagem no Claude Code para atualizar os limites."
echo ""
read -r "?Pressione Enter para fechar..."
