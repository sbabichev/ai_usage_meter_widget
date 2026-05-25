# Codex Usage Meter Agent Instructions

This repository contains a Windows PowerShell + WPF tray-style widget for monitoring Codex and Minimax usage limits.

## Project Context

- GitHub: https://github.com/sbabichev/codex_usage_meter
- Main app: `usage-widget.ps1`
- Launcher: `start-usage-widget.cmd`
- Tray/window icon: `assets/codex-usage-meter.ico`
- Icon generator: `tools/create-icon.ps1`
- User-facing docs: `README.md`
- Local state: `usage-widget.state.json` is ignored by git and should remain local.

## Data Sources

- Reads Codex telemetry from `%USERPROFILE%\.codex\sessions\**\*.jsonl`.
- Uses only valid `rate_limits` events where `limit_id=codex` or `limit_id=minimax`.
- Codex: `primary` = current 5-hour session, `secondary` = weekly limit.
- Minimax: `primary` = daily limit, `secondary` = weekly limit.
- Compares the latest usable rate-limit snapshot with the previous distinct snapshot to show last activity impact.
- Reads local `token_count` and `task_started` events to estimate recent turn, latest call, and last-3-minute token usage.

## UI Layout

- Widget height: 420px (increased from 276px to fit MINIMAX section)
- Header shows "Codex PLUS | MINIMAX PRO" with brand-specific colors:
  - Codex: cyan (#6FE8FF)
  - MINIMAX: red-orange (#FF8A3D)
- MINIMAX section in bordered container with orange border
- Two blocks: `CURRENT SESSION` and `WEEKLY LIMIT` for Codex
- One block: `MINIMAX DAILY` for Minimax
- The main usage bar changes color by `used_percent`:
  - `0-49`: lime
  - `50-74`: yellow-green
  - `75-89`: amber
  - `90+`: orange
- Time bars fill left-to-right by elapsed time
- Smart hints at the bottom analyze usage pace vs elapsed time and weekly pace
- Compact last-activity line with token details in tooltip

## Recent Baseline Commits

- `9932f86` Add smart usage hints
- `08b8e7e` Relax stale telemetry warning
- `3d6ddeb` Make time bars fill by elapsed time
- `018b9ec` Improve tray icon and rate limit freshness

## Working Conventions

- Keep changes small and focused.
- Preserve the tray-first behavior unless explicitly asked otherwise.
- Do not commit or track `usage-widget.state.json`.
- Prefer matching the existing PowerShell/WPF style in `usage-widget.ps1`.
- Before changing layout values, inspect the nearby margins, padding, and fixed widget dimensions.
- When changing UI spacing, verify that the fixed widget height still fits the content cleanly.
