# Changelog

## 3.6.1 - 2026-07-23

### Notifications

- the menu bar icon now re-checks the system notification permission when the
  panel is opened and when the app becomes active again, so changing it in System
  Settings while the app is running is reflected immediately. Previously the state
  was only read at launch and stayed stale until a restart.

## 3.6.0 - 2026-07-22

### Interface

- replaces the NSMenu with a panel anchored to the menu bar, the way Apple does
  it in its own extras (Wi-Fi, Sound, Control Center). An NSMenu sizes itself to
  its widest item and draws its own frame, which blocked the system glass and
  forced titles to be truncated by font arithmetic; the panel drops that whole
  machinery;
- adopts Liquid Glass (`NSGlassEffectView`) on macOS 26, falling back to
  `NSVisualEffectView` on earlier versions. The floor is still macOS 13;
- draws the panel's shadow itself instead of using the window's: macOS derives it
  from the backing alpha, the glass is composited on the GPU and does not write
  its corners there, and the result was a square shadow around a rounded panel;
- gathers the settings into a dedicated window (⌘,) with General and Alerts tabs.
  They were previously scattered across three submenus, with no ⌘, at all;
- the General tab opens with the app's identity: icon, version, and authorship;
- swaps the animated About motif for an original twelve-stroke ring, respecting
  **Reduce Motion**;
- the panel's action bar gains the About ⓘ next to the chart and loses the copy
  icon, which moved to the "•••" menu with the other rare actions;
- About takes on the skeleton of the system About panel: icon, name, version, a
  single line, and authorship. Out went the description (it repeated the status
  line and the privacy points Settings already explains), the authorship card
  (a frame inside a frame), and the green "Made in Brazil" seal, which spelled
  out in text what the flag beside it already said. Authorship stays legible to
  VoiceOver;
- About animates on entry: each block rises 8 pt and fades in, 45 ms after the
  previous one. The pulsing halo is gone: with the ring spinning, it was two
  continuous motions competing over the same icon.

### Terminal status line

- the line printed in Claude Code gains color: each window's percentage turns
  green, amber, or red according to the usage band (critical threshold at 90%),
  in bold, to read the risk at a glance without counting digits;
- now shows the session's **model** and **reasoning effort** for that terminal
  (e.g., `Fable 5 (high)`), read from the status line's official fields;
- time until reset is compact (`↻ 4h27m`) with a standard Unicode symbol that
  renders in any terminal font, with no dependency on Nerd Fonts;
- color respects the `NO_COLOR` and `TERM=dumb` conventions: in a pipe or a
  color-less terminal, the line comes out as clean text.

### Features

- **Where the usage went**: history splits the period across the models that
  responded, in a bar beneath the chart. The status line does not report
  per-model limits, but it does report which model was active, and the app was
  throwing that data away: now each sample stores the model (`m`), and whatever
  the window climbs between two samples counts toward the model of the most
  recent one. This is attribution, not measurement, which is why the bar only
  appears with two or more models: with just one it would be a bar filled with a
  single color, which on a limits screen reads as "100% used". A stacked bar
  compares the models against each other, and a per-model bar compares each one
  against the whole period, which is the reading a thin slice cannot give;
- the combined bar writes the model's name inside its own slice when it fits
  whole (no ellipsis: "Op…" names nothing, and the full name is on the line right
  below). The ink is black or white depending on the slice's luminance, because
  the ramp runs from a light peach to a dark brown and no fixed ink works for
  both ends;
- the split colors are opaque tones separated by luminance, measured against the
  window's real background (`ModelShareContrastTests`). They used to be the
  brand orange with alpha, and the weakest tone reached 1.5:1 against the
  background, that is, invisible. The steps take up the whole range the
  background allows and the hue is derived on top (light pulls toward yellow,
  dark toward red), which adds separation without costing anything to people with
  color blindness: luminance and the yellow-blue axis survive deuteranopia,
  red-green does not. There are three warm steps and not four because the fourth
  no longer reaches 3:1 against the background in either mode, and so the fourth
  place is neutral, which is also what "Other" means;
