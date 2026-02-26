# ClaudeQuota — macOS Menu Bar App + Widgets

**Date:** 2026-02-26
**Status:** Approved

## Overview

A native macOS menu bar app and WidgetKit widgets that display Claude API usage and rate limits. Companion to the existing Claude Code terminal statusline — not a replacement.

## Motivation

- Always-visible monitoring outside the terminal
- Richer UI with progress bars and circular gauges
- Extra credits display (missing from existing tools like TokenEater)
- Fully customizable to personal preferences

## Tech Stack

- **Swift + SwiftUI** — native macOS
- **WidgetKit** — desktop and Notification Center widgets
- **Keychain Services** — read OAuth token from Claude Code's stored credential
- **App Groups** — share data between main app and widget extension

## Architecture

```
┌─────────────────────────────────────┐
│         ClaudeQuota.app             │
│  (LSUIElement = true, no dock icon) │
│                                     │
│  ┌───────────┐   ┌───────────────┐  │
│  │ MenuBar   │   │ UsageService  │  │
│  │ Popover   │◄──│ (timer-based) │  │
│  └───────────┘   └──────┬────────┘  │
│                         │ writes    │
│              ┌──────────▼─────────┐ │
│              │ App Group Defaults │ │
│              └──────────┬─────────┘ │
└─────────────────────────┼───────────┘
                          │ reads
              ┌───────────▼──────────┐
              │  Widget Extension    │
              │  (WidgetKit)         │
              │  - Small: gauges     │
              │  - Medium: bars      │
              └──────────────────────┘
```

- Menu bar app runs as background agent (no dock icon, `LSUIElement = true`)
- `UsageService` polls the API every 60s (configurable)
- Shared data via `UserDefaults` with App Group (`group.com.khairul.claudequota`)
- Widget's `TimelineProvider` reads from App Group defaults
- Main app triggers `WidgetCenter.shared.reloadAllTimelines()` after each fetch

## Data Layer

### Shared Models

```swift
struct UsageData: Codable {
    let fiveHour: RateLimit
    let sevenDay: RateLimit
    let sevenDaySonnet: RateLimit?  // optional, not always present
    let extraCredits: ExtraCredits? // optional, only if enabled
    let fetchedAt: Date
}

struct RateLimit: Codable {
    let utilization: Int      // 0-100
    let resetsAt: Date?
}

struct ExtraCredits: Codable {
    let utilization: Int      // 0-100
    let used: Double
    let limit: Double
}
```

### UsageService

- Singleton in the main app
- Reads OAuth token from Keychain (`Security` framework, `SecItemCopyMatching`)
- Calls `https://api.anthropic.com/api/oauth/usage` on a timer
- Decodes response, writes `UsageData` as JSON to App Group `UserDefaults`
- Triggers widget timeline reload after each update

### KeychainHelper

- Reads Claude Code credential from Keychain (service: `Claude Code-credentials`)
- Parses JSON to extract `claudeAiOauth.accessToken`
- Read-only — never writes to Keychain

## UI Surfaces

### Menu Bar Icon

- Small circular gauge reflecting the highest utilization across all limits
- Color-coded: green (<50%), yellow (50-80%), red (>=80%)

### Menu Bar Popover

Dark themed, card-based layout:

```
┌──────────────────────────────────────┐
│  ◉  ClaudeQuota                      │
│                                      │
│  ⏱  Session                    37%   │
│  5h sliding window      Reset 3h01   │
│  ██████████░░░░░░░░░░░░░░░░░░░░░░░  │
│                                      │
│  📊  Weekly                    54%   │
│  Opus + Sonnet + Haiku  Reset Thu 11am│
│  ██████████████████░░░░░░░░░░░░░░░  │
│                                      │
│  ✦  Sonnet                      3%   │
│  Dedicated limit        Reset Thu 12pm│
│  █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│                                      │
│  💳  Extra Credits             12%   │
│  $2.40 / $20.00                      │
│  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│                                      │
│  Updated less than a minute ago      │
│                          ⚙ Settings  │
└──────────────────────────────────────┘
```

- Each card: icon, label, subtitle, percentage, reset time (Malaysia TZ), progress bar
- Progress bar colors: green <50%, yellow 50-80%, red >=80%
- Extra Credits card: only shown when enabled, displays used/limit dollar amounts
- Sonnet card: only shown when `seven_day_sonnet` is present in API response
- Footer: last updated timestamp + settings gear

### Small Widget

Single most-urgent metric with circular gauge:

```
┌─────────────────┐
│  ◉ ClaudeQuota  │
│                  │
│    ╭───╮        │
│    │37%│        │
│    ╰───╯        │
│   Session        │
│   Reset 3h01     │
└─────────────────┘
```

- Shows whichever limit has the highest utilization
- Circular progress ring, color-coded
- Tapping opens the menu bar app

### Medium Widget

All metrics with circular gauges side by side:

```
┌──────────────────────────────────────┐
│  ◉ ClaudeQuota                       │
│                                      │
│   ╭───╮     ╭───╮     ╭───╮         │
│   │37%│     │54%│     │ 3%│         │
│   ╰───╯     ╰───╯     ╰───╯         │
│  Session    Weekly    Sonnet         │
│   3h01    Thu 11am   Thu 12pm        │
│                                      │
│  Updated < 1 min ago                 │
└──────────────────────────────────────┘
```

- 3 circular gauges (Session, Weekly, Sonnet)
- If Extra Credits enabled, 4 gauges (slightly smaller)
- Each gauge color-coded independently
- Reset times in Malaysia TZ below each gauge

## Settings (v1)

- **Refresh interval**: 30s / 60s (default) / 120s
- **Timezone**: default Malaysia UTC+8, dropdown of common timezones
- **Launch at login**: toggle via `SMAppService.mainApp`
- **Quit**: quit button

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Keychain read fails | "No token found" state with hint to sign into Claude Code |
| API call fails | Show last successful data with "stale" indicator |
| No network | Same as API fail — show cached data |

## App Identity

- **Bundle ID**: `com.khairul.claudequota`
- **Widget extension**: `com.khairul.claudequota.widget`
- **App Group**: `group.com.khairul.claudequota`
- **LSUIElement**: `true` (no dock icon)

## Color Thresholds

Consistent across all surfaces:

| Range | Color |
|-------|-------|
| 0-49% | Green |
| 50-79% | Yellow |
| 80-100% | Red |

## Out of Scope (v1)

- Notifications/alerts (planned for v2)
- Historical usage charts
- Multiple account support
- Context window usage (stays in terminal statusline only)

## API Reference

**Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`

**Headers:**
- `Authorization: Bearer <token>`
- `anthropic-beta: oauth-2025-04-20`

**Response fields used:**
- `five_hour.utilization`, `five_hour.resets_at`
- `seven_day.utilization`, `seven_day.resets_at`
- `seven_day_sonnet.utilization`, `seven_day_sonnet.resets_at`
- `extra_usage.is_enabled`, `extra_usage.monthly_limit`, `extra_usage.used_credits`, `extra_usage.utilization`
