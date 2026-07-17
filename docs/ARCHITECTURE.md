# Arquitetura

## Visão geral

Claude Usage Monitor 3.5 é um app nativo AppKit para macOS. O mesmo executável
atua como app de barra de menus e como receptor da status line do Claude Code.

A interface suporta inglês, português (pt-BR) e espanhol. No modo automático,
`Locale.preferredLanguages` escolhe o primeiro idioma suportado e inglês é o
fallback. A escolha manual fica em `UserDefaults` e também vale para os modos
CLI. As strings vivem em `L10n.swift` (sem arquivos `.lproj`, para funcionar
também em `--ingest-statusline` sem depender de recursos do bundle).

```text
Resposta do Claude Code
        |
        v
JSON de uso e sessão em stdin
        |
        v
ClaudeUsageMonitor --ingest-statusline
        |
        +-> state.json (0600) com marcos cruzados por janela
        +-> history.jsonl (0600) com amostras locais
        +-> texto da status line
        |
        v
App de menu observa o diretório de dados (DispatchSource) e relê ao gravar;
um timer de 30 segundos cobre transições de relógio (countdown, expiração,
dados obsoletos)
        |
        +-> percentual na barra superior
        +-> painel com 5h, 7d, contexto e sessão
        +-> entrega de notificações de marcos, 7 dias e janela reiniciada
```

Não existe serviço HTTP, navegador automatizado, LaunchAgent ou processo Node.

## Modos do executável

Sem argumentos, o binário inicia `NSApplication` com política `.accessory`. A
chave `LSUIElement` no `Info.plist` remove o ícone do Dock.

Modos auxiliares:

```text
--ingest-statusline     recebe JSON do Claude Code e atualiza o estado
--install-statusline    configura ~/.claude/settings.json
--uninstall-statusline  restaura a configuração anterior
--show                  imprime o último estado no Terminal
```

## Componentes Swift

### `MenuBarApp.swift`

Cria `NSStatusItem` com ícone SF Symbol dinâmico e percentual. Os estados são
saudável, aguardando, atenção e erro. O clique alterna o painel; o app não usa
NSMenu.

Detecta cobrança por chave de API (`ClaudeAccount.authMethod`) e, nesse caso,
explica que não existem janelas de uso em vez de aguardar `rate_limits` que a
status line nunca envia para esse tipo de autenticação.

### `MonitorPanel.swift` e `MonitorPanelController.swift`

Um `NSPanel` sem moldura ancorado ao item da barra, na forma que a Apple usa
nos próprios extras (Wi-Fi, Som, Central de Controlo). Um NSMenu dimensiona-se
pelo item mais largo e desenha a própria moldura, então não aceita vidro nem
acompanha views de largura fixa; o painel dispensou toda a aritmética de
truncagem que existia só para o conter.

A sombra é desenhada por nós (`Glass.panelSurface`) com `hasShadow = false`: o
macOS deriva a sombra da janela do alpha do backing, o NSGlassEffectView é
composto na GPU e não escreve lá os cantos, e o resultado era uma sombra
quadrada à volta de um painel arredondado. A janela leva `Metrics.shadowMargin`
de folga transparente de cada lado, e a ancoragem desconta essa margem.

### `Design.swift`

Paleta, métricas e a superfície de vidro. `Glass.wrap` usa `NSGlassEffectView`
(Liquid Glass) no macOS 26 e recua para `NSVisualEffectView` nas versões
anteriores, mantendo o piso em macOS 13. Os hexadecimais da marca vivem aqui
uma vez só; antes estavam duplicados em `MenuViews` e `HistoryWindow`.

### `SettingsWindow.swift`

Janela de Ajustes (⌘,) com abas **Geral** e **Alertas**, no vocabulário de
formulário do sistema (`NSGridView`). Sem vidro por dentro, de propósito: os
Ajustes do Sistema do macOS 26 usam a moldura padrão. A aba Geral abre com a
identidade do app (ícone, versão, autoria).

`MenuViews.swift` desenha as barras com acentos Claude dinâmicos: um tom mais
escuro sobre superfícies claras e um mais luminoso no modo escuro, preservando
contraste, tipografia e cores semânticas do macOS. Em 75% usa alerta laranja;
em 90%, vermelho.