- **global shortcut ⌥⌘U** (optional, off by default) to open the panel with any
  app in front, in the General tab of Settings. It uses `RegisterEventHotKey`,
  the system API that does not require Accessibility permission. If another app
  already holds the combination, the box backs off and says why instead of
  promising a shortcut that does not exist.

### Charts

- adds the **current 5-hour window** to history, anchored to the reset
  (`resets_at − 5h` through `resets_at`) rather than the last 5 hours elapsed: a
  rolling range would cross the reset and draw a cliff from 90% to 0% that looks
  like a drop in usage but is not;
- the panel's mini-chart now shows that same window. Over 24 h it crossed about
  five resets and turned into a sawtooth that said nothing about the window in
  progress;
- marks "now" on the axis, which ends at the reset;
- keeps the Y axis fixed at 0-100% of the plan's own limit, with no auto-scaling:
  Anthropic publishes only relative multiples, never absolute numbers, and the
  percentage is the only scale that means the same thing on a Pro and on a
  Max 20x.

### Cross-plan compatibility

- detects API-key billing and explains that there are no usage windows. The
  status line does not send `rate_limits` for API keys, Console, Bedrock,
  Vertex, Foundry, or consumption-based Enterprise, and the app sat forever on
  "waiting for data" for those accounts;
- when the 7-day limit does not come, the chart hides the series and the footer
  no longer shows `7d: --`, which suggested broken data rather than a
  nonexistent limit;
- the 7-day gauge explains in its tooltip that plan-specific limits (such as the
  weekly Sonnet limit on Max) are not reported by the status line.

### Stability and security fixes

Findings from a review aimed at failures, each reproduced before being fixed and
covered by a test afterward:

- **cumulative cost was summing concurrent sessions on top of each other.** Each
  sample's `c` is the cumulative cost of *that* Claude Code session, but
  `history.jsonl` is a single file for all of them: with two projects open the
  samples interleave (US$ 3.00 from session A, US$ 0.05 from B, US$ 3.05 from
  A...) and each alternation was read as a new session, adding the other's full
  cost all over again. Six samples were enough to report US$ 6.22 where US$ 0.12
  was spent. Samples now carry the `session_id` and the sum is computed per
  session;
- **a payload over 64 KiB killed the ingest and wiped the status line.** A pipe's
  buffer is 64 KiB: with a larger payload and a previous status line that does
  not read stdin (the common case), the write blocked, the child exited, closed
  the read end, and the SIGPIPE brought the process down. The user was left with
  no status line at all, neither theirs nor ours. The descriptor now requests
  `F_SETNOSIGPIPE` (an error instead of a signal, and only on that descriptor)
  and the write moves off the thread that times it, so the 1.5 s timeout applies
  even when the previous command never reads stdin;
- **a corrupted `state.json` crashed the app on every launch, forever.** The
  payload was validated on the way in, but the cache was decoded raw: a
  `"fiveHourUsage": 1e19` decoded without complaint and `Int(1e19)` crashed the
  process when formatting the number. Because the file decoded, self-repair never
  fired. Percentages are now validated during decoding, and an impossible value
  becomes a disposable cache, which is what it is;
- **history was read whole on the main thread.** At full retention (90 days,
  ~130k lines, 11 MB) it was 267 ms per ingestion just to end up with the 300
  lines from the last 5 h, and the panel opens with a synchronous `reload`.
  Reading now works from the tail, expanding only if needed: 6 ms for the same
  result;
- **the 90-day retention was only applied at launch.** A menu-bar app stays on
  for months, and the file grew past its promised limit without ever being
  pruned. Pruning now also runs once a day;
