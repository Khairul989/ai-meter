# Live Countdown Timer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Display a live ticking countdown for the Session (5h) card that updates every second without polling the API.

**Architecture:** Use SwiftUI's `TimelineView(.periodic(from:by:))` to re-render only the countdown text every second. Update `ResetTimeFormatter` to accept a `Date` parameter instead of always using `Date()`. No changes to service layer or data models needed.

**Tech Stack:** SwiftUI, TimelineView, ResetTimeFormatter

---

### Task 1: Update ResetTimeFormatter to accept a reference date

**Files:**
- Modify: `AIMeter/Sources/Shared/ResetTimeFormatter.swift`

**Step 1: Update the `format` function signature and countdown format**

Replace the current implementation with:

```swift
import Foundation

enum ResetTimeFormatter {
    /// Format a reset date for display, relative to a reference date.
    /// Countdown format: "3h 1m" for 5-hour resets.
    /// Day/time format: "Thu 11am" for 7-day resets.
    static func format(_ date: Date?, style: Style, timeZone: TimeZone = .current, now: Date = Date()) -> String? {
        guard let date else { return nil }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = timeZone

        switch style {
        case .countdown:
            let diff = calendar.dateComponents([.hour, .minute], from: now, to: date)
            guard let h = diff.hour, let m = diff.minute, h >= 0, m >= 0 else { return nil }
            return "\(h)h \(m)m"
        case .dayTime:
            formatter.dateFormat = "EEE h:mma"
            return formatter.string(from: date).lowercased()
        }
    }

    enum Style {
        case countdown  // "3h 1m"
        case dayTime    // "thu 11:00am"
    }
}
```

Key changes:
- Added `now: Date = Date()` parameter (defaults to `Date()` so existing callers still work)
- Changed countdown format from `"%dh%02d"` → `"\(h)h \(m)m"` (e.g. "3h 1m" not "3h01")

**Step 2: Build to verify no compile errors**

```bash
cd AIMeter && xcodebuild -scheme AIMeter -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` (existing callers use default `now:` so no breakage)

---

### Task 2: Wrap Session countdown in TimelineView

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift` (ClaudeTabView, lines ~183–219)

**Step 1: Update ClaudeTabView to use TimelineView for Session card**

Replace the `ClaudeTabView` body:

```swift
struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    let timeZone: TimeZone

    var body: some View {
        let data = service.usageData
        VStack(spacing: 0) {
            // Session card: live countdown ticking every second
            TimelineView(.periodic(from: .now, by: 1)) { context in
                UsageCardView(
                    icon: "timer",
                    title: "Session",
                    subtitle: "5h sliding window",
                    percentage: data.fiveHour.utilization,
                    resetText: ResetTimeFormatter.format(
                        data.fiveHour.resetsAt,
                        style: .countdown,
                        timeZone: timeZone,
                        now: context.date
                    )
                )
            }
            UsageCardView(
                icon: "chart.bar.fill",
                title: "Weekly",
                subtitle: "Opus + Sonnet + Haiku",
                percentage: data.sevenDay.utilization,
                resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: timeZone)
            )
            if let sonnet = data.sevenDaySonnet {
                UsageCardView(
                    icon: "sparkles",
                    title: "Sonnet",
                    subtitle: "Dedicated limit",
                    percentage: sonnet.utilization,
                    resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: timeZone)
                )
            }
            if let credits = data.extraCredits {
                UsageCardView(
                    icon: "creditcard.fill",
                    title: "Extra Credits",
                    subtitle: String(format: "$%.2f / $%.2f", credits.used / 100, credits.limit / 100),
                    percentage: credits.utilization,
                    resetText: nil
                )
            }
        }
    }
}
```

**Step 2: Build and verify**

```bash
cd AIMeter && xcodebuild -scheme AIMeter -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 3: Run the app and verify the Session card countdown ticks every second**

```bash
open /path/to/AIMeter.app
```

Observe: Session card shows "3h 1m" style, updates each second. Weekly/Sonnet show day+time unchanged.

**Step 4: Commit**

```bash
git add AIMeter/Sources/Shared/ResetTimeFormatter.swift AIMeter/Sources/App/PopoverView.swift
git commit -m "feat: live countdown timer for Session card (v1.6.0)"
```
