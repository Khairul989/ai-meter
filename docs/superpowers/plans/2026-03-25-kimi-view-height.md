# Kimi View Height and Window Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update Kimi login window height to 640px and improve window duration display with hours conversion and reset time visibility.

**Architecture:** Simple Swift/SwiftUI modifications to existing KimiAuthManager and KimiTabView. No new files, just targeted changes to align with existing patterns in the codebase.

**Tech Stack:** Swift, SwiftUI, AppKit (NSWindow)

**Spec Reference:** `docs/superpowers/specs/2026-03-25-kimi-view-height-design.md`

---

## Files Overview

| File | Purpose | Changes |
|------|---------|---------|
| `AIMeter/Sources/App/KimiAuthManager.swift` | Manages Kimi login window | Line 90: height 500 → 640 |
| `AIMeter/Sources/App/KimiTabView.swift` | Displays Kimi usage data | Lines 142-183: add window duration formatting and reset time display |

---

### Task 1: Update Login Window Height

**Files:**
- Modify: `AIMeter/Sources/App/KimiAuthManager.swift:90`

- [ ] **Step 1: Change window height from 500 to 640**

```swift
let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
```

- [ ] **Step 2: Build to verify no syntax errors**

Run: `cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate && xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add AIMeter/Sources/App/KimiAuthManager.swift
git commit -m "fix: increase Kimi login window height to 640px to match other auth windows"
```

---

### Task 2: Add Window Duration Helper Function

**Files:**
- Modify: `AIMeter/Sources/App/KimiTabView.swift` (add after the `shortDateLabel` function, around line 201)

- [ ] **Step 1: Add helper function to format window duration**

Add this private function after the closing brace of `shortDateLabel`:

```swift
private func windowDurationText(_ duration: Int) -> String {
    if duration == 300 {
        return "5-hour Window"
    }
    return "\(duration)-minute Window"
}
```

- [ ] **Step 2: Build to verify no syntax errors**

Run: `cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate && xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add AIMeter/Sources/App/KimiTabView.swift
git commit -m "feat: add helper to convert 300-minute window to 5-hour display"
```

---

### Task 3: Update Window Card to Show Reset Time

**Files:**
- Modify: `AIMeter/Sources/App/KimiTabView.swift:142-183` (limitWindowCard function)

- [ ] **Step 1: Add reset time formatting helper**

Add this private function after `windowDurationText`:

```swift
private func formatResetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
```

- [ ] **Step 2: Update limitWindowCard header to show reset time**

Replace the header HStack in `limitWindowCard` (lines 144-151):

```swift
HStack {
    Image(systemName: "clock.fill")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    Text(windowDurationText(limit.window.duration))
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
    Spacer()
    if let resetTime = limit.detail.resetTime {
        Text("Resets: \(formatResetTime(resetTime))")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 3: Build to verify no syntax errors**

Run: `cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate && xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add AIMeter/Sources/App/KimiTabView.swift
git commit -m "feat: show reset time in Kimi window cards and convert 300min to 5h"
```

---

## Testing

### Manual Testing Checklist

After all tasks complete, verify:

- [ ] Kimi login window opens at 640px height (same as Claude/Codex)
- [ ] Window cards show "5-hour Window" for 300-minute duration
- [ ] Window cards show "{N}-minute Window" for other durations
- [ ] Reset time displays when available (check API response has resetTime)
- [ ] Reset time hidden when not available
- [ ] Build completes without errors

### Testing Approach

These are UI changes that are best tested manually by:
1. Running the app and opening Kimi login window
2. Authenticating and viewing the Kimi usage tab
3. Verifying the window labels and reset times display correctly

No automated tests needed for these cosmetic changes.

---

## Completion Criteria

- [ ] All 3 tasks complete
- [ ] All builds pass
- [ ] 3 commits made (one per task)
- [ ] Manual testing verified
