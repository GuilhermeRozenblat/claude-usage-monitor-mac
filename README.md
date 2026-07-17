# Claude Usage Monitor para macOS

App nativo de barra de menus que exibe a conta conectada, limites do plano,
resets, uso do contexto e informações da sessão atual do Claude Code.

```text
✓ 40%

conta@exemplo.com
Funcionando normalmente
Limite de 5 horas      40%
Limite de 7 dias       28%
Contexto da sessão     18%
```

Os dados de uso e sessão vêm exclusivamente dos campos oficiais enviados à
[status line do Claude Code](https://code.claude.com/docs/en/statusline). Para o
cabeçalho, o app confirma a sessão com
[`claude auth status`](https://code.claude.com/docs/en/cli-usage) e lê somente o
e-mail dos metadados locais do perfil; não lê nem persiste tokens. Ele não abre
`claude.ai`, não usa Playwright, não faz scraping e não implementa cliente de
rede.

A interface acompanha automaticamente o idioma preferido do macOS em inglês,
português (pt-BR) ou espanhol. Quando nenhum deles é encontrado, usa inglês
como fallback. **Ajustes > Geral > Idioma** permite escolher outro idioma e
salva a preferência. O binário de release é universal (Apple Silicon e Intel),
macOS 13+.

## Planos suportados

O monitor mostra o que a status line do Claude Code envia, e ela só envia
limites para assinaturas do Claude.ai.

| Plano | Limite de 5 h | Limite de 7 dias |
| --- | --- | --- |
| Pro, Max, Team, Enterprise por assento | sim | sim |
| Chave de API, Console, Bedrock, Vertex, Foundry | não | não |
| Enterprise por consumo | não | não |
| Free | sem acesso ao Claude Code | nenhum |

Com cobrança por token não existem janelas de uso: o consumo é faturado por
token e a
[documentação da status line](https://code.claude.com/docs/en/statusline)
afirma que `rate_limits` *"won't show up when using API keys directly"*. O app
detecta esse caso e diz isso, em vez de esperar por dados que nunca chegam.

Cada janela pode faltar por si só, mesmo com a outra presente, e a documentação
oficial registra o comportamento mas não lista as condições. Quando o limite de
7 dias não vem, o app mostra "não enviado para este plano" e o gráfico esconde
a série, em vez de desenhar uma legenda para uma linha inexistente.

Os planos Max têm ainda um limite semanal específico de Sonnet, e existe um
limite por modelo do Opus. **Nenhum dos dois aparece na status line**: só o
`/usage` os mostra. O monitor não pode exibir o que não recebe, e o tooltip do
medidor de 7 dias diz isso.

Os percentuais são sempre relativos ao limite do **seu** plano: a Anthropic
publica apenas múltiplos relativos (Max 5x = "5 vezes o Pro"), nunca números
absolutos. Por isso 50% num Pro e 50% num Max 20x significam consumos absolutos
muito diferentes, mas a mesma coisa útil: metade do que você tem.

## Instalação

### Código recebido por ZIP, WhatsApp ou AirDrop

O macOS pode colocar todo o projeto em quarentena ao extrair um arquivo recebido.
Prepare somente esta pasta antes do primeiro build:

```zsh
xattr -dr com.apple.quarantine "/caminho/para/claude-usage-monitor-mac"
cd "/caminho/para/claude-usage-monitor-mac"
./prepare-local.command
```

Não use `sudo`. O comando confirma que a pasta pertence ao usuário atual,
remove a quarentena apenas do projeto e preserva as proteções do restante do
sistema.

### Instalar o app compilado

O bundle está em:

```text
dist/Claude Usage Monitor.app
```

Mova o app para `~/Applications` e abra-o. Se o macOS bloquear a primeira
execução, clique com o botão direito no app e escolha **Abrir**.

### Compilar e instalar

Requer macOS 13 ou mais recente e Xcode 15 ou mais recente.

```sh
chmod +x *.command
./install.command
```

O instalador:

1. executa os testes Swift;
2. compila o executável em modo release;
3. cria e assina localmente o bundle `.app`;
4. instala em `~/Applications/Claude Usage Monitor.app`;
5. configura a status line do Claude Code;
6. abre o app na barra superior do macOS.

Não use `sudo`.

Para transferir somente o código-fonte, sem `.build`, binários ou metadados
locais, execute `./source-archive.command`. Para colaboração contínua, prefira
um repositório Git a enviar a pasta compilada.

## Uso

O app não aparece no Dock. Procure o ícone de estado e o percentual na barra
superior do macOS. O símbolo informa a saúde do monitor:

- círculo com check: integração ativa e dados válidos;
- relógio: aguardando o primeiro payload;
- exclamação: janela encerrada ou notificações bloqueadas;
- octógono com X: integração ou cache com erro.

Clique no item para ver:

- percentual do limite de 5 horas;
- data e hora do próximo reset de 5 horas;
- percentual do limite de 7 dias;
- data e hora do próximo reset de 7 dias;
- uso, tokens e tamanho da janela de contexto da sessão;
- modelo, projeto, esforço, thinking, duração e versão do Claude Code;
- custo API estimado da sessão, quando enviado;
- horário e idade da última atualização;
- estado da integração com o Claude Code e da permissão de notificações;
- mini-gráfico da janela de 5 h corrente, com o ritmo projetado ("no ritmo
  atual: 100% às 14:32") ou o pico da janela;
- **Histórico de uso…** com a janela de 5 h corrente e gráficos de 24 h, 7, 30
  e 90 dias (coletado localmente pela própria ingestão), e a repartição do
  consumo do período por modelo;
- botões para atualizar a exibição, abrir o histórico e abrir o **Sobre**;
- **Ajustes** (⌘,) com duas abas: **Geral** (início de sessão, idioma,
  integração, dados) e **Alertas** (tipos de alerta, marcos e pausa de 1 hora);
- menu **•••** com copiar o resumo de uso, reconfigurar a integração, abrir a
  pasta de dados e encerrar.

A aba **Geral** dos Ajustes abre com a identidade do app: ícone, versão e
autoria.

Na primeira execução, permita as notificações do macOS. O app avisa nos marcos
de 25%, 50%, 75%, 90% e 100% do limite de 5 horas e de 75%, 90% e 100% do
limite de 7 dias. Se o app estava fechado quando um marco foi cruzado, o maior
marco pendente é notificado ao abrir (dados com mais de 30 minutos não geram
alerta). Quando uma janela que passou de 75% reinicia, o app anuncia que o uso
foi liberado.

## Atualização dos dados

O Claude Code envia `rate_limits` depois de respostas da API. Para atualizar:

1. mantenha o app aberto;
2. abra uma sessão autenticada do Claude Code;
3. envie uma mensagem e aguarde a resposta.

Uso feito em `claude.ai` ou no Claude Desktop aparece quando o Claude Code recebe
a próxima resposta. O app reage na hora a novos dados (observa o arquivo de
estado); o item **Atualizar exibição** relê o cache local sob demanda e não faz
uma chamada de rede. Depois da releitura, envia uma notificação com os últimos
valores de 5 horas e 7 dias e seus resets.

Quando o horário de reset passa sem uma nova resposta, o app deixa de mostrar o
percentual antigo como atual e exibe **aguardando nova janela**. Se os dados
param de chegar por mais de 15 minutos com a janela ainda ativa, o cabeçalho
avisa **sem dados recentes**.

O campo pode estar ausente antes da primeira resposta, para autenticação por API
key ou em contas sem uma assinatura Claude.ai compatível.

## O que cada número significa

- **5 horas e 7 dias:** limites do plano compartilhados entre superfícies Claude.
- **Contexto:** quanto da memória da conversa atual está ocupado; não é limite do
  plano e pode cair depois de `/compact` ou ao iniciar outra sessão.
- **Custo API estimado:** cálculo local do Claude Code. A
  [documentação oficial de custos](https://code.claude.com/docs/en/costs) informa
  que esse valor não representa cobrança para assinantes Pro e Max.

O comando interativo `/usage` do Claude Code pode mostrar divisões adicionais
por skills, subagentes, plugins e MCPs. Esses dados não fazem parte do JSON da
status line e, por isso, não são inventados nem extraídos pelo monitor.

## Iniciar com o macOS

Abra **Ajustes > Geral** e marque **Abrir ao iniciar sessão**. A opção usa
`SMAppService`, a API nativa de itens de login do macOS.

O macOS também permite revisar essa permissão em **Ajustes do Sistema > Geral >
Itens de Início de Sessão**.

## Comandos auxiliares

Consultar o último estado no Terminal:

```sh
./check-now.command
```

Renovar o login do Claude Code:

```sh
./relogin.command
```

Recompilar somente o bundle:

```sh
./build-app.command
```

Remover o app e restaurar a status line anterior:

```sh
./uninstall.command
```

## Solução de problemas

### O ícone não aparece na barra

Abra manualmente:

```sh
open "$HOME/Applications/Claude Usage Monitor.app"
```

Se a barra estiver cheia, encerre ou reorganize outros itens da barra.

### O app mostra `aguardando dados`

1. confirme `claude --version` 2.1.80 ou mais recente;
2. confirme `claude auth status`;
3. em **Ajustes > Geral**, escolha **Reconfigurar Claude Code**;
4. reinicie o Claude Code e aceite a confiança do workspace;
5. envie uma mensagem e aguarde a resposta.

Se o painel mostrar `bloqueada por disableAllHooks`, altere essa opção em
`~/.claude/settings.json`; a documentação oficial informa que ela também desativa
a status line.

### O percentual parece desatualizado

O app mostra o último valor recebido. Envie uma mensagem no Claude Code para
obter novos `rate_limits`.

### As notificações não aparecem

Confira a linha **Notificações** no painel. Se a permissão estiver bloqueada,
clique em **Atualizar exibição** para abrir o atalho aos Ajustes do Sistema.

## Desenvolvimento

Estrutura principal:

```text
Sources/ClaudeUsageMonitor/       Código AppKit e modos CLI
Tests/ClaudeUsageMonitorTests/    Testes XCTest
App/Info.plist                    Metadados do bundle
build-app.command                 Build, assinatura e empacotamento
dist/Claude Usage Monitor.app     App gerado
```

Executar apenas os testes:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

Documentação complementar:

- [Guia do usuário](docs/USER_GUIDE.md)
- [Arquitetura](docs/ARCHITECTURE.md)
- [Desenvolvimento e release](docs/DEVELOPMENT.md)
- [Segurança](SECURITY.md)
- [Histórico de mudanças](CHANGELOG.md)

## Arquivos locais

App instalado:

```text
~/Applications/Claude Usage Monitor.app
```

Estado e backup da status line:

```text
~/Library/Application Support/ClaudeUsageMonitor
```

Configuração integrada:

```text
~/.claude/settings.json
```
