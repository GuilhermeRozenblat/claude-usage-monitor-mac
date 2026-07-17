#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CURRENT_USER="$(id -un)"
OWNER="$(stat -f '%Su' "$ROOT")"

if [[ "$OWNER" != "$CURRENT_USER" ]]; then
  echo "A pasta pertence a '$OWNER', não a '$CURRENT_USER'." >&2
  echo "Mova ou extraia uma nova cópia dentro da sua pasta de usuário." >&2
  exit 1
fi

# Arquivos recebidos por WhatsApp, navegador ou AirDrop podem herdar a
# quarentena do contêiner. O escopo fica restrito a este projeto.
/usr/bin/xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true
/bin/chmod -R u+rwX "$ROOT"
/bin/chmod u+x "$ROOT"/*.command

if [[ -n "$(/usr/bin/xattr -r -p com.apple.quarantine "$ROOT" 2>/dev/null)" ]]; then
  echo "A quarentena ainda existe em algum arquivo do projeto." >&2
  exit 1
fi

echo "Projeto preparado para $CURRENT_USER:"
echo "  $ROOT"
echo "Quarentena removida e permissões locais verificadas."
