# User Guide

## First launch

Claude Usage Monitor is a menu bar app (`LSUIElement`). It has no main window and
doesn't appear in the Dock.

After installing:

1. open `~/Applications/Claude Usage Monitor.app`;
2. allow notifications when macOS asks;
3. restart Claude Code if it was already running;
4. accept the workspace trust prompt;
5. send a message and wait for the response.

A health icon appears in the menu bar next to the 5-hour window percentage. A
checkmark means everything works; a clock means it's waiting; an exclamation mark
means attention is needed; an X means an integration or cache error.

## Plans and what's shown

The monitor shows whatever the Claude Code status line sends, and the status line
only reports limits for Claude.ai subscriptions.

| Plan | 5 hours | 7 days |
| --- | --- | --- |
| Pro, Max, Team, Enterprise (per seat) | yes | yes |
| API key, Console, Bedrock, Vertex, Foundry | no | no |
| Enterprise (usage-based) | no | no |
| Free | no Claude Code access | none |

Token-based billing has no usage windows: consumption is billed per token. In
those cases the app says so instead of waiting for data that will never arrive.

Max plans also have a weekly Sonnet limit and a per-model Opus limit. Neither
appears in the status line: only Claude Code's `/usage` command shows them. You
can hit one of these limits without the monitor showing 100%.

## App panel

### Claude account

The header shows the email of the account signed in to Claude Code. The session is
confirmed locally via `claude auth status`; the email is only used when that
command reports an active login. After you sign out, stale profile metadata is
ignored. API keys appear without an OAuth account email, and the monitor never
reads or stores any token.

### `5-hour limit`

Shows the percentage consumed in the current 5-hour window. The detail line shows
the date, local time, and time remaining until the reset. The gauge uses the
Claude accent color under normal usage, turns orange after 75%, and red after 90%.
Once the window ends, the old percentage is replaced by `Ended`.

### `7-day limit`

Shows the weekly all-models limit and its next reset. Not every plan gets this
window; when it's missing, the panel shows `not sent for this plan` and the chart
hides the series.

This is the overall weekly limit. The weekly Sonnet limit on Max plans and the
per-model Opus limit aren't reported by the status line and don't appear here.

### `Session context`

Shows the percentage taken up by the current conversation, tokens currently in
context, maximum size, and percentage free. Context isn't a plan limit: it can
drop after `/compact` and starts over in a new session.

### `Session details`

The grid shows only officially provided fields: model, short project name, session
name, reasoning effort, thinking, duration, estimated API cost, and Claude Code
version. The cost is a local estimate and doesn't reflect billing for Pro or Max
subscriptions.

### `Updated`

The time the app received the last `rate_limits`, plus the cache age. This is not
the time the menu was opened.

### `Integration`

Shows whether `~/.claude/settings.json` points to the installed executable. Fix
the `needs repair` state with **Reconfigure Claude Code**. The `blocked by
disableAllHooks` state requires changing that option in Claude Code's settings.

### `Notifications`

Shows whether alerts are enabled, awaiting permission, or blocked in System
Settings.

### `Refresh display`

Immediately re-reads `state.json` and sends a notification with the latest valid
5-hour, 7-day, and context values. Ended windows appear as `waiting for new
window`. This action doesn't query the network. To get a fresh value from the
service, send a message in Claude Code. It's rarely needed: the app watches the
state file and updates itself whenever ingestion writes new data.

### `Copy usage summary`

In the **•••** menu. Copies the compact summary of 5-hour, 7-day, and context
values to the clipboard, the same text as the icon tooltip.

### `Usage history…`

Opens a window with the chart of the 5-hour and 7-day limits. The ranges are the
current **5-hour window** and spans of 24 hours, 7, 30, or 90 days. Hover over the
chart to read the values at each point; the dashed line marks 90%.

The **5-hour window** is the current period up to the reset, not the last 5 elapsed
hours: the axis runs from the start of the window to the reset time, with "now"
marked. That way you can read how much you've spent and how much time is left. A
rolling "last 5 hours" range would cross the reset and draw a drop from 90% to 0%
that looks like usage plummeting, when the window is just restarting.