Janelas cujo reset já passou deixam de exibir o percentual em cache. Dados sem
atualização há mais de 15 minutos com janela ativa entram no estado de atenção
`sem dados recentes`. O refresh manual relê o cache e envia uma notificação com
os valores disponíveis. O item **Copiar resumo de uso** coloca o mesmo resumo na
área de transferência e o tooltip do ícone traz o resumo completo.

A releitura é dirigida por eventos: um `DispatchSourceFileSystemObject` observa
o diretório de dados e o check de integração só reparseia
`~/.claude/settings.json` quando o mtime muda.

O item de login usa `SMAppService.mainApp`. Notificações usam
`UNUserNotificationCenter`.

### `UsageModels.swift`

Decodifica exclusivamente os campos necessários:

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
model.display_name
workspace.project_dir
context_window.*
session_name
version
effort.level
thinking.enabled
cost.total_cost_usd
cost.total_duration_ms
```

Percentuais fora de 0 a 100 são rejeitados. Cada janela de limite é opcional e
independente. O caminho do projeto é reduzido ao último componente antes de ser
persistido. `transcript_path` não é decodificado.

### `StatusLineProcessor.swift`

Atualiza limites e metadados da sessão sem apagar campos opcionais ausentes e
encadeia uma status line preexistente, quando houver. O comando anterior recebe o
mesmo JSON, tem timeout de 1,5 segundo e saída drenada com limite de memória de
1 MiB.

Um payload não vazio que falha no parse grava `lastIngestErrorAt` em
`state.json` sem apagar o restante do estado; o menu sinaliza `última leitura
falhou` enquanto não chega um payload válido mais recente.

Quando o payload traz `rate_limits`, o ingest também acrescenta uma amostra em
`history.jsonl` (`HistoryStore`): JSONL com `{t, h5, d7, c}`, throttle de 60s
pelo timestamp da última amostra válida, escrita com `O_APPEND` e retenção de
90 dias — o prune roda no app, não no ingest.

`FileLock.swift` fornece locks cooperativos entre processos. O ciclo completo
de leitura/modificação/gravação de `state.json` é serializado para que sessões
simultâneas não sobrescrevam campos umas das outras. Append, leitura e poda do
histórico usam outro lock estável, evitando linhas parciais e perda de amostras
durante a substituição atômica feita pela poda.

### `UsageTrends.swift`

`PaceEstimator` faz regressão linear sobre as amostras dos últimos 45 minutos
(descartando o trecho anterior a uma queda de janela) e projeta quando a
janela de 5h atinge 100%; a projeção só aparece com ritmo ≥ 2 pontos/h, dado
fresco e reset posterior à projeção. `CostAggregator` estima o custo de um
período somando os aumentos do custo cumulativo por sessão (quedas indicam
sessão nova). A `TrendView` do painel mostra a sparkline da janela de 5h
corrente e a projeção; o app relê o `history.jsonl` apenas quando o mtime muda.

### `HistoryWindow.swift`

Janela **Histórico de uso…** com a janela de 5h corrente e faixas de
24h/7d/30d/90d. Gráfico de linhas desenhado em AppKit: séries de 5h e 7d
(laranja Claude e azul, validados para daltonismo nos dois modos), grid
recessivo em 0-100%, referência tracejada em 90%, quebra de linha em lacunas
sem amostras (não interpola períodos sem uso), downsample para ≤500 pontos
preservando picos, crosshair com leitura de valores sob o cursor e pico do
período no rodapé.

`ChartSpan` resolve o intervalo do eixo. A janela de 5h é ancorada no reset
(`resets_at − 5h` até `resets_at`), não em "agora": um range rolante de
"últimas 5h" atravessaria o reset e desenharia um penhasco de 90% para 0% que
parece queda de uso e não é. É o mesmo artefato que o `PaceEstimator` já
descarta para não corromper a projeção. Sem reset conhecido, recua para o
intervalo rolante. A janela começa sempre depois de `agora − 5h` (o reset está
no futuro), então carregar 5h de histórico cobre-a inteira.

O eixo Y é sempre 0-100% do limite do próprio plano, nunca auto-escalado aos
dados: a Anthropic não publica limites absolutos, apenas múltiplos relativos, e
a percentagem é a única escala que significa o mesmo num Pro e num Max 20x.
Auto-escalar faria 18% de uso desenhar uma montanha.

A legenda e o rodapé seguem o que o payload traz: em planos sem limite semanal,
a série de 7 dias some em vez de deixar uma legenda apontando para uma linha
inexistente.

### `AboutWindow.swift`

Janela Sobre com o esqueleto do painel Sobre do sistema: ícone, nome, versão,
uma linha e a assinatura de Guilherme Rozenblat com a bandeira. O ícone traz um
anel de doze traços que acendem em sequência, e os blocos entram em cascata de
45 ms. O anel é desenho original: reproduzir a marca da Anthropic num app de
terceiros é terreno de marca registada. O fundo usa `NSVisualEffectView`, o
equivalente translúcido nativo compatível com macOS 13, e se adapta ao modo
claro/escuro. As animações respeitam **Reduzir movimento**.

### `SettingsManager.swift`

Migra a integração Node legada sem substituir o backup original. Instalações
subsequentes atualizam o caminho do executável caso o app tenha sido movido.

Na remoção, restaura a status line anterior. Uma configuração alterada pelo
usuário depois da instalação é preservada.

### `StateStore.swift`

Persiste `state.json` de forma atômica. O diretório usa permissão `0700` e o
arquivo usa `0600`. A leitura diferencia arquivo ausente de JSON inválido.
O decoder migra automaticamente as chaves `lastUsage` e `updatedAt` da versão
3.1 para o formato atual.

## Notificações

A detecção e a entrega são separadas, com uma única fonte de verdade:

- **Ingest (`ThresholdTracker`)** registra em `state.json` quais marcos cada
  janela cruzou (`notifiedThresholds` para 5 horas, `sevenDayNotifiedThresholds`
  para 7 dias), mesmo com o app fechado. A mudança de `resets_at` ou uma queda
  superior a 10 pontos limpa os marcos.
- **App (`ThresholdDelivery`)** compara os marcos registrados com o que já foi
  entregue (UserDefaults) e notifica a diferença. Se o app esteve fechado
  durante a subida, entrega uma única notificação com o maior marco pendente em
  vez de empilhar várias. Dados com mais de 30 minutos são marcados como
  entregues sem alerta.

Os marcos são 25%, 50%, 75%, 90% e 100% da janela de 5 horas e 75%, 90% e 100%
da janela de 7 dias. Quando uma janela que atingiu 75% ou mais reinicia, o app
anuncia **uso liberado** uma vez, até 30 minutos após o reset
(`WindowResetAnnouncement`).

A aba **Alertas** dos Ajustes permite desligar cada tipo de alerta e pausar
tudo por 1 hora. O snooze segura os alertas sem marcá-los como entregues: ao expirar,
cruzamentos ainda recentes são notificados e os antigos caem na regra de idade.

A ingestão continua atualizando o cache mesmo quando a interface não está em
execução; a entrega das notificações acontece quando o app abre.

## Build e bundle

Swift Package Manager compila o produto `ClaudeUsageMonitor`. O script
`build-app.command` roda os testes, compila **universal (arm64 + x86_64)** por
padrão (`UNIVERSAL=0` desliga), cria a estrutura `.app` e valida o bundle com
`codesign` e `plutil`. Requer macOS 13 ou mais recente.

Assinatura e notarização para distribuição:

```zsh
# uma vez: xcrun notarytool store-credentials notary --apple-id ... --team-id ...
CODESIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" \
NOTARY_PROFILE="notary" \
./build-app.command
```

Sem essas variáveis a assinatura é ad hoc (uso local). Com `CODESIGN_IDENTITY`
o app é assinado com hardened runtime; com `NOTARY_PROFILE` o zip é submetido
ao notarytool, o ticket é grampeado e `dist/ClaudeUsageMonitor-<versão>.zip`
fica pronto para distribuição.
