# Architecture

## Overview

Claude Usage Monitor 3.6 is a native AppKit app for macOS. One executable serves
as both the menu bar app and the receiver for the Claude Code status line.

The interface supports English, Portuguese (pt-BR), and Spanish. In automatic
mode, `Locale.preferredLanguages` picks the first supported language, falling
back to English. A manual choice is stored in `UserDefaults` and also applies to
the CLI modes. Strings live in `L10n.swift` (no `.lproj` files, so
`--ingest-statusline` works without bundle resources).

```text
Claude Code response
        |
        v
Usage and session JSON on stdin
        |
        v
ClaudeUsageMonitor --ingest-statusline
        |
        +-> state.json (0600) with per-window threshold crossings
        +-> history.jsonl (0600) with local samples
        +-> status line text
        |
        v
Menu app watches the data directory (DispatchSource) and re-reads on write;
a 30-second timer covers clock transitions (countdown, expiration,
stale data)
        |
        +-> percentage in the menu bar
        +-> panel with 5-hour window, 7-day window, context, and session
        +-> delivery of threshold, 7-day, and window-reset notifications
```

There is no HTTP service, headless browser, LaunchAgent, or Node process.

## Executable modes

With no arguments, the binary starts `NSApplication` with the `.accessory`
policy. The `LSUIElement` key in `Info.plist` removes the Dock icon.

Auxiliary modes:

```text
--ingest-statusline     receives JSON from Claude Code and updates state
--install-statusline    configures ~/.claude/settings.json
--uninstall-statusline  restores the previous configuration
--show                  prints the last state to the Terminal
```

## Swift components

### `MenuBarApp.swift`

Creates an `NSStatusItem` with a dynamic SF Symbol icon and percentage. The
states are healthy, waiting, warning, and error. Clicking toggles the panel; the
app does not use NSMenu.

It detects API-key billing (`ClaudeAccount.authMethod`) and then explains that
there are no usage windows, rather than waiting for `rate_limits` that the status
line never sends for that authentication type.

### `MonitorPanel.swift` and `MonitorPanelController.swift`

A borderless `NSPanel` anchored to the menu bar item, in the shape Apple uses for
its own menu extras (Wi-Fi, Sound, Control Center). An NSMenu sizes itself to its
widest item and draws its own frame, so it accepts neither glass nor fixed-width
views; the panel dropped all the truncation arithmetic that existed only to fit
inside one.

We draw the shadow ourselves (`Glass.panelSurface`) with `hasShadow = false`:
macOS derives the window shadow from the backing store's alpha, but
NSGlassEffectView composites on the GPU and does not write its rounded corners
there, so the result was a square shadow around a rounded panel. The window
carries `Metrics.shadowMargin` of transparent slack on each side, and the
anchoring accounts for that margin.

### `Design.swift`

The palette, metrics, and glass surface. `Glass.wrap` uses `NSGlassEffectView`
(Liquid Glass) on macOS 26 and falls back to `NSVisualEffectView` on earlier
versions, keeping the floor at macOS 13. The brand hex values live here once;
they were previously duplicated across `MenuViews` and `HistoryWindow`.

### `SettingsWindow.swift`

The Settings window (⌘,) with **General** and **Alerts** tabs, in the system's
form vocabulary (`NSGridView`). No glass inside: macOS 26 System Settings uses the
standard frame. The General tab opens with the app's identity (icon, version,
authorship).

`MenuViews.swift` draws the gauges with dynamic Claude accents: a darker tone over
light surfaces and a brighter one in dark mode, preserving contrast, typography,
and the semantic colors of macOS. At 75% it uses an orange warning; at 90%, red.

Windows whose reset has already passed stop showing the cached percentage. Data
that has not updated for more than 15 minutes with an active window enters the
`no recent data` warning state. A manual refresh re-reads the cache and sends a
notification with the available values. The **Copy usage summary** item places the
same summary on the clipboard, and the icon's tooltip carries the full summary.

Re-reading is event-driven: a `DispatchSourceFileSystemObject` watches the data
directory, and the integration check only re-parses `~/.claude/settings.json`
when the mtime changes.

The login item uses `SMAppService.mainApp`. Notifications use
`UNUserNotificationCenter`.

### `UsageModels.swift`

Decodes only the fields it needs:

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

