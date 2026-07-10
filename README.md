# codex-claude-usage-watch

Live, at-a-glance view of **how much usage quota you have left** in both
**OpenAI Codex** and **Claude Code** — their 5‑hour session windows and weekly
windows — in your terminal or as a translucent floating HUD on your macOS
desktop.

```
Usage windows  |  7/10/2026, 10:22:01 AM

Codex   | plan=pro
  5h  [█████░░░░░░░]  left   42%  ↻ Jul 10, 11:02 AM (        40m)
  7d  [███████████░]  left   91%  ↻ Jul 17, 06:02 AM ( 6d 19h 40m)

Claude  | plan=max tier=default_claude_max_20x
  5h  [█████████░░░]  left   75%  ↻ Jul 10, 11:00 AM (        37m)
  7d  [███████████░]  left   95%  ↻ Jul 12, 11:00 PM ( 2d 12h 37m)
```

The bar is a **fuel gauge**: full = plenty left, draining as you consume. `↻`
is when the window resets, with time remaining.

---

## What's in here

| Command | What it does |
| --- | --- |
| **`usage-watch`** | Combined view — Codex **and** Claude side by side. The one you'll use. |
| **`usage-hud`** | macOS floating HUD (translucent, always‑on‑top) that renders `usage-watch`. |
| `claude-usage-watch` | Claude‑only CLI. |
| `codex-usage-watch` | Codex‑only CLI. |

All are self‑contained (`usage-watch`/`*-usage-watch` are single Node scripts,
`usage-hud` is a single Swift/AppKit file — no npm install, no frameworks).

---

## Requirements

- **macOS** (uses the login keychain for Claude auth and the ChatGPT app for Codex).
- **Node.js** (any recent version — uses the built‑in `fetch`).
- For the HUD: **Xcode Command Line Tools** (`swiftc`) — `xcode-select --install`.
- **Codex** data needs the ChatGPT desktop app installed (it ships the `codex`
  binary that exposes a local rate‑limit API). Override its path with `CODEX_BIN`.
- **Claude** data needs the Claude Code **CLI** logged in once (see below).

## Install

```bash
git clone https://github.com/brightac/codex-claude-usage-watch
cd codex-claude-usage-watch
./install.sh            # installs CLIs + builds & autostarts the desktop HUD
# ./install.sh --no-hud # CLIs only, no HUD / LaunchAgent
```

Make sure `~/.local/bin` is on your `PATH`. To remove everything:
`./install.sh --uninstall`.

## Usage

```bash
usage-watch            # full view, refreshes every 300s in place (no scroll)
usage-watch --once     # single snapshot
usage-watch --line     # one line:  Codex 5h 42% 7d 91%  ‖  Claude 5h 75% 7d 95%
usage-watch -i 60      # custom refresh interval (seconds)
```

`--line` is handy for a tmux status bar or shell prompt:

```tmux
set -g status-right "#(usage-watch --line) | %H:%M"
set -g status-interval 300
```

### The desktop HUD

After `install.sh`, a translucent HUD floats on your desktop and starts at login.

Two **skins**, toggled with **⌘T** (your choice is remembered):

- **text** — the aligned `usage-watch --once` output (default).
- **dial** — circular gauges: an outer colored ring for remaining quota
  (green / amber / red), a shrinking pomodoro wedge for time‑until‑reset, and a
  second hand that sweeps once a minute so the clock visibly turns.

Controls:

- **Drag** anywhere to move (position is remembered).
- **⌘T** switch skin · **⌘R** force refresh · **⌘Q** dismiss (returns at next login).
- Dark, semi‑transparent panel — readable on any wallpaper.

Tweak look/behavior at the top of [`bin/usage-hud.swift`](bin/usage-hud.swift)
(`REFRESH_SECONDS`, `FONT_SIZE`, tint alpha, dial sizes) then re‑run `./install.sh`.

> **First run:** the Claude row shows `not logged in` until you log the CLI in
> once with `claude auth login` (see below). Codex works immediately.

---

## Authentication & how it works

Neither tool stores any secret — tokens are read at runtime from where each
vendor already keeps them.

**Codex.** Spawns the ChatGPT app's `codex app-server` and calls its local
JSON‑RPC `account/rateLimits/read`. No network call of our own; nothing to log in to.

**Claude.** Calls `GET /api/oauth/usage` (the same endpoint the in‑session
`/usage` command uses), authenticating with the Claude Code CLI's keychain
entry (`Claude Code-credentials` → `claudeAiOauth`). The token is auto‑refreshed
when expired, provided that entry has a refresh token.

> **Logging in (important):** the tool needs a non‑expired `claudeAiOauth` entry
> **with a refresh token** in the keychain. Only the interactive browser login
> writes that:
> ```bash
> claude auth login          # opens a browser; writes a refreshable keychain token
> ```
> ⚠️ **Do _not_ use `claude setup-token`** — despite the name, it only mints a
> long‑lived `CLAUDE_CODE_OAUTH_TOKEN` for headless/CI use and does **not** touch
> the `claudeAiOauth` keychain entry this tool reads. If you only ever used the
> Claude **desktop app**, the CLI keychain entry is stale/absent until you run
> `claude auth login`. This doesn't disturb any running Claude session.

### Rate limiting & caching

Claude's usage endpoint is aggressively rate‑limited (and the running desktop
app may poll it too), so requests can return **HTTP 429**. To stay useful, every
successful reading is cached to `~/.cache/usage-watch/`. On a throttled refresh
the last good values are shown with a `(cached 3m ago)` marker instead of
`unavailable`. The default 300s interval keeps well clear of the limit.

---

## Notes

- Weekly Opus / Sonnet sub‑limits are shown when the API returns them.
- Times are shown in your local timezone.
- Linux/Windows aren't supported (keychain + ChatGPT‑app specifics are macOS‑only).

## License

MIT © brightac
