# Guia do usuário

## Primeira execução

Claude Usage Monitor é um app de barra de menus (`LSUIElement`). Ele não cria
janela principal e não aparece no Dock.

Depois de instalar:

1. abra `~/Applications/Claude Usage Monitor.app`;
2. permita notificações quando o macOS solicitar;
3. reinicie o Claude Code se ele já estava aberto;
4. aceite a confiança do workspace;
5. envie uma mensagem e aguarde a resposta.

Um ícone de saúde aparece na barra superior acompanhado do percentual da janela
de 5 horas. Check indica funcionamento normal; relógio indica espera; exclamação
indica atenção; X indica erro de integração ou cache.

## Planos e o que aparece

O monitor mostra o que a status line do Claude Code envia, e ela só envia
limites para assinaturas do Claude.ai.

| Plano | 5 horas | 7 dias |
| --- | --- | --- |
| Pro, Max, Team, Enterprise por assento | sim | sim |
| Chave de API, Console, Bedrock, Vertex, Foundry | não | não |
| Enterprise por consumo | não | não |
| Free | sem acesso ao Claude Code | — |

Com cobrança por token não existem janelas de uso: o consumo é faturado por
token. Nesses casos o app diz isso em vez de esperar por dados que nunca chegam.

Os planos Max têm ainda um limite semanal específico de Sonnet, e existe um
limite por modelo do Opus. Nenhum dos dois aparece na status line — só o
comando `/usage` do Claude Code os mostra. Você pode atingir um desses limites
sem que o monitor mostre 100%.

## Painel do app

### Conta do Claude

O cabeçalho mostra o e-mail da conta conectada no Claude Code. A sessão é
confirmada localmente por `claude auth status`; o e-mail só é usado quando esse
comando informa que há login ativo. Depois de logout, metadados antigos do
perfil são ignorados. Chaves de API aparecem sem associar o e-mail de uma conta
OAuth, e nenhum token é lido ou salvo pelo monitor.

### `Limite de 5 horas`

Mostra a porcentagem consumida da janela atual de 5 horas. A linha de detalhe
mostra a data, a hora local e o tempo restante até o reset. A barra usa o acento
Claude em uso normal, laranja após 75% e vermelho após 90%. Depois que a janela
termina, o percentual antigo é substituído por `Encerrado`.

### `Limite de 7 dias`

Mostra o limite semanal de todos os modelos e seu próximo reset. Nem todo plano
recebe essa janela; nesse caso o painel mostra `não enviado para este plano` e o
gráfico esconde a série.

Este é o limite semanal geral. O limite semanal de Sonnet dos planos Max e o
limite por modelo do Opus não são informados pela status line e não aparecem
aqui.

### `Contexto da sessão`

Mostra o percentual ocupado pela conversa atual, tokens presentes no contexto,
tamanho máximo e percentual livre. Contexto não é limite do plano: ele pode cair
depois de `/compact` e recomeça em outra sessão.

### `Detalhes da sessão`

A grade mostra somente campos fornecidos oficialmente: modelo, nome curto do
projeto, nome da sessão, esforço, thinking, duração, custo API estimado e versão
do Claude Code. O custo é uma estimativa local e não representa cobrança de
assinaturas Pro ou Max.

### `Atualizado`

Horário em que o app recebeu o último `rate_limits`, acompanhado da idade do
cache. Não é o horário em que o menu foi aberto.

### `Integração`

Mostra se `~/.claude/settings.json` aponta para o executável instalado. O estado
`requer reparo` pode ser corrigido com **Reconfigurar Claude Code**. O estado
`bloqueada por disableAllHooks` exige alterar essa opção nas configurações do
Claude Code.

### `Notificações`

Mostra se os alertas estão ativos, aguardando permissão ou bloqueados nos Ajustes
do Sistema.

### `Atualizar exibição`

Relê imediatamente `state.json` e envia uma notificação com os últimos valores
válidos de 5 horas, 7 dias e contexto. Janelas encerradas aparecem como
`aguardando nova janela`. Essa ação não consulta a rede. Para obter um valor novo
do serviço, envie uma mensagem no Claude Code. Em uso normal ela raramente é
necessária: o app observa o arquivo de estado e atualiza sozinho quando a
ingestão grava dados novos.

### `Copiar resumo de uso`

No menu **•••**. Copia para a área de transferência o resumo compacto com 5
horas, 7 dias e contexto, o mesmo texto do tooltip do ícone.

### `Histórico de uso…`

Abre uma janela com o gráfico dos limites de 5 horas e 7 dias. Os períodos
disponíveis são a **janela de 5 h** corrente e as faixas de 24 horas, 7, 30 ou
90 dias. Passe o mouse sobre o gráfico para ler os valores de cada momento; a
linha tracejada marca 90%.

A **janela de 5 h** é o período corrente até o reset, não as últimas 5 horas
corridas: o eixo vai do início da janela até o horário do reset, com "agora"
marcado. Assim você lê quanto já gastou e quanto tempo falta. Um período rolante
de "últimas 5 horas" atravessaria o reset e desenharia uma queda de 90% para 0%
que parece consumo despencando, quando na verdade é só a janela reiniciando.