Percentages outside 0 to 100 are rejected. Each limit window is optional and
independent. The project path is reduced to its last component before being
persisted. `transcript_path` is not decoded.

### `StatusLineProcessor.swift`

Updates the limits and session metadata without clearing absent optional fields,
and chains a pre-existing status line when one is present. The previous command
receives the same JSON, has a 1.5-second timeout, and its output is drained with a
1 MiB memory cap.

A non-empty payload that fails to parse writes `lastIngestErrorAt` to `state.json`
without clearing the rest of the state; the menu flags `last read failed` until a
more recent valid payload arrives.

When the payload carries `rate_limits`, the ingest also appends a sample to
`history.jsonl` (`HistoryStore`): JSONL with `{t, h5, d7, c, m, s}` (`m` is the
model active in the sample and `s` the session that emitted it; without `s` you
cannot total cost, because cost is accumulated per session and the file is shared
across all of them), throttled to 60s by the timestamp of the last valid sample,
written with `O_APPEND`, and retained for 90 days. The prune runs in the app, not
in the ingest.

`HistoryStore.load` reads from the tail backward, widening the window only if it
has not yet reached the requested period. Samples are appended in time order, so
what matters is always at the end: at full retention, decoding the entire file
cost 267 ms on the main thread for every ingest just to reach the 300 lines of the
last 5 hours. Pruning runs at launch and once per day, since a menu bar app stays
running for months.

`FileLock.swift` provides cooperative cross-process locks. The full
read/modify/write cycle of `state.json` is serialized so concurrent sessions do
not overwrite each other's fields. History append, read, and prune use another
stable lock, avoiding partial lines and lost samples during the atomic replacement
the prune performs.

### `UsageTrends.swift`

`PaceEstimator` runs linear regression over the samples from the last 45 minutes
(discarding the segment before a window drop) and projects when the 5-hour window
reaches 100%; the projection only appears with a pace ≥ 2 points/h, fresh data,
and a reset later than the projection. `CostAggregator` estimates a period's cost
by summing the increases in cumulative cost **per session** (drops indicate a new
session): samples from concurrent sessions interleave in the same file, and summing
the series as one would read every switch as a new session and re-add the other
session's entire cost. `ModelUsage.split` uses the same increment rule to divide
the window's rise among the models: between two samples, the amount that rose
counts toward the model of the more recent one. It is attribution, not a reading,
because the status line does not send `limits[]` per model.

The panel's `TrendView` shows the sparkline of the current 5-hour window and the
projection; the app re-reads `history.jsonl` only when the mtime changes.

### `HistoryWindow.swift`

The **Usage history…** window with the current 5-hour window and 24h/7d/30d/90d
ranges. A line chart drawn in AppKit: 5-hour and 7-day series (Claude orange and
blue, validated for color blindness in both modes), a recessive grid at 0-100%, a
dashed reference at 90%, line breaks at gaps with no samples (it does not
interpolate periods with no usage), downsampling to ≤500 points while preserving
peaks, a crosshair reading the values under the cursor, and the period's peak in
the footer.

