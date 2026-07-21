# AI Usage Meter

A Windows 11 glass-style companion widget for tracking Codex, MiniMax, and Grok subscription limits.

It reads the real `rate_limits` events that Codex writes locally and shows:

- current 5-hour session usage;
- weekly usage;
- optional MiniMax subscription interval and weekly limits from `mmx quota --output json`;
- optional Grok weekly usage from local CLI billing data, with a manual API refresh button;
- last activity impact, combining the latest visible limit movement with local token usage;
- exact reset time;
- time remaining until reset;
- a green usage bar and a subtle time-remaining bar.

This is a small WPF desktop app styled like a widget. It is not a native Windows Widgets board extension.

## Screenshot

Detailed widget in "always on top" mode 
<br>
<img width="360" alt="image" src="https://github.com/user-attachments/assets/86de1bd3-03c8-42fa-a5a7-6e257c0abba3" />

Compact mode fits in taskbar
<br>
<img width="514" alt="image" src="https://github.com/user-attachments/assets/be94b07d-d3dd-46e0-88a5-98dd96c1766e" />

## Requirements

- Windows 11
- Windows PowerShell 5.1 or PowerShell with WPF support
- Codex installed and used at least once, so local session logs exist
- Optional: SSH access to a VPS where `mmx-cli` is installed and already authenticated
- Optional: Grok CLI already installed and authenticated locally

## Run

Double-click:

```text
start-usage-widget.cmd
```

Or run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\usage-widget.ps1
```

## How It Works

Codex writes session events under:

```text
%USERPROFILE%\.codex\sessions\**\*.jsonl
```

The widget scans the newest session files, finds the latest `token_count` event with a `rate_limits` block, and uses:

- `primary` for the current 5-hour session;
- `secondary` for the weekly limit;
- `used_percent` for usage progress;
- `resets_at` and `window_minutes` for reset and time-remaining progress;
- `plan_type` for the wordmark tier.

The widget refreshes every 3 seconds and ignores non-Codex or incomplete rate-limit events.

## Provider Configuration

Providers are enabled in config and shown or hidden in the widget separately:

- `enabled` controls whether a provider is active at all;
- the widget right-click menu controls whether an enabled provider is currently visible;
- the widget refuses to hide the last visible enabled provider.

Example local config:

```json
{
  "hoverOpenDelayMs": 2000,
  "minimax": {
    "enabled": true,
    "source": "token_plan",
    "tokenPlanKey": "YOUR_TOKEN_PLAN_KEY",
    "modelPattern": "general",
    "refreshSeconds": 300,
    "timeoutSeconds": 10
  },
  "grok": {
    "enabled": true,
    "staleAfterSeconds": 900,
    "refreshSeconds": 300,
    "apiTimeoutSeconds": 12
  }
}
```

## MiniMax Limits

MiniMax quota fetching is configured through `usage-widget.config.json`, ignored `usage-widget.local.json`, or environment variables. Prefer `usage-widget.local.json` for machine-specific API tokens, SSH aliases, and secrets.

For `source: "token_plan"`, the widget calls `GET https://api.minimax.io/v1/token_plan/remains` with `Authorization: Bearer ...`, reads `model_remains`, and prefers the `model_name` matching `general` for text-generation quota. It treats `current_interval_usage_count` and `current_weekly_usage_count` as used counts when totals are available; otherwise it derives usage from `current_interval_remaining_percent` and `current_weekly_remaining_percent`. `end_time` and `weekly_end_time` are treated as millisecond reset timestamps. Use another `modelPattern` such as `video` if you want to show a different quota bucket.

## Grok Limits

Grok tracks the same weekly subscription pool that the Grok CLI shows in its usage UI (shared weekly credits, not public API RPS/TPM limits).

Default source is the local CLI billing log:

```text
%USERPROFILE%\.grok\logs\unified.jsonl
```

The widget reads the newest `billing: fetched credits config` entry and maps `creditUsagePercent` to used percent for a single weekly window. When the CLI/API omit `creditUsagePercent` (common at 0% right after a weekly reset), the widget treats that as `0% used` instead of keeping an older period snapshot. It does not invent a fake session bar for Grok.

While Grok is enabled, the widget also does a best-effort automatic live refresh through the installed CLI auth context when local data is missing or stale (`refreshSeconds`, default 300). The full Grok panel still has a small `API` button for an immediate force refresh. This live endpoint is undocumented and may change with CLI updates; auth secrets are never written into checked-in config or `usage-widget.state.json`.

## Controls

- Drag anywhere on the glass panel to move it.
- Double-click the panel to hide it to the tray.
- Right-click the panel to show or hide enabled providers and switch the percent display between `used` and `left`.
- Use the tray icon menu for `Codex Usage Dashboard` and `Exit`.
- Double-click the tray icon to show the widget.

## Files

- `usage-widget.ps1` - WPF widget implementation.
- `start-usage-widget.cmd` - double-click launcher.
- `assets/codex-usage-meter.ico` - Lucide-inspired gauge icon for the tray/window.
- `tools/create-icon.ps1` - regenerates the icon.
- `usage-widget.config.json` - checked-in provider settings and placeholders.
- `usage-widget.local.json` - optional local provider settings, ignored by git.
- `usage-widget.state.json` - local window state, generated automatically and ignored by git.

## Privacy

By default, the app reads local Codex session JSONL files. If MiniMax is enabled, it also runs the configured HTTPS or SSH quota fetch. If Grok is enabled, it reads local Grok CLI billing logs and, when that data is missing or stale, may call the undocumented live billing endpoint using the current CLI auth context.
