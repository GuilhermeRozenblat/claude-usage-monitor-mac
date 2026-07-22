# Desenvolvimento e release

## Requisitos

- macOS 13 ou mais recente;
- Xcode 15 ou mais recente;
- Swift Package Manager;
- Apple Silicon ou Intel (o artefato de release é universal).

## Preparar uma cópia transferida

Não transporte `.build` nem `dist`: esses diretórios contêm produtos específicos
da máquina e são ignorados pelo Git. Para criar uma cópia limpa do fonte:

```zsh
./source-archive.command
```

Se o ZIP chegar por navegador, WhatsApp ou AirDrop, o macOS pode propagar a
quarentena para todos os arquivos extraídos. Na máquina de destino:

```zsh
xattr -dr com.apple.quarantine "/caminho/para/claude-usage-monitor-mac"
cd "/caminho/para/claude-usage-monitor-mac"
./prepare-local.command
```

O preparo recusa pastas que pertençam a outro usuário e não requer `sudo`.

Não existem pacotes de terceiros ou dependências de runtime.

## Estrutura

```text
App/Info.plist
Sources/ClaudeUsageMonitor/
  MenuBarApp.swift
  MenuViews.swift
  SettingsManager.swift
  StateStore.swift
  StatusLineProcessor.swift
  UsageModels.swift
  main.swift
Tests/ClaudeUsageMonitorTests/
Package.swift
build-app.command
```

## Testes

O ambiente de automação pode impedir o Swift de gravar caches globais. Use
caches dentro do projeto:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

A cobertura atual valida:

- parsing das janelas de 5 horas e 7 dias;
- payload parcial e preservação de janelas ausentes;
- contexto, modelo e metadados oficiais da sessão;
- rejeição de percentuais e timestamps inválidos;
- round trip e permissão `0600` do estado;
- distinção entre estado ausente e cache inválido;
- transição de marcos entre janelas;
- ocultação de valores após o reset;
- instalação, restauração e preservação da status line;
- normalização do caminho absoluto do executável;
- detecção de `disableAllHooks`;
- migração do cache 3.1 e minimização de dados persistidos;
- renderização em bitmap e dimensões fixas das views AppKit;
- reconhecimento e migração do comando Node legado;
- limite de 1 MiB da saída da status line anterior.

## Modos CLI

O executável do bundle pode ser testado sem abrir a interface:

```sh
APP="dist/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"

"$APP" --show
"$APP" --install-statusline
"$APP" --uninstall-statusline
```

Ingestão manual:

```sh
printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":44,"resets_at":1784140200},"seven_day":{"used_percentage":27,"resets_at":1784300400}}}' |
  "$APP" --ingest-statusline
```

Para não alterar o perfil real:

```sh
export CLAUDE_USAGE_MONITOR_BASE_DIR="$(mktemp -d)"
export CLAUDE_USAGE_MONITOR_SETTINGS_FILE="$CLAUDE_USAGE_MONITOR_BASE_DIR/settings.json"
```

## Criar o bundle

```sh
./build-app.command
```

O script:

1. executa `swift test`;
2. compila o produto release;
3. cria `dist/Claude Usage Monitor.app`;
4. copia o executável e `Info.plist`;
5. aplica assinatura ad hoc;
6. valida com `codesign` e `plutil`.

## Versão

Atualize estes campos em `App/Info.plist`:

```text
CFBundleShortVersionString
CFBundleVersion
```

Registre a mudança em `CHANGELOG.md` antes de gerar o artefato.

## Assinatura para distribuição

O passo a passo completo de publicação (conta Apple Developer, certificado,
notarização e GitHub Release) está em [RELEASE.md](RELEASE.md); esta seção é o
resumo operacional.

Sem variáveis de ambiente, o `build-app.command` assina ad hoc (uso local).
Para distribuição pública, o próprio script cuida do fluxo completo:

```zsh
# uma única vez, guarda as credenciais do notarytool no Keychain:
xcrun notarytool store-credentials notary \
  --apple-id "seu@email" --team-id "TEAMID" --password "app-specific"

CODESIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" \
NOTARY_PROFILE="notary" \
./build-app.command
```

Isso assina com hardened runtime e timestamp, submete ao serviço notarial,
grampeia o ticket e gera `dist/ClaudeUsageMonitor-<versão>.zip` pronto para
publicar. O script também valida o ticket com `stapler`, a aceitação do
Gatekeeper com `spctl` e as duas arquiteturas do binário universal.

O bundle usa a identidade estável
`com.guilhermerozenblat.ClaudeUsageMonitor`. Não a altere depois da primeira
publicação: preferências, notificações e o item de login são associados a ela.

Este app deve ser distribuído diretamente com Developer ID, não pela Mac App
Store: ele precisa atualizar `~/.claude/settings.json` e executar a status line
anterior, operações incompatíveis com o App Sandbox obrigatório da loja.

## Build universal

O `build-app.command` compila universal (arm64 + x86_64) por padrão e imprime
as arquiteturas do executável. Use `UNIVERSAL=0` para compilar apenas a
arquitetura local durante o desenvolvimento.

## Checklist de release

```text
[ ] testes Swift passam
[ ] Info.plist possui a versão correta
[ ] CFBundleIdentifier continua estável
[ ] bundle release foi recriado
[ ] lipo mostra arm64 e x86_64
[ ] codesign --verify --deep --strict passa
[ ] release público usa Developer ID, hardened runtime, timestamp e notarização
[ ] stapler validate e spctl passam no artefato público
[ ] modos --ingest-statusline e --show passam em diretório temporário
[ ] app instalado aparece na barra de menus
[ ] settings.json aponta para o executável instalado
[ ] README e CHANGELOG foram atualizados
```