O eixo vertical é sempre 0-100% do limite do **seu** plano e nunca se ajusta aos
dados. A Anthropic publica apenas múltiplos relativos entre planos (Max 5x = "5
vezes o Pro"), nunca números absolutos, então a percentagem é a única medida que
significa o mesmo em qualquer plano. O espaço vazio acima da linha é a folga que
resta.

Em planos que não reportam o limite semanal, a série de 7 dias não aparece no
gráfico nem na legenda. Os dados são coletados localmente pela
própria ingestão (uma amostra por minuto, no máximo, com 90 dias de retenção)
e podem ser apagados removendo `history.jsonl` na pasta de dados. Lacunas no
gráfico correspondem a períodos sem uso do Claude Code — o app não inventa
pontos onde não houve dados. O botão **Exportar…** salva o histórico completo
em CSV (`timestamp,five_hour_pct,seven_day_pct,session_cost_usd`).

### Ajustes > `Alertas`

Liga e desliga os alertas do limite de 5 horas, do limite de 7 dias e o aviso de
janela reiniciada. Em **Notificar nos marcos** você escolhe o perfil: todos os
marcos (padrão), a partir de 75% ou só críticos (90%+) — a mudança vale para as
próximas notificações, sem alertas retroativos. **Silenciar alertas por 1 hora**
segura tudo temporariamente; o item mostra o horário em que o silêncio termina.

### Linha de tendência

Logo abaixo do medidor de 5 horas há um mini-gráfico da janela corrente. Ao
lado, quando o uso está subindo de forma consistente, aparece a projeção
**"No ritmo atual: 100% às HH:mm"**, calculada localmente sobre os últimos 45
minutos de amostras. Sem ritmo relevante, mostra o pico da janela.

### Custo estimado por período

Nos detalhes da sessão, além do custo da sessão atual, o app mostra o custo de
API estimado acumulado nas últimas 24 horas e nos últimos 7 dias, derivado do
histórico local. É uma estimativa: não representa cobrança de planos Pro/Max.

### `Reconfigurar Claude Code`

Regrava a chave `statusLine` em `~/.claude/settings.json` apontando para a
localização atual do app. Use depois de mover ou reinstalar o bundle.

### `Abrir ao iniciar sessão`

Registra ou remove o app como item de login usando a API `SMAppService` do
macOS. O estado também pode ser revisado nos Ajustes do Sistema.

### `Abrir pasta de dados`

Abre `~/Library/Application Support/ClaudeUsageMonitor`, que contém o estado e o
backup da status line anterior.

### `Idioma`

Por padrão, **Automático (Sistema)** acompanha a lista de idiomas preferidos do
macOS. Inglês, português (Brasil) e espanhol são suportados; se nenhum deles
estiver configurado, o app usa inglês. Também é possível selecionar **English**,
**Português (Brasil)** ou **Español** manualmente. A mudança é imediata e fica
salva para as próximas execuções.

### `Sobre`

No botão ⓘ do painel. Segue a ordem do painel Sobre do macOS: ícone, nome,
versão, uma linha sobre o app e a assinatura 🇧🇷 **Desenvolvido por Guilherme
Rozenblat**. O ícone tem um anel de doze traços que acendem em sequência, e os
blocos sobem ao abrir. As duas animações param quando **Reduzir movimento** está
ativo nos Ajustes de Acessibilidade do macOS. Materiais translúcidos e cores se
adaptam aos modos claro e escuro.

### `Encerrar`

Fecha somente a interface de menu. O Claude Code ainda pode atualizar o cache
chamando o modo `--ingest-statusline`, e os marcos cruzados ficam registrados:
ao reabrir o app, o maior marco pendente é notificado se os dados ainda forem
recentes.

## Notificações

Os alertas são enviados nos marcos de 25%, 50%, 75%, 90% e 100% da janela de 5
horas e nos marcos de 75%, 90% e 100% da janela de 7 dias.

- Cada marco é notificado uma vez por janela.
- Quando o timestamp de reset muda, os marcos são liberados novamente.
- Marcos cruzados enquanto o app estava fechado são registrados pela ingestão;
  ao abrir, o app notifica apenas o maior marco pendente, e somente se os dados
  tiverem menos de 30 minutos.
- Quando uma janela que atingiu 75% ou mais reinicia, o app envia **uso
  liberado** uma vez, até 30 minutos após o reset.

Na aba **Alertas** dos Ajustes (⌘,) é possível desligar os alertas de 5 horas,
de 7 dias e o aviso de janela reiniciada, além de **Silenciar alertas por 1
hora**. Ao fim do
silêncio, alertas ainda recentes são entregues; os antigos são descartados.

Permissões podem ser alteradas em **Ajustes do Sistema > Notificações > Claude
Usage Monitor**.

## Estados comuns

### `aguardando dados`

O app ainda não recebeu uma resposta do Claude Code com `rate_limits`.

### `7 dias: indisponível`

A resposta atual não contém a janela semanal. Isso pode depender da assinatura,
da autenticação ou da disponibilidade do campo no Claude Code.

### Percentual antigo

O valor é um cache. Uso feito em outras superfícies do Claude aparece na próxima
resposta recebida pelo Claude Code.

### `cache inválido`

O arquivo `state.json` existe, mas não contém um estado válido. Use
**Reconfigurar Claude Code** e envie uma nova mensagem. Se persistir, encerre o
app, remova somente `state.json` e abra o app novamente.

## Atualização

Execute novamente `install.command`. O instalador encerra a instância atual,
substitui o bundle, preserva o estado e reabre o app.

## Remoção

Execute `uninstall.command`. O processo:

1. restaura a status line anterior;
2. encerra o app;
3. remove o bundle de `~/Applications`;
4. apaga o diretório de dados do monitor.
