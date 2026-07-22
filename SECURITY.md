# Security

## Data processed

The executable receives the full status line JSON on `stdin`, but decodes only
the limits, context, model, session identifier and name, short project name,
version, effort, thinking, duration, and estimated API cost. The `session_id`
is kept only in the history samples, where it is what allows costs to be summed
without mixing concurrent sessions; it is never written to `state.json`. Text
from the payload is stripped of control characters and truncated to 120
characters before being displayed or stored.

The app ignores `transcript_path`, does not persist the full project path, and
does not read conversations. To identify the account, it runs `claude auth
status` and reads only `oauthAccount.emailAddress` from `~/.claude.json` when
the CLI confirms an active login. It does not access authentication tokens,
cookies, the Keychain, or browser profiles, and it implements no network
client.

## System writes

- `~/Library/Application Support/ClaudeUsageMonitor/state.json`;
- `~/Library/Application Support/ClaudeUsageMonitor/history.jsonl`;
- the cooperative `state.lock` and `history.lock` files in the same directory;
- `~/Library/Application Support/ClaudeUsageMonitor/previous-statusline.json`;
- the `statusLine` key in `~/.claude/settings.json`;
- a login item entry, only when enabled from the menu.

State, history, locks, backup, and settings use `0600` permissions;
structured files that are replaced in full use atomic writes. The base
directory uses `0700`.

## Command execution

A pre-existing status line continues to run because it was already part of the
configuration the user trusted. The subprocess uses `/bin/zsh`, a 1.5-second
timeout, discarded stderr, and incremental collection capped at 1 MiB. If the
command does not exit after `terminate`, the process is sent `SIGKILL`.

Writing the payload to the child's `stdin` is done off the thread that times
the operation, so that the timeout holds even when the command never reads
stdin, and the descriptor requests `F_SETNOSIGPIPE`: a reader that closes
becomes a handled error rather than a signal that kills the process.

The app does not run package lifecycle scripts and has no third-party runtime
dependencies.

To show the connected account, the app also runs the local Claude Code binary
directly with `auth status --json`, on a background queue and with a 2-second
timeout. Its stdout is used only for the authentication state; stderr is
discarded.

## Global shortcut

The ⌥⌘U shortcut is optional and ships disabled. When enabled, it uses Carbon's
`RegisterEventHotKey`, the system API for global shortcuts: macOS delivers only
that combination to the app and no other keystroke. The app neither requests
nor uses the Accessibility permission that would be required to observe the
entire keyboard (which is what `NSEvent.addGlobalMonitorForEvents` would
demand), and therefore has no way to see what is typed in other apps. The
preference lives in UserDefaults; nothing is written outside the app.

## Signing

The local bundle receives an ad hoc signature (`codesign --sign -`). It
guarantees the structural integrity macOS relies on, but does not identify a
developer and is not equivalent to Apple notarization.

For public distribution, replace the ad hoc signature with a Developer ID
Application signature, enable the hardened runtime and a timestamp, and submit
the app for notarization. `build-app.command` automates this flow when given
`CODESIGN_IDENTITY` and `NOTARY_PROFILE`. Local ad hoc builds may require
**right-click > Open** on first launch and should not be published.

Validate the artifact before installing:

```sh
codesign --verify --deep --strict "dist/Claude Usage Monitor.app"
plutil -lint "dist/Claude Usage Monitor.app/Contents/Info.plist"
```

## Sandbox

The app does not use the App Sandbox because it needs to update
`~/.claude/settings.json`, keep files in Application Support, and run a previous
status line. Do not run the installer with `sudo`.

## Removal

`uninstall.command` restores the previous status line, terminates the process,
removes the bundle from `~/Applications`, and deletes only the monitor's data
directory.

For the operational release checklist, see
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