The vertical axis is always 0-100% of **your** plan's limit and never rescales to
the data. Anthropic only publishes relative multiples between plans (Max 5x = "5
times Pro"), never absolute numbers, so the percentage is the only measure that
means the same thing on any plan. The empty space above the line is your remaining
headroom.

On plans that don't report the weekly limit, the 7-day series appears in neither
the chart nor the legend. The data is collected locally by ingestion (one sample
per minute at most, with 90-day retention) and can be erased by removing
`history.jsonl` in the data folder. Gaps in the chart mark periods with no Claude
Code use; the app doesn't invent points where there was no data. The **Export…**
button saves the full history as CSV
(`timestamp,five_hour_pct,seven_day_pct,session_cost_usd`).

### Settings > `Alerts`

Turns the 5-hour limit, 7-day limit, and window-restarted alerts on and off. Under
**Notify at thresholds** you choose the profile: all thresholds (default), from 75%
on, or critical only (90%+). The change applies to future notifications, with no
retroactive alerts. **Mute alerts for 1 hour** holds everything temporarily; the
item shows the time the mute ends.

### Trend line

Just below the 5-hour gauge there's a mini-chart of the current window. When usage
is climbing steadily, the projection **"At the current pace: 100% at HH:mm"**
appears next to it, computed locally over the last 45 minutes of samples. With no
meaningful pace, it shows the window's peak.

### Estimated cost per period

In the session details, besides the current session's cost, the app shows the
estimated API cost over the last 24 hours and the last 7 days, derived from the
local history. It's an estimate: it doesn't reflect billing for Pro/Max plans.

### `Reconfigure Claude Code`

Rewrites the `statusLine` key in `~/.claude/settings.json` to point to the app's
current location. Use it after moving or reinstalling the bundle.

### `Open at login`

Registers or removes the app as a login item using the macOS `SMAppService` API.
The state can also be reviewed in System Settings.

### `Open data folder`

Opens `~/Library/Application Support/ClaudeUsageMonitor`, which holds the state and
the backup of the previous status line.

### `Language`

By default, **Automatic (System)** follows the macOS preferred-languages list.
English, Portuguese (Brazil), and Spanish are supported; if none is configured, the
app uses English. You can also pick **English**, **Português (Brasil)**, or
**Español** manually. The change is immediate and is saved for future launches.

### Where the usage went

Below the history chart, a stacked bar splits the period's usage across the models
that responded, with each model's name written inside its slice. Below it, each
model has its own bar with its name and percentage. The stacked bar compares the
models against each other; the individual bars compare each model against the whole
period. They only appear when two or more models consumed usage in the chosen
period.

The Claude Code status line doesn't report per-model limits, only the total and
which model was active. So this is an attribution, not a reading: whatever the
window rises between two measurements counts toward the model in the more recent
measurement. It answers "did I spend on Opus or on Sonnet?", not to audit billing.

### ⌥⌘U shortcut

In **Settings › General › Shortcut**, off by default. When on, it opens the panel
over any app in front, without asking for Accessibility permission. If another app
already uses ⌥⌘U, the app warns you and the option won't enable: whoever registered
it first keeps the combination.

### `About`

In the panel's ⓘ button. It follows the macOS About panel layout: icon, name,
version, a one-line description, and the 🇧🇷 **Developed by Guilherme Rozenblat**
credit. The icon has a ring of twelve dashes that light up in sequence, and the
blocks rise as it opens. Both animations stop when **Reduce motion** is enabled in
the macOS Accessibility settings. Translucent materials and colors adapt to light
and dark mode.

### `Quit`

Closes only the menu interface. Claude Code can still update the cache by calling
the `--ingest-statusline` mode, and crossed thresholds are recorded: when you
reopen the app, the highest pending threshold is notified if the data is still
recent.

## Notifications

Alerts are sent at the 25%, 50%, 75%, 90%, and 100% thresholds of the 5-hour window
and at the 75%, 90%, and 100% thresholds of the 7-day window.

- Each threshold is notified once per window.
- When the reset timestamp changes, the thresholds are released again.
- Thresholds crossed while the app was closed are recorded by ingestion; on open,
  the app notifies only the highest pending threshold, and only if the data is less
  than 30 minutes old.
- When a window that reached 75% or more restarts, the app sends **usage freed**
  once, up to 30 minutes after the reset.

In the **Alerts** tab of Settings (⌘,) you can turn off the 5-hour, 7-day, and
window-restarted alerts, plus **Mute alerts for 1 hour**. When the mute ends,
alerts that are still recent are delivered; older ones are discarded.

Permissions can be changed in **System Settings > Notifications > Claude Usage
Monitor**.

## Common states

### `waiting for data`

The app hasn't yet received a Claude Code response with `rate_limits`.

### `7 days: unavailable`

The current response doesn't include the weekly window. This can depend on the
subscription, the authentication, or the field's availability in Claude Code.

### Stale percentage

The value is cached. Usage from other Claude surfaces shows up in the next response
received by Claude Code.

### `invalid cache`

The `state.json` file exists but doesn't contain a valid state. Use **Reconfigure
Claude Code** and send a new message. If it persists, quit the app, remove only
`state.json`, and open the app again.

## Updating

Run `install.command` again. The installer quits the current instance, replaces the
bundle, preserves the state, and reopens the app.

## Removal

Run `uninstall.command`. The process:

1. restores the previous status line;
2. quits the app;
3. removes the bundle from `~/Applications`;
4. deletes the monitor's data directory.
