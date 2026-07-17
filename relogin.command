#!/bin/zsh
set -euo pipefail

find_claude() {
  local candidate
  local -a candidates

  if command -v claude >/dev/null 2>&1; then
    candidates+=("$(command -v claude)")
  fi
  candidates+=(
    "$HOME/.local/bin/claude"
    "$HOME/.claude/local/claude"
    /opt/homebrew/bin/claude
    /usr/local/bin/claude
  )

  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] && { print -r -- "$candidate"; return 0; }
  done
  return 1
}

CLAUDE_BIN="$(find_claude)" || {
  echo "Claude Code não foi encontrado."
  read -r "?Pressione Enter para fechar..."
  exit 1
}

"$CLAUDE_BIN" auth login
echo "Login concluído. Envie uma mensagem no Claude Code para atualizar o app."
read -r "?Pressione Enter para fechar..."
