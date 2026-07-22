# Claude Usage Monitor for macOS

A native menu bar app that shows your Claude Code account, plan limits, resets,
context usage, and current session details.

```text
✓ 40%

account@example.com
Running normally
5-hour limit          40%
7-day limit           28%
Session context       18%
```

All data comes from the official fields Claude Code sends to its
[status line](https://code.claude.com/docs/en/statusline). The app confirms the
account with [`claude auth status`](https://code.claude.com/docs/en/cli-usage)
and reads only the email from local profile metadata. It never reads or stores
tokens, opens no network connection, and does no scraping.

The interface follows your macOS language (English, Portuguese, or Spanish;
English otherwise) and can be changed in **Settings > General > Language**. The
release binary is universal (Apple Silicon and Intel), macOS 13+.

## Supported plans

Claude Code only sends limits for Claude.ai subscriptions.

| Plan | 5-hour limit | 7-day limit |
| --- | --- | --- |
| Pro, Max, Team, per-seat Enterprise | yes | yes |
| API key, Console, Bedrock, Vertex, Foundry | no | no |
| Usage-based Enterprise | no | no |
| Free | no Claude Code access | none |

With token-based billing there are no usage windows, so the app says so instead
of waiting for data that never arrives. Either window can also be absent on its
own; when the 7-day limit isn't sent, the app labels it and hides the chart
series rather than faking a value.

Percentages are relative to your own plan's limit. Anthropic publishes only
relative multiples (Max 5x = five times Pro), so 50% on Pro and 50% on Max 20x
mean very different absolute usage but the same thing: half of what you have.
Per-model and Sonnet-weekly limits aren't in the status line (only `/usage`
shows them), so the app can't display them. The [user guide](docs/USER_GUIDE.md)
has the details.

## Installation

### Prebuilt release (recommended)

Download `ClaudeUsageMonitor-<version>.zip` from
[Releases](https://github.com/GuilhermeRozenblat/claude-usage-monitor-mac/releases),
unzip, and move `Claude Usage Monitor.app` to `~/Applications`. The app is signed
with a Developer ID and notarized. If macOS blocks the first launch, right-click
the app and choose **Open**.

### Build from source

Requires macOS 13+ and Xcode 15+.

```sh
git clone https://github.com/GuilhermeRozenblat/claude-usage-monitor-mac.git
cd claude-usage-monitor-mac
./install.command
```

The installer runs the tests, builds in release mode, signs the `.app`, installs
it to `~/Applications`, configures the Claude Code status line, and launches the
app. Don't use `sudo`. To rebuild only the bundle, run `./build-app.command`.

## Usage

The app has no Dock icon. Find the status icon and percentage in the menu bar;
the symbol shows the monitor's health:

- checkmark: integration active, data valid;
- clock: waiting for the first payload;
- exclamation: window ended or notifications blocked;
- octagon with an X: integration or cache error.

Click it for the full panel: 5-hour and 7-day percentages with reset times,
session context and tokens, model and reasoning effort, estimated API cost,
last-update age, integration status, a mini-chart of the current 5-hour window
with projected pace, and **Usage history…** (24-hour, 7-, 30-, and 90-day charts
plus a per-model breakdown, all collected locally). The **•••** menu copies the
usage summary, reconfigures the integration, opens the data folder, and quits.

The panel is anchored to the menu bar like the macOS system extras (Wi-Fi,
Sound, Control Center), with Liquid Glass on macOS 26.

**Settings** (⌘,) has two tabs: **General** (open at login, language, global
shortcut, integration, data) and **Alerts** (alert types, thresholds, 1-hour
snooze). To open the panel by keyboard, enable **Global shortcut** (⌥⌘U); it's
off by default because a global shortcut takes that combination from every other
app, and uses `RegisterEventHotKey`, which needs no Accessibility permission.

Allow notifications on first launch. The app alerts at 25/50/75/90/100% of the
5-hour limit and 75/90/100% of the 7-day limit. If it was closed when a threshold
passed, the highest pending one fires on open (data older than 30 minutes is
skipped). When a window that passed 75% resets, the app says usage is freed.

## Status line in the terminal

Besides the panel, the app prints a compact line to the Claude Code status line
at the bottom of the terminal:

```text
Fable 5 (high)  ·  5h 5% ↻ 4h27m  ·  7d 71% ↻ 1d20h
```

It shows the session's model and reasoning effort, each window's percentage
color-coded by band (green, amber, red from 90%) and bold, and the time until
reset (`↻`). Color respects `NO_COLOR` and `TERM=dumb`, so pipes and color-less
terminals get plain text. The `↻` is standard Unicode, no Nerd Fonts needed. If
you already had a status line, the app runs it and appends its own instead of
replacing it.

## Data refresh

Claude Code sends `rate_limits` after API responses. To refresh, keep the app
open, use an authenticated Claude Code session, and wait for a response. Usage
from `claude.ai` or Claude Desktop appears on Claude Code's next response.

The app reacts to new data instantly (it watches the state file) and makes no
network calls; **Refresh display** re-reads the local cache on demand. When a
reset time passes with no new response, it shows **waiting for new window**; if
data stops for over 15 minutes while a window is active, the header warns
**no recent data**.

## What each number means

- **5-hour and 7-day:** plan limits shared across Claude surfaces.
- **Context:** how much of the current conversation is in use; not a plan limit,
  and it drops after `/compact` or a new session.
- **Estimated API cost:** a local Claude Code figure. The
  [cost docs](https://code.claude.com/docs/en/costs) note it isn't a charge for
  Pro and Max subscribers.

`/usage` can show extra breakdowns (skills, subagents, plugins, MCPs) that aren't
in the status line JSON, so the monitor doesn't show them.

## Start with macOS

Open **Settings > General** and check **Open at login** (uses `SMAppService`).
You can also review it in **System Settings > General > Login Items**.

## Helper commands

```sh
./check-now.command    # print the last state in the terminal
./relogin.command      # renew the Claude Code login
./build-app.command    # rebuild only the bundle
./uninstall.command    # remove the app, restore the previous status line
```

## Troubleshooting

**Icon missing from the menu bar.** Open it with
`open "$HOME/Applications/Claude Usage Monitor.app"`. If the bar is full, remove
other items.

**Shows `waiting for data`.** Confirm `claude --version` is 2.1.80 or later and
`claude auth status` works, then choose **Reconfigure Claude Code** in
**Settings > General**, restart Claude Code, accept the workspace trust prompt,
and send a message. If it shows `blocked by disableAllHooks`, change that key in
`~/.claude/settings.json` (it also disables the status line).

**Percentage looks stale.** The app shows the last value received; send a message
to get new `rate_limits`.

**Notifications don't appear.** Check the **Notifications** line in the panel; if
blocked, click **Refresh display** to open System Settings.

## Development

```text
Sources/ClaudeUsageMonitor/       AppKit code and CLI modes
Tests/ClaudeUsageMonitorTests/    XCTest tests
App/Info.plist                    Bundle metadata
build-app.command                 Build, signing, packaging
```

Run the tests:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

More docs: [User guide](docs/USER_GUIDE.md) · [Architecture](docs/ARCHITECTURE.md)
· [Development](docs/DEVELOPMENT.md) · [Release](docs/RELEASE.md) ·
[Security](SECURITY.md) · [Changelog](CHANGELOG.md).

## Local files

```text
~/Applications/Claude Usage Monitor.app                 installed app
~/Library/Application Support/ClaudeUsageMonitor         status line state and backup
~/.claude/settings.json                                  integration config
```

## License

[MIT](LICENSE).
