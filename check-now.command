#!/bin/zsh
set -euo pipefail

EXECUTABLE="$HOME/Applications/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Claude Usage Monitor ainda não foi instalado."
  read -r "?Pressione Enter para fechar..."
  exit 1
fi

"$EXECUTABLE" --show

echo ""
read -r "?Pressione Enter para fechar..."
