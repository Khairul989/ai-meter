# Notifications Design

**Date:** 2026-02-26
**Version target:** v1.2.0

## Goal

Alert the user when any monitored AI quota metric crosses a configurable warning or critical utilization threshold, using native macOS local notifications.

## Approach

Use `UNUserNotificationCenter` (UserNotifications framework) for native macOS local notifications. No third-party dependencies. Permission requested lazily when the user enables notifications in settings.

## Threshold Crossing Detection

A `NotificationTracker` tracks the last-notified level per metric key. A notification fires only when the level *increases* (none → warning → critical). When utilization drops back below the warning threshold, the tracker resets so future crossings notify again.

**Metric keys:**
- `claude.session`
- `claude.weekly`
- `claude.sonnet`
- `claude.credits`
- `copilot.premium`

**Notification levels:**
```
none → (crosses warning%) → warning → (crosses critical%) → critical
                                  ↑ resets when drops below warning
```

## Settings

Added to `InlineSettingsView`:

```
Notifications
  [ ] Enable notifications              ← toggle; triggers permission request on first enable
  Warning threshold:  [50%] [75%] [80%] ← segmented picker, default 80
  Critical threshold: [85%] [90%] [95%] ← segmented picker, default 90
```

`@AppStorage` keys:
- `notificationsEnabled` (Bool, default false)
- `notifyWarning` (Int, default 80)
- `notifyCritical` (Int, default 90)

## Notification Content

**Warning level:**
- Title: `"Claude Weekly at 85%"`
- Body: `"Resets in 3d 14h"` (or remaining count for Copilot)

**Critical level:**
- Title: `"⚠️ Copilot Premium at 92%"`
- Body: `"42 interactions remaining"`

Tapping the notification brings the app to focus (no custom actions needed).

## Data Flow

1. `UsageService.fetch()` or `CopilotService.fetch()` completes successfully
2. Service calls `NotificationManager.shared.check(metrics:)`
3. `NotificationManager` reads `notificationsEnabled`, `notifyWarning`, `notifyCritical` from `UserDefaults`
4. For each metric, compares utilization to thresholds and current tracker state
5. If crossing detected → fires `UNUserNotificationCenter` local notification
6. Updates tracker state (persisted as JSON in `@AppStorage("notificationTracker")`)

## New Files

- `AIMeter/Sources/Shared/NotificationManager.swift` — all threshold logic and UNUserNotificationCenter calls

## Modified Files

- `AIMeter/Sources/App/UsageService.swift` — call `NotificationManager.shared.check(...)` after successful fetch
- `AIMeter/Sources/App/CopilotService.swift` — same
- `AIMeter/Sources/App/PopoverView.swift` — add notifications section to `InlineSettingsView`

## Out of Scope

- Notification actions/buttons
- Sound customization
- Per-metric toggles
- Historical notification log
