#!/bin/zsh
set -euo pipefail

# `set -u` recusa HOME por definir, mas aceita HOME vazio, e este script apaga
# pastas: com HOME vazio os caminhos abaixo viravam `/Applications/...` e
# `/Library/...`, que não são nossos.
: "${HOME:?HOME vazio}"

APP="$HOME/Applications/Claude Usage Monitor.app"
EXECUTABLE="$APP/Contents/MacOS/ClaudeUsageMonitor"
BASE_DIR="$HOME/Library/Application Support/ClaudeUsageMonitor"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.local.claude-usage-monitor.plist"

# Quem restaura a status line anterior é o executável, lendo o backup que vive
# em BASE_DIR. Sem ele, apagar BASE_DIR levaria o backup junto e a status line
# original ficaria perdida para sempre, com o settings.json a apontar para um
# binário que já não existe. Acontece com quem arrasta o app para o lixo antes
# de rodar este script, que é o instinto normal no Mac.
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "O app não está em ~/Applications, então a status line anterior não pode" >&2
  echo "ser restaurada agora. Nada foi apagado." >&2
  echo "" >&2
  echo "Reinstale (./install.command) e rode este script outra vez: aí a sua" >&2
  echo "status line original volta e tudo é removido." >&2
  echo "" >&2
  echo "O backup dela está preservado em:" >&2
  echo "  $BASE_DIR/previous-statusline.json" >&2
  exit 1
fi

"$EXECUTABLE" --uninstall-statusline

/usr/bin/pkill -x ClaudeUsageMonitor >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
rm -rf "$APP" "$BASE_DIR"

echo "Claude Usage Monitor removido."
echo ""
read -r "?Pressione Enter para fechar..."