`ModelSplitView` sits between the chart and the footer: a split bar with a legend,
fed by `ModelUsage.split` over the **raw** samples (the downsample keeps each
bucket's peak and discards the steps the attribution comes from). It disappears on
its own with fewer than two models, and aggregates the tail into "Others" from the
fifth onward. Below the stacked bar, one `ModelShareRowView` per model (name, its
own bar, percentage), with fixed columns so they align across rows.

The slices use `Palette.modelShare`: opaque tones separated mostly by
**luminosity** (under deuteranopia the red-green axis disappears; luminosity and
yellow-blue remain), with a hue drift on top to add separation for those who see
all the colors. Each tone measures ≥3:1 against the window background and ≥4.5:1
against its own ink (`Palette.ink`, which picks black or white by measured
luminance), verified in `ModelShareContrastTests`. There are three steps plus one
neutral: the fourth orange step does not reach 3:1 in either mode, and the neutral
is also what "Others" means. Between adjacent slices runs a hairline in the
background color, because two adjacent luminosity steps read as a single mass.

`ChartSpan` resolves the axis range. The 5-hour window is anchored to the reset
(`resets_at − 5h` to `resets_at`), not to "now": a rolling "last 5 hours" range
would cross the reset and draw a cliff from 90% to 0% that looks like a drop in
usage but isn't. It's the same artifact `PaceEstimator` discards to avoid
corrupting the projection. With no known reset, it falls back to the rolling range.
The window always starts after `now − 5h` (the reset is in the future), so loading
5 hours of history covers it in full.

The Y axis is always 0-100% of the plan's own limit, never auto-scaled to the
data: Anthropic does not publish absolute limits, only relative multiples, and the
percentage is the only scale that means the same thing on a Pro and on a Max 20x.
Auto-scaling would make 18% of usage draw a mountain.

The legend and footer follow what the payload carries: on plans with no weekly
limit, the 7-day series disappears instead of leaving a legend pointing to a
nonexistent line.

### `AboutWindow.swift`

The About window with the skeleton of the system About panel: icon, name, version,
one line, and the signature of Guilherme Rozenblat with the flag. The icon carries
a ring of twelve ticks that light up in sequence, and the blocks cascade in at 45
ms. The ring is an original drawing: reproducing Anthropic's mark in a third-party
app is trademark territory. The background uses `NSVisualEffectView`, the native
translucent equivalent compatible with macOS 13, and adapts to light/dark mode. The
animations respect **Reduce Motion**.

### `GlobalShortcut.swift`

An optional global shortcut (⌥⌘U) via Carbon's `RegisterEventHotKey`, the system
API for global shortcuts and the only one that does not require an Accessibility
permission (`NSEvent.addGlobalMonitorForEvents` does). Off by default: a global
shortcut takes the combination away from every other app. When the system refuses
the registration (another app got there first), `setEnabled` returns `false` and
the checkbox in Settings backs off instead of promising a nonexistent shortcut.

### `SettingsManager.swift`

Migrates the legacy Node integration without replacing the original backup.
Subsequent installs update the executable path in case the app has moved.

On removal, it restores the previous status line. A configuration the user changed
after installation is preserved.

### `StateStore.swift`

Persists `state.json` atomically. The directory uses `0700` permissions and the
file uses `0600`. Reads distinguish a missing file from invalid JSON. The decoder
automatically migrates the `lastUsage` and `updatedAt` keys from version 3.1 to the
current format.

## Notifications

Detection and delivery are separate, with a single source of truth:

- **Ingest (`ThresholdTracker`)** records in `state.json` which thresholds each
  window has crossed (`notifiedThresholds` for 5 hours,
  `sevenDayNotifiedThresholds` for 7 days), even with the app closed. A change in
  `resets_at` or a drop of more than 10 points clears the thresholds.
- **App (`ThresholdDelivery`)** compares the recorded thresholds with what has
  already been delivered (UserDefaults) and notifies the difference. If the app
  was closed during the rise, it delivers a single notification with the highest
  pending threshold instead of stacking several. Data more than 30 minutes old is
  marked as delivered without an alert.

The thresholds are 25%, 50%, 75%, 90%, and 100% of the 5-hour window and 75%, 90%,
and 100% of the 7-day window. When a window that reached 75% or more resets, the
app announces **usage freed** once, up to 30 minutes after the reset
(`WindowResetAnnouncement`).

The **Alerts** tab in Settings lets you turn off each alert type and pause
everything for 1 hour. The snooze holds alerts without marking them as delivered:
when it expires, still-recent crossings are notified and old ones fall under the
age rule.

Ingest keeps updating the cache even when the interface is not running;
notification delivery happens when the app opens.

## Build and bundle

Swift Package Manager builds the `ClaudeUsageMonitor` product. The
`build-app.command` script runs the tests, builds **universal (arm64 + x86_64)** by
default (`UNIVERSAL=0` turns it off), creates the `.app` structure, and validates
the bundle with `codesign` and `plutil`. Requires macOS 13 or newer.

Signing and notarization for distribution:

```zsh
# once: xcrun notarytool store-credentials notary --apple-id ... --team-id ...
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE="notary" \
./build-app.command
```

Without those variables, the signature is ad hoc (local use). With
`CODESIGN_IDENTITY` the app is signed with the hardened runtime; with
`NOTARY_PROFILE` the zip is submitted to notarytool, the ticket is stapled, and
`dist/ClaudeUsageMonitor-<version>.zip` is ready for distribution.
