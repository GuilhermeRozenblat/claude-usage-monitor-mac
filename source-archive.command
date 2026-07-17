#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PARENT="$(dirname "$ROOT")"
PROJECT="$(basename "$ROOT")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/App/Info.plist")"
ARCHIVE="${SOURCE_ARCHIVE:-$PARENT/ClaudeUsageMonitor-source-$VERSION.zip}"

if [[ "$ARCHIVE" != /* ]]; then
  echo "SOURCE_ARCHIVE precisa ser um caminho absoluto." >&2
  exit 1
fi

/bin/rm -f "$ARCHIVE"
cd "$PARENT"

# -X descarta metadados extras do macOS. Artefatos, credenciais, estado local de
# ferramentas e o histórico do Git ficam fora do pacote; somente o código-fonte
# reproduzível é enviado.
#
# Os padrões de credenciais levam `*` antes do ponto: sem ele o zip só casava na
# raiz do projeto, e um `.env` numa subpasta entrava no pacote apesar do
# comentário aqui prometer o contrário.
/usr/bin/zip -qry -X "$ARCHIVE" "$PROJECT" \
  -x "$PROJECT/.build/*" \
     "$PROJECT/.swiftpm/*" \
     "$PROJECT/.git/*" \
     "$PROJECT/dist/*" \
     "$PROJECT/DerivedData/*" \
     "$PROJECT/.DS_Store" \
     "$PROJECT/*/.DS_Store" \
     "$PROJECT/*.env" \
     "$PROJECT/*.env.*" \
     "$PROJECT/.claude/settings.local.json" \
     "$PROJECT/.impeccable/*" \
     "$PROJECT/*.p12" \
     "$PROJECT/*.cer" \
     "$PROJECT/*.pem" \
     "$PROJECT/*.key" \
     "$PROJECT/*.mobileprovision" \
     "$PROJECT/*.provisionprofile"

/usr/bin/unzip -tq "$ARCHIVE" >/dev/null
echo "Código-fonte criado sem caches nem metadados locais herdados:"
echo "  $ARCHIVE"
