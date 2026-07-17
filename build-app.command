#!/bin/zsh
set -euo pipefail

# Configuração por variáveis de ambiente:
#   UNIVERSAL=0            desliga o binário universal (compila só a arch local)
#   CODESIGN_IDENTITY      identidade "Developer ID Application: Nome (TEAMID)";
#                          sem ela, assinatura ad hoc (uso local apenas)
#   NOTARY_PROFILE         perfil do notarytool (xcrun notarytool store-credentials);
#                          exige CODESIGN_IDENTITY; produz dist/*.zip notarizado

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/Claude Usage Monitor.app"
MODULE_CACHE="$ROOT/.build/ModuleCache"
UNIVERSAL="${UNIVERSAL:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && -z "$CODESIGN_IDENTITY" ]]; then
  echo "NOTARY_PROFILE exige CODESIGN_IDENTITY (Developer ID Application)." >&2
  exit 1
fi
if [[ -n "$CODESIGN_IDENTITY" && "$CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "Use uma identidade 'Developer ID Application' para distribuição." >&2
  exit 1
fi

if /usr/bin/xattr -r -p com.apple.quarantine "$ROOT" >/dev/null 2>&1; then
  echo "O projeto ainda contém arquivos em quarentena." >&2
  echo "Execute ./prepare-local.command antes de compilar." >&2
  exit 1
fi

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

cd "$ROOT"
swift test --disable-sandbox

if [[ "$UNIVERSAL" == "1" ]]; then
  swift build -c release --disable-sandbox --arch arm64 --arch x86_64
  BIN_DIR="$ROOT/.build/apple/Products/Release"
else
  swift build -c release --disable-sandbox
  BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeUsageMonitor" "$APP/Contents/MacOS/ClaudeUsageMonitor"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod 755 "$APP/Contents/MacOS/ClaudeUsageMonitor"

echo "Arquiteturas: $(lipo -archs "$APP/Contents/MacOS/ClaudeUsageMonitor")"
if [[ "$UNIVERSAL" == "1" ]]; then
  lipo "$APP/Contents/MacOS/ClaudeUsageMonitor" -verify_arch arm64 x86_64
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  # Hardened runtime é obrigatório para notarização.
  codesign --force --options runtime --timestamp \
    --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Exercita as mesmas restrições de runtime do release público, ainda sem
  # atribuir identidade de desenvolvedor ao build local.
  codesign --force --deep --options runtime --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

if [[ -n "$NOTARY_PROFILE" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  ZIP="$ROOT/dist/ClaudeUsageMonitor-$VERSION.zip"
  rm -f "$ZIP"
  /usr/bin/ditto -c -k --keepParent --noqtn "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=4 "$APP"
  # Regera o zip com o ticket grampeado para distribuição.
  rm -f "$ZIP"
  /usr/bin/ditto -c -k --keepParent --noqtn "$APP" "$ZIP"
  echo "Zip notarizado: $ZIP"
fi

echo ""
echo "App criado em:"
echo "$APP"
