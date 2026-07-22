# Development and release

## Requirements

- macOS 13 or later;
- Xcode 15 or later;
- Swift Package Manager;
- Apple Silicon or Intel (the release artifact is universal).

## Preparing a transferred copy

Do not carry over `.build` or `dist`. They hold machine-specific build products
and are ignored by Git. To make a clean copy of the source:

```zsh
./source-archive.command
```

If the ZIP arrives via a browser, WhatsApp, or AirDrop, macOS may set the
quarantine flag on every extracted file. On the destination machine:

```zsh
xattr -dr com.apple.quarantine "/caminho/para/claude-usage-monitor-mac"
cd "/caminho/para/claude-usage-monitor-mac"
./prepare-local.command
```

The prepare step refuses folders owned by another user and does not need
`sudo`.

There are no third-party packages or runtime dependencies.

## Structure

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

## Tests

The automation environment may block Swift from writing global caches. Use
project-local caches instead:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

Current coverage validates:

- parsing of the 5-hour and 7-day windows;
- partial payloads and preservation of missing windows;
- session context, model, and official metadata;
- rejection of invalid percentages and timestamps;
- state round trip and `0600` permissions;
- distinguishing missing state from an invalid cache;
- milestone transitions across windows;
- hiding values after a reset;
- installing, restoring, and preserving the status line;
- normalization of the executable's absolute path;
- detection of `disableAllHooks`;
- migration of the 3.1 cache and minimization of persisted data;
- bitmap rendering and fixed dimensions of the AppKit views;
- recognition and migration of the legacy Node command;
- the 1 MiB limit on the previous status line output.

## CLI modes

The bundle's executable can be tested without opening the interface:

```sh
APP="dist/Claude Usage Monitor.app/Contents/MacOS/ClaudeUsageMonitor"

"$APP" --show
"$APP" --install-statusline
"$APP" --uninstall-statusline
```

Manual ingestion:

```sh
printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":44,"resets_at":1784140200},"seven_day":{"used_percentage":27,"resets_at":1784300400}}}' |
  "$APP" --ingest-statusline
```

To avoid touching the real profile:

```sh
export CLAUDE_USAGE_MONITOR_BASE_DIR="$(mktemp -d)"
export CLAUDE_USAGE_MONITOR_SETTINGS_FILE="$CLAUDE_USAGE_MONITOR_BASE_DIR/settings.json"
```

## Building the bundle

```sh
./build-app.command
```

The script:

1. runs `swift test`;
2. compiles the release build;
3. creates `dist/Claude Usage Monitor.app`;
4. copies the executable and `Info.plist`;
5. applies an ad hoc signature;
6. validates with `codesign` and `plutil`.

## Version

Update these fields in `App/Info.plist`:

```text
CFBundleShortVersionString
CFBundleVersion
```

Record the change in `CHANGELOG.md` before producing the artifact.

## Signing for distribution

The full publishing walkthrough (Apple Developer account, certificate,
notarization, and GitHub Release) lives in [RELEASE.md](RELEASE.md). This
section is the operational summary.

With no environment variables set, `build-app.command` signs ad hoc, for local
use. For public distribution, the script handles the full flow:

```zsh
# one time only, stores the notarytool credentials in the Keychain:
xcrun notarytool store-credentials notary \
  --apple-id "your@email" --team-id "TEAMID" --password "app-specific"

CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="notary" \
./build-app.command
```

This signs with hardened runtime and a timestamp, submits to the notary
service, staples the ticket, and produces a ready-to-publish
`dist/ClaudeUsageMonitor-<version>.zip`. The script also validates the ticket
with `stapler`, Gatekeeper acceptance with `spctl`, and both architectures of
the universal binary.

The bundle uses the stable identity
`com.guilhermerozenblat.ClaudeUsageMonitor`. Do not change it after the first
release: preferences, notifications, and the login item are all tied to it.

Distribute this app directly with a Developer ID, not through the Mac App
Store. It updates `~/.claude/settings.json` and runs the previous status line,
which the store's mandatory App Sandbox does not allow.

## Universal build

`build-app.command` builds universal (arm64 + x86_64) by default and prints the
executable's architectures. Use `UNIVERSAL=0` to build only the local
architecture during development.

## Release checklist

```text
[ ] Swift tests pass
[ ] Info.plist has the correct version
[ ] CFBundleIdentifier remains stable
[ ] release bundle was rebuilt
[ ] lipo shows arm64 and x86_64
[ ] codesign --verify --deep --strict passes
[ ] public release uses Developer ID, hardened runtime, timestamp, and notarization
[ ] stapler validate and spctl pass on the public artifact
[ ] --ingest-statusline and --show modes pass in a temporary directory
[ ] installed app appears in the menu bar
[ ] settings.json points to the installed executable
[ ] README and CHANGELOG were updated
```
