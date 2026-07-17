# Segurança

## Dados processados

O executável recebe o JSON completo da status line em `stdin`, mas decodifica
somente limites, contexto, modelo, nome de sessão, nome curto do projeto, versão,
esforço, thinking, duração e custo API estimado.

O app ignora `transcript_path`, não persiste o caminho completo do projeto e não
lê conversas. Para identificar a conta, executa `claude auth status` e lê somente
`oauthAccount.emailAddress` de `~/.claude.json` quando a CLI confirma um login
ativo. Não acessa tokens de autenticação, cookies, Keychain ou perfis de
navegador e não implementa cliente de rede.

## Escritas no sistema

- `~/Library/Application Support/ClaudeUsageMonitor/state.json`;
- `~/Library/Application Support/ClaudeUsageMonitor/history.jsonl`;
- arquivos cooperativos `state.lock` e `history.lock` no mesmo diretório;
- `~/Library/Application Support/ClaudeUsageMonitor/previous-statusline.json`;
- a chave `statusLine` de `~/.claude/settings.json`;
- registro de item de login, apenas quando habilitado pelo menu.

Estado, histórico, locks, backup e settings usam permissão `0600`; arquivos
estruturados substituídos por inteiro usam gravação atômica. O diretório base
usa `0700`.

## Execução de comandos

Uma status line preexistente continua sendo executada porque já fazia parte da
configuração confiada pelo usuário. O subprocesso usa `/bin/zsh`, timeout de 1,5
segundo, stderr descartado e coleta incremental limitada a 1 MiB. Se o comando
não encerrar após `terminate`, o processo recebe `SIGKILL`.

O app não executa lifecycle scripts de pacotes e não possui dependências de
runtime de terceiros.

Para mostrar a conta conectada, o app também executa diretamente o binário local
do Claude Code com `auth status --json`, em fila de background e com timeout de
2 segundos. O stdout é usado apenas para o estado de autenticação; stderr é
descartado.

## Assinatura

O bundle local recebe assinatura ad hoc (`codesign --sign -`). Ela garante a
integridade estrutural usada pelo macOS, mas não identifica um desenvolvedor e
não equivale a notarização da Apple.

Para distribuição pública, substitua a assinatura ad hoc por Developer ID
Application, habilite hardened runtime e timestamp e envie o app para
notarização. O `build-app.command` automatiza esse fluxo quando recebe
`CODESIGN_IDENTITY` e `NOTARY_PROFILE`. Builds locais ad hoc podem exigir
**botão direito > Abrir** na primeira execução e não devem ser publicados.

Valide o artefato antes da instalação:

```sh
codesign --verify --deep --strict "dist/Claude Usage Monitor.app"
plutil -lint "dist/Claude Usage Monitor.app/Contents/Info.plist"
```

## Sandbox

O app não usa App Sandbox porque precisa atualizar `~/.claude/settings.json`,
manter arquivos em Application Support e executar uma status line anterior. Não
execute o instalador com `sudo`.

## Remoção

`uninstall.command` restaura a status line anterior, encerra o processo, remove o
bundle de `~/Applications` e apaga somente o diretório de dados do monitor.

Para o checklist operacional de release, consulte
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
