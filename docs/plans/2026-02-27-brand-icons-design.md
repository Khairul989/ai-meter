# Design: Brand Icons for Claude & Copilot Tabs

**Date:** 2026-02-27
**Status:** Approved

## Problem

The Claude and Copilot tab buttons currently use generic SF Symbols (`sparkles` and `airplane`). The goal is to replace them with the real brand icons for each provider.

## Approach

Option A — add icons as image assets in `Assets.xcassets`, use SwiftUI `Image("name")` for custom assets and keep `Image(systemName:)` for SF Symbols (Settings gear).

## Asset Setup

1. Create `AIMeter/Resources/Assets.xcassets/claude.imageset/` with:
   - `claude.png` (copied from repo root)
   - `Contents.json` mapping 1x slot
2. Create `AIMeter/Resources/Assets.xcassets/copilot.imageset/` with:
   - `copilot.png` (converted from `copilot.webp` at repo root)
   - `Contents.json` mapping 1x slot
3. Run `xcodegen generate` from `AIMeter/` after adding assets

## Code Changes — `PopoverView.swift`

Introduce a `TabIcon` enum to distinguish between SF Symbol and custom asset:

```swift
enum TabIcon {
    case system(String)
    case asset(String)
}
```

Update `tabButton` signature and image rendering:

```swift
private func tabButton(_ tab: Tab, icon: TabIcon, label: String?) -> some View {
    Button { selectedTab = tab } label: {
        HStack(spacing: 4) {
            switch icon {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: 11))
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            }
            if let label { Text(label).font(.system(size: 11, weight: .medium)) }
        }
        .foregroundColor(selectedTab == tab ? .white : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    .buttonStyle(.plain)
}
```

Update call sites:

```swift
tabButton(.claude,   icon: .asset("claude"),   label: "Claude")
tabButton(.copilot,  icon: .asset("copilot"),  label: "Copilot")
tabButton(.settings, icon: .system("gear"),     label: nil)
```

## Notes

- `.renderingMode(.template)` ensures custom icons inherit `.foregroundColor` tint (active white vs secondary)
- `copilot.webp` must be converted to PNG before adding to asset catalog (Xcode does not support `.webp`)
- `claude.png` has a white stroke/sticker border — may look fine on dark popover background, verify visually after build
- Frame size 13×13 pt matches approximate SF Symbol size at `.system(size: 11)`
