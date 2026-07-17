# Histórico de mudanças

## Próxima versão

### Interface

- substitui o NSMenu por um painel ancorado à barra, na forma que a Apple usa
  nos próprios extras (Wi-Fi, Som, Central de Controlo). Um NSMenu dimensiona-se
  pelo item mais largo e desenha a própria moldura, o que impedia o vidro do
  sistema e exigia truncar títulos por aritmética de fontes; o painel dispensou
  essa maquinaria inteira;
- adota Liquid Glass (`NSGlassEffectView`) no macOS 26, com recuo para
  `NSVisualEffectView` nas versões anteriores. O piso continua em macOS 13;
- desenha a sombra do painel em vez de usar a da janela: o macOS a deriva do
  alpha do backing, o vidro é composto na GPU e não escreve lá os cantos, e o
  resultado era uma sombra quadrada à volta de um painel arredondado;
- reúne os ajustes numa janela própria (⌘,) com abas Geral e Alertas. Antes
  estavam espalhados por três submenus e não havia ⌘, nenhum;
- a aba Geral abre com a identidade do app: ícone, versão e autoria;
- troca o motivo animado do Sobre por um anel de doze traços de desenho
  original, respeitando **Reduzir movimento**;
- a barra de ações do painel ganha o ⓘ do Sobre ao lado do gráfico e perde o
  ícone de copiar, que passou para o menu "•••" com as outras ações raras;
- o Sobre fica com o esqueleto do painel Sobre do sistema: ícone, nome, versão,
  uma linha e a autoria. Saíram a descrição (repetia a status line e a
  privacidade que os Ajustes já explicam), o cartão da autoria (moldura dentro
  de moldura) e o selo verde "Feito no Brasil", que dizia com texto o que a
  bandeira ao lado já dizia. A autoria continua legível para o VoiceOver;
- o Sobre anima a entrada: cada bloco sobe 8 pt e aparece, 45 ms depois do
  anterior. O halo pulsante saiu: com o anel a girar eram dois movimentos
  contínuos a disputar o mesmo ícone.

### Gráficos

- adiciona a **janela de 5 h corrente** ao histórico, ancorada no reset
  (`resets_at − 5h` até `resets_at`) e não nas últimas 5 h corridas: um range
  rolante atravessaria o reset e desenharia um penhasco de 90% para 0% que
  parece queda de uso e não é;
- o mini-gráfico do painel passa a mostrar essa mesma janela. Em 24 h ele
  cruzava cerca de cinco resets e virava um serrote que nada dizia da janela em
  curso;
- marca "agora" no eixo, que termina no reset;
- mantém o eixo Y fixo em 0-100% do limite do próprio plano, sem auto-escala: a
  Anthropic publica apenas múltiplos relativos, nunca números absolutos, e a
  percentagem é a única escala que significa o mesmo num Pro e num Max 20x.

### Compatibilidade entre planos

- detecta cobrança por chave de API e explica que não existem janelas de uso.
  A status line não envia `rate_limits` para chave de API, Console, Bedrock,
  Vertex, Foundry nem Enterprise por consumo, e o app ficava eternamente em
  "aguardando dados" para essas contas;
- quando o limite de 7 dias não vem, o gráfico esconde a série e o rodapé não
  mostra mais `7d: --`, que sugeria dado quebrado em vez de limite inexistente;
- o medidor de 7 dias explica no tooltip que limites específicos do plano (como
  o semanal de Sonnet no Max) não são informados pela status line.

### Correções

- os formatos de hora deixam de fixar 24 horas em todos os idiomas: o relógio
  agora vem do locale, então o inglês dos EUA volta a ler "2:32 PM" e o espanhol
  perde o zero à esquerda;