- **the 5-hour window chart drew the previous window over the axis.** The axis is
  anchored to the reset (`reset − 5h` through `reset`), but the history load
  starts at `now − 5h`, which is earlier: the samples in that stretch belong to
  the window that already reset, and without clipping the trace stacked them all
  on top of the Y axis (a vertical fence from 0 to 98% glued to 0%). Worse: the
  footer announced their peak ("Peak: 5 h 97.5%") as if it were the current
  window's, which was at 20%. Samples are now clipped to the axis, and the peak
  and the per-model split come from the same clip;
- the **now** label wrote over the axis note when the window had just started
  ("% of your plan's limitnow"), and the readout under the cursor competed for
  the same strip. **now** moved inside the chart, beside the line, and the note
  yields the strip to the cursor;
- the per-model split, when hidden (the case of anyone using a single model),
  kept occupying the height of the previous render: it was ~46 pt stolen from the
  chart forever, and up to ~110 pt after viewing a period with three models;
- the Settings footer note computed its line breaks at a width 12 pt wider than
  the real column, and the last word could get cut off;
- `uninstall.command` no longer deletes the status line backup when it cannot
  restore it (the app already being in the trash before the script ran was the
  common path, and the backup went with it: the original status line was lost and
  `settings.json` pointed at a nonexistent binary). It now explains what to do and
  deletes nothing;
- the quarantine guard in `build-app.command` and `prepare-local.command` was
  dead letter: `xattr -r -p` only returns 0 when **every** file has the
  attribute, and the guard used that as "does any have it?". With one file in
  quarantine it stayed silent, and `prepare-local` still said "quarantine removed
  and permissions verified" without having verified;
- `install.command` copies the app alongside and only then swaps (it used to
  delete the installed app first, and if the copy failed the user was left with
  none), and explains what happened when the status line cannot be configured,
  instead of bailing midway and leaving the install half-done;
- `source-archive.command` no longer bundles `.env` files from subfolders (the
  patterns only matched at the root, despite the comment promising otherwise) or
  local tool state, which carried the user's path and a hook the recipient
  inherited on opening the project;
- users billed by API key got "send a message in Claude Code" in the first 30 s
  after opening, waiting for a limit the status line never sends for that kind of
  account. The account's response now updates the gauges instead of waiting for
  the next cycle;
- writing to `~/.claude/settings.json` no longer undoes a symlink. The atomic
  write replaced the link with a loose copy, and anyone keeping their dotfiles in
  a repository ended up with the repository frozen without warning;
- text coming from the payload has its control characters stripped before being
  displayed: a directory name with escape sequences reached the terminal intact
  through `--show`.

### Release audit

- the panel responds to **⌘W** and the menu bar icon gains a **right-click** menu
  (copy summary, history, settings, quit), the two conventions of the system
  extras;
- the History window remembers its position and size between runs, and the period
  selector no longer runs over the legend at minimum width (the legend truncates
  with a tooltip);
- every read of history moves off the main thread (periodic refresh of the open
  window, CSV export, and the 7-day cache): at 90 days of retention, decoding cost
  ~270 ms per cycle on the UI;
- **Copy usage summary** and **Refresh display** confirm inline in the status
  line; the manual refresh only notifies when the panel is out of view, and no
  longer asks for notification permission for an action already visible on
  screen;
- VoiceOver: gauges, header, trend, status lines, and the session grid become
  real accessibility elements (the assembled labels used to be ignored and the
  fields read loose);
- a gauge's truncated detail gains a tooltip with the full text; the main menu
  (invisible, but read by VoiceOver) is localized in all three languages;
- removes dead code (`RateLimitParser`, `SettingsManager.isInstalled`,
  `L10n.languageMenuTitle`), pointing the tests at the real paths;
- adds LICENSE (MIT) and the app category in Info.plist
  (`public.app-category.developer-tools`).

### Fixes

- time formats no longer pin 24-hour across all languages: the clock now comes
  from the locale, so US English reads "2:32 PM" again and Spanish drops the
  leading zero;
