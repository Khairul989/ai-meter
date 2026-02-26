# Tabbed UI Design

**Date:** 2026-02-26
**Version target:** v1.3.0

## Goal

Replace the vertical stacked provider sections in PopoverView with a tabbed layout so adding new providers (OpenAI, Codex, etc.) adds a tab rather than growing the popover vertically.

## Tab Structure

Three tabs in a fixed top tab bar:

| Tab | Icon | Label | Content |
|-----|------|-------|---------|
| Claude | `sparkles` | Claude | Existing metric cards (Session, Weekly, Sonnet, Credits) |
| Copilot | `airplane` | Copilot | Existing quota rows + reset date |
| Settings | `gear` | *(none)* | InlineSettingsView (unchanged) |

Footer gear button removed — Settings is now a tab.

## Visual Design

Custom `HStack` tab bar (not native TabView — too iOS-like for a compact popover).

- **Selected tab:** icon + label, `Color.white.opacity(0.1)` pill background, white text
- **Unselected tab:** icon + label, `.secondary` color, no background
- **Settings tab:** icon only, no label, sits right-aligned in the same HStack
- Tab bar sits between the global header and the content area

## Layout

```
┌─────────────────────────────────┐
│ ● AI Meter                      │  global header (unchanged)
├─────────────────────────────────┤
│  [✦ Claude]  [✈ Copilot]  [⚙]  │  custom tab bar
├─────────────────────────────────┤
│                                 │
│   tab content                   │
│                                 │
├─────────────────────────────────┤
│ Updated 2m ago  (stale)         │  global footer, no gear button
└─────────────────────────────────┘
```

## Architecture

**Only `PopoverView.swift` changes** — pure UI refactor. No service, model, or data changes.

### New types

```swift
enum Tab { case claude, copilot, settings }
```

### PopoverView changes

- `@State var showSettings: Bool` → `@State var selectedTab: Tab = .claude`
- Tab bar replaces the footer gear button
- Content area switches on `selectedTab`
- Footer shows provider fetch time for active tab (hidden on Settings tab)

### Extracted views

- `ClaudeTabView` — contains existing `claudeSection` logic
- `CopilotTabView` — contains existing `copilotSection` logic
- `InlineSettingsView` — unchanged, used directly as Settings tab content

### Footer update text

- Claude tab: `service.usageData.fetchedAt`
- Copilot tab: `copilotService.copilotData.fetchedAt`
- Settings tab: hidden

## Out of Scope

- Per-tab notification badges
- Tab reordering
- Hiding/disabling tabs for disconnected providers (future)