- alinha o vocabulário do gráfico ao do painel ("Limite de 5 horas", não "Janela
  de 5 horas" para a mesma coisa);
- copyright do Info.plist em inglês, alinhado ao `CFBundleDevelopmentRegion`;
- reescreve a copy do Sobre, que descrevia o app sem dizer o que ele faz.

### Interno

- mostra no cabeçalho a conta confirmada pelo `claude auth status`, sem ler ou
  persistir tokens e sem reaproveitar e-mail OAuth quando a sessão usa API key;
- remove a quarentena herdada da transferência do projeto e adiciona
  `prepare-local.command` para preparar futuras cópias sem `sudo`;
- adiciona `.gitignore` e `source-archive.command` para impedir que caches,
  binários, certificados e metadados locais sejam transportados com o fonte;
- estabiliza o bundle ID como `com.guilhermerozenblat.ClaudeUsageMonitor`;
- reforça o release universal com validação das duas arquiteturas, hardened
  runtime também no build local, ticket notarizado, `stapler validate` e
  avaliação final do Gatekeeper;
- amplia a suíte para 99 testes.

## 3.5.0 - 2026-07-16

- adiciona **previsão de ritmo (burn rate)**: regressão linear sobre as
  amostras dos últimos 45 minutos projeta quando a janela de 5 horas atinge
  100% ("No ritmo atual: 100% às 14:32"); sem projeção quando o ritmo é
  irrelevante, o dado está obsoleto ou o reset chega antes; uma queda de uso
  dentro da janela de análise descarta a janela anterior;
- adiciona **sparkline das últimas 24 horas** no menu, logo abaixo do medidor
  de 5 horas, com a projeção de ritmo (ou o pico do período) ao lado;
- adiciona **perfis de marcos** no submenu Alertas: todos (padrão), a partir
  de 75% ou só críticos (90%+); o ingest continua registrando todos os marcos
  e a troca de perfil não gera notificações retroativas;
- registra o **custo de API por amostra** no histórico e mostra o custo
  estimado acumulado de 24 h e 7 dias nos detalhes da sessão (soma de aumentos,
  robusta a sessões novas);
- adiciona **Exportar… (CSV)** na janela de histórico
  (`timestamp,five_hour_pct,seven_day_pct,session_cost_usd`);
- substitui o painel Sobre padrão por uma experiência autoral animada, com
  assinatura de Guilherme Rozenblat e selo **Feito no Brasil**;
- adiciona localização completa em espanhol e seletor persistente de idioma
  (automático, inglês, português ou espanhol), com troca imediata e fallback
  em inglês quando o idioma do macOS não é suportado;
- aprimora os modos claro e escuro com materiais translúcidos nativos,
  contrastes específicos por aparência e paletas adaptativas nos medidores,
  gráficos e janela Sobre;
- diferencia limites desatualizados de uma sessão ativa sem `rate_limits` e
  troca o aviso ambíguo por orientações curtas e acionáveis;
- compacta os textos dos medidores e remove o ano dos horários de reset;
- serializa atualizações concorrentes de estado e histórico entre sessões do
  Claude Code, evitando perda de campos e disputa entre poda e ingestão;
- corrige o throttle do histórico para usar o timestamp da última amostra, sem
  bloquear a primeira coleta depois de uma poda;
- corrige parsing de projetos com caminhos longos, contadores iguais a zero,
  limpeza de erros de ingestão recuperados e validação do tipo da status line;
- passa a informar erros de gravação ao exportar o histórico;
- o app relê o history.jsonl apenas quando o mtime muda;
- amplia a suíte para 80 testes.

## 3.4.0 - 2026-07-16

- adiciona **histórico de uso com gráficos** (24h / 7 dias / 30 dias / 90 dias):
  o ingest grava amostras em `history.jsonl` (mínimo 60s entre amostras,
  retenção de 90 dias), e a janela **Histórico de uso…** desenha as séries de
  5 horas e 7 dias com crosshair interativo, linha de referência em 90%,
  legenda e pico do período; cores validadas para daltonismo nos modos claro
  e escuro;
- **inglês passa a ser o idioma padrão**; português (pt-BR) é usado quando é o
  idioma preferido do sistema — UI, notificações, statusline e `--show`;
- **binário universal** (Apple Silicon + Intel) por padrão no build;
- suporte a **assinatura Developer ID e notarização** no `build-app.command`
  via `CODESIGN_IDENTITY` e `NOTARY_PROFILE` (hardened runtime, notarytool,
  stapler e zip de distribuição);
- adiciona `docs/COMPETITORS.md` (análise competitiva com ranking de features)
  e `docs/ROADMAP.md` (plano de desenvolvimento);
- amplia a suíte para 56 testes.

## 3.3.0 - 2026-07-16

- unifica a detecção de marcos no `state.json` gravado pela ingestão; o app
  passa a apenas entregar, eliminando a lógica duplicada em UserDefaults;
- notifica marcos cruzados com o app fechado ao reabrir: uma única notificação
  com o maior marco pendente, apenas se os dados tiverem menos de 30 minutos;
- adiciona alertas do limite de 7 dias (75%, 90% e 100%);
- anuncia **uso liberado** uma vez quando uma janela que atingiu 75% reinicia;
- adiciona o submenu **Alertas** com toggles por tipo e silêncio de 1 hora;
- sinaliza **sem dados recentes** quando o uso não é atualizado há 15 minutos
  com a janela ainda ativa, no cabeçalho e no medidor de 5 horas;
- substitui o polling de 3 segundos por observação do diretório de dados
  (DispatchSource) com timer de 30 segundos apenas para transições de relógio;
- só reparseia `~/.claude/settings.json` quando o mtime muda;
- registra `lastIngestErrorAt` quando um payload não vazio falha no parse e
  mostra **última leitura falhou** no menu;
- adiciona **Copiar resumo de uso** e tooltip com o resumo completo no ícone;
- unifica a formatação de `--show`, notificação de atualização manual e cópia
  em um único resumo compartilhado;
- troca o `sleep` fixo do `install.command` por espera ativa pelo encerramento
  do processo anterior;
- amplia a suíte para 46 testes.

## 3.2.0 - 2026-07-15

- redesenha o menu com medidores nativos de dimensões estáveis e acento Claude;
- adiciona ícones dinâmicos para estados saudável, aguardando, atenção e erro;
- adiciona uso da janela de contexto, tokens e percentual restante;
- adiciona modelo, projeto, nome da sessão, esforço, thinking, duração, custo API
  estimado e versão do Claude Code em um submenu;
- aceita as janelas de 5 horas e 7 dias de forma independente;
- preserva valores em cache quando um campo opcional some do payload;
- detecta `disableAllHooks`, que impede o Claude Code de executar a status line;
- migra automaticamente o cache 3.1 sem perder os limites existentes;
- não persiste `transcript_path` nem o caminho completo do projeto;
- adiciona testes de renderização AppKit e amplia a suíte para 22 testes;
- documenta possibilidades e limitações conforme a documentação oficial.

## 3.1.0 - 2026-07-15

- adiciona tempo restante aos horários de reset;
- deixa de apresentar como atual uma janela cujo reset já passou;
- envia notificação com os valores de 5 horas e 7 dias no refresh manual;
- mostra no menu o estado da integração e da permissão de notificações;
- diferencia ausência de dados de cache inválido;
- mantém erros de integração visíveis e apresenta falhas de ações ao usuário;
- valida timestamps e percentuais antes de persistir;
- normaliza o caminho da integração para um executável absoluto;
- limita a memória usada pela saída da status line anterior durante a execução;
- alinha menu, status line e CLI ao ocultar valores de janelas encerradas;
- amplia a suíte de 4 para 13 testes.

## 3.0.0 - 2026-07-15

- transforma o monitor em um app nativo AppKit para a barra superior do macOS;
- adiciona `NSStatusItem` com percentual de 5 horas sempre visível;
- adiciona menu com limites de 5 horas e 7 dias, resets e última atualização;
- adiciona notificações nativas com `UNUserNotificationCenter`;
- adiciona opção de iniciar com o macOS usando `SMAppService`;
- substitui o runtime Node por um executável Swift arm64 sem dependências;
- adiciona bundle `LSUIElement`, assinatura ad hoc e instalação em
  `~/Applications`;
- migra automaticamente a status line da versão 2.0;
- adiciona guias separados de uso, arquitetura, segurança e release.

## 2.0.0 - 2026-07-15

- substitui a automação de `claude.ai` pelos campos oficiais `rate_limits` da
  status line do Claude Code;
- remove Playwright, Chromium e todas as dependências de runtime;
- remove o LaunchAgent e a consulta em intervalo fixo;
- adiciona limites de 5 horas e 7 dias com horários oficiais de reinício;
- exibe a data e a hora de reinício ao lado de cada percentual;
- preserva e restaura uma status line preexistente;
- adiciona gravação atômica e permissões `0600` para estado e configurações;
- adiciona testes de extração, validação e formatação dos limites;
- documenta migração, arquitetura, limitações e modelo de segurança.

## 1.0.0 - 2026-07-15

- primeira versão;
- leitura de `claude.ai/settings/usage` com um perfil persistente do Chromium;
- notificações nos marcos de 25%, 50%, 75%, 90% e 100%;
- execução periódica por LaunchAgent.