- aligns the chart's vocabulary with the panel's ("5-hour limit", not "5-hour
  window" for the same thing);
- Info.plist copyright in English, aligned with `CFBundleDevelopmentRegion`;
- rewrites the About copy, which described the app without saying what it does.

### Internal

- shows in the header the account confirmed by `claude auth status`, without
  reading or persisting tokens and without reusing the OAuth email when the
  session uses an API key;
- removes the quarantine inherited from transferring the project and adds
  `prepare-local.command` to prepare future copies without `sudo`;
- adds `.gitignore` and `source-archive.command` to keep caches, binaries,
  certificates, and local metadata from being shipped with the source;
- stabilizes the bundle ID as `com.guilhermerozenblat.ClaudeUsageMonitor`;
- hardens the universal release with validation of both architectures, hardened
  runtime in the local build too, a notarized ticket, `stapler validate`, and a
  final Gatekeeper assessment;
- grows the suite to 145 tests.

## 3.5.0 - 2026-07-16

- adds **pace (burn rate) forecasting**: a linear regression over the samples
  from the last 45 minutes projects when the 5-hour window hits 100% ("At the
  current pace: 100% at 14:32"); no projection when the pace is irrelevant, the
  data is stale, or the reset arrives first; a drop in usage within the analysis
  window discards the previous window;
- adds a **24-hour sparkline** to the menu, right below the 5-hour gauge, with the
  pace projection (or the period's peak) beside it;
- adds **threshold profiles** to the Alerts submenu: all (default), from 75% up,
  or critical only (90%+); the ingest keeps recording every threshold and
  switching profiles does not generate retroactive notifications;
- records the **API cost per sample** in history and shows the estimated
  cumulative 24 h and 7-day cost in the session details (a sum of increases,
  resilient to new sessions);
- adds **Export… (CSV)** to the history window
  (`timestamp,five_hour_pct,seven_day_pct,session_cost_usd`);
- replaces the default About panel with an animated authorial experience, with
  Guilherme Rozenblat's signature and a **Made in Brazil** seal;
- adds full Spanish localization and a persistent language selector (automatic,
  English, Portuguese, or Spanish), with immediate switching and an English
  fallback when the macOS language is not supported;
- refines light and dark modes with native translucent materials,
  appearance-specific contrasts, and adaptive palettes across the gauges, charts,
  and About window;
- distinguishes stale limits from an active session with no `rate_limits` and
  swaps the ambiguous warning for short, practical guidance;
- compacts the gauge texts and drops the year from reset times;
- serializes concurrent state and history updates across Claude Code sessions,
  avoiding field loss and contention between pruning and ingestion;
- fixes the history throttle to use the last sample's timestamp, without blocking
  the first collection after a prune;
- fixes parsing of projects with long paths, counters equal to zero, cleanup of
  recovered ingestion errors, and validation of the status line type;
- now reports write errors when exporting history;
- the app re-reads history.jsonl only when the mtime changes;
- grows the suite to 80 tests.

## 3.4.0 - 2026-07-16

- adds **usage history with charts** (24h / 7 days / 30 days / 90 days): the
  ingest writes samples to `history.jsonl` (minimum 60s between samples, 90-day
  retention), and the **Usage history…** window draws the 5-hour and 7-day series
  with an interactive crosshair, a reference line at 90%, a legend, and the
  period's peak; colors validated for color blindness in light and dark modes;
- **English becomes the default language**; Portuguese (pt-BR) is used when it is
  the system's preferred language: UI, notifications, status line, and `--show`;
- **universal binary** (Apple Silicon + Intel) by default in the build;
- support for **Developer ID signing and notarization** in `build-app.command`
  via `CODESIGN_IDENTITY` and `NOTARY_PROFILE` (hardened runtime, notarytool,
  stapler, and a distribution zip);
- grows the suite to 56 tests.

## 3.3.0 - 2026-07-16

- unifies threshold detection in the `state.json` written by ingestion; the app
  now only delivers, eliminating the duplicated logic in UserDefaults;
- notifies thresholds crossed while the app was closed, on reopen: a single
  notification with the highest pending threshold, only if the data is less than
  30 minutes old;
- adds 7-day limit alerts (75%, 90%, and 100%);
- announces **usage freed** once when a window that reached 75% resets;
- adds the **Alerts** submenu with per-type toggles and a 1-hour mute;
- flags **no recent data** when usage has not been updated for 15 minutes with the
  window still active, in the header and the 5-hour gauge;
- replaces the 3-second polling with data-directory observation (DispatchSource)
  plus a 30-second timer solely for clock transitions;
- only re-parses `~/.claude/settings.json` when the mtime changes;
- records `lastIngestErrorAt` when a non-empty payload fails to parse and shows
  **last read failed** in the menu;
- adds **Copy usage summary** and a tooltip with the full summary on the icon;
- unifies the formatting of `--show`, the manual-refresh notification, and the
  copy into a single shared summary;
- swaps the fixed `sleep` in `install.command` for an active wait on the previous
  process exiting;
- grows the suite to 46 tests.

## 3.2.0 - 2026-07-15

- redesigns the menu with native gauges of stable dimensions and a Claude accent;
- adds dynamic icons for healthy, waiting, attention, and error states;
- adds context-window usage, tokens, and percentage remaining;
- adds model, project, session name, effort, thinking, duration, estimated API
  cost, and Claude Code version in a submenu;
- accepts the 5-hour and 7-day windows independently;
- preserves cached values when an optional field drops from the payload;
- detects `disableAllHooks`, which prevents Claude Code from running the status
  line;
- automatically migrates the 3.1 cache without losing the existing limits;
- does not persist `transcript_path` or the project's full path;
- adds AppKit rendering tests and grows the suite to 22 tests;
- documents possibilities and limitations per the official documentation.

## 3.1.0 - 2026-07-15

- adds time remaining to the reset times;
- stops presenting as current a window whose reset has already passed;
- sends a notification with the 5-hour and 7-day values on manual refresh;
- shows the state of the integration and the notification permission in the menu;
- distinguishes missing data from an invalid cache;
- keeps integration errors visible and surfaces action failures to the user;
- validates timestamps and percentages before persisting;
- normalizes the integration path to an absolute executable;
- caps the memory used by the previous status line's output during execution;
- aligns menu, status line, and CLI in hiding values for closed windows;
- grows the suite from 4 to 13 tests.

## 3.0.0 - 2026-07-15

- turns the monitor into a native AppKit app for the macOS menu bar;
- adds an `NSStatusItem` with the 5-hour percentage always visible;
- adds a menu with the 5-hour and 7-day limits, resets, and last update;
- adds native notifications with `UNUserNotificationCenter`;
- adds an option to start with macOS using `SMAppService`;
- replaces the Node runtime with a dependency-free Swift arm64 executable;
- adds an `LSUIElement` bundle, ad hoc signing, and installation in
  `~/Applications`;
- automatically migrates the status line from version 2.0;
- adds separate usage, architecture, security, and release guides.

## 2.0.0 - 2026-07-15

- replaces the `claude.ai` automation with Claude Code's official `rate_limits`
  status line fields;
- removes Playwright, Chromium, and all runtime dependencies;
- removes the LaunchAgent and the fixed-interval polling;
- adds 5-hour and 7-day limits with official reset times;
- displays the reset date and time next to each percentage;
- preserves and restores a preexisting status line;
- adds atomic writing and `0600` permissions for state and configuration;
- adds extraction, validation, and formatting tests for the limits;
- documents migration, architecture, limitations, and the security model.

## 1.0.0 - 2026-07-15

- first release;
- reads `claude.ai/settings/usage` with a persistent Chromium profile;
- notifications at the 25%, 50%, 75%, 90%, and 100% thresholds;
- periodic execution via LaunchAgent.
