# AIMeter

A native macOS menu bar app and WidgetKit widgets for monitoring Claude API usage and rate limits.

---

## Overview

AIMeter sits in your menu bar and shows your Claude API usage at a glance — session (5h), weekly (7d), Sonnet-specific, and extra credits. It reads your existing Claude Code authentication token from the macOS Keychain, so there is no separate login required.

---

## Features

- Menu bar icon with a color-coded circular gauge reflecting your highest active utilization
- Popover with per-limit progress bars, reset times, and extra credits balance
- WidgetKit extension with small (single gauge) and medium (all gauges) widget sizes
- Automatic API polling with a configurable refresh interval (30s, 60s, 120s)
- Color thresholds: green below 50%, yellow 50-79%, red 80% and above
- Reset times displayed in your configured timezone
- No Dock icon — runs as a background agent (`LSUIElement`)
- Reads OAuth token from the macOS Keychain (Claude Code credentials) — read-only, no writes
- Graceful error states: stale-data indicator when the API is unreachable, hint when no token is found
- Launch at login via `SMAppService`

---

## Screenshots

Coming soon.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Claude Code installed and authenticated (provides the Keychain credential)

---

## Installation / Getting Started

**1. Clone the repository**

```bash
git clone https://github.com/Khairul989/ai-meter.git
cd ai-meter
```

**2. Install XcodeGen**

```bash
brew install xcodegen
```

**3. Generate the Xcode project**

```bash
cd AIMeter
xcodegen generate
```

**4. Open in Xcode**

```bash
open AIMeter.xcodeproj
```

**5. Set your Development Team**

In Xcode, select the `AIMeter` target, go to **Signing & Capabilities**, and set your Development Team. Repeat for the `AIMeterWidget` target.

**6. Build and run**

Select the **AIMeter** scheme (not AIMeterWidget) and press **Run** (Cmd+R). The app will appear in your menu bar.

---

## Configuration

Open the popover from the menu bar icon and click the settings gear in the bottom-right corner.

| Setting | Options | Default |
|---------|---------|---------|
| Refresh interval | 30s, 60s, 120s | 60s |
| Timezone | Common timezone list | System timezone |
| Launch at login | On / Off | Off |

---

## How It Works

```
AIMeter.app (LSUIElement — no Dock icon)
  |
  |-- UsageService (timer-based polling)
  |     Reads OAuth token from Keychain (Claude Code-credentials)
  |     Calls https://api.anthropic.com/api/oauth/usage
  |     Writes UsageData JSON to App Group UserDefaults
  |     Triggers WidgetCenter.shared.reloadAllTimelines()
  |
  |-- MenuBar Popover (SwiftUI)
        Reads from UsageService @Published state

App Group: group.com.khairul.aimeter
  |
  +-- AIMeterWidget extension (WidgetKit)
        TimelineProvider reads UsageData from App Group UserDefaults
        Small widget: highest-utilization gauge
        Medium widget: all gauges side by side
```

- **Authentication** — `KeychainHelper` uses `SecItemCopyMatching` to read the token stored by Claude Code. It is strictly read-only.
- **API** — `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` header.
- **Shared state** — `UserDefaults(suiteName:)` with an App Group bridges the main app and the widget extension. The widget never makes its own network requests.

---

## Project Structure

```
claude-usage-quota/
├── AIMeter/
│   ├── project.yml                  # XcodeGen configuration
│   ├── Resources/
│   │   ├── Info.plist
│   │   ├── WidgetInfo.plist
│   │   ├── AIMeter.entitlements
│   │   └── AIMeterWidget.entitlements
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── AIMeterApp.swift     # App entry point, menu bar setup
│   │   │   ├── PopoverView.swift    # Main popover UI
│   │   │   ├── UsageCardView.swift  # Per-limit card component
│   │   │   ├── UsageService.swift   # API polling and state
│   │   │   └── SettingsView.swift   # Settings panel
│   │   ├── Shared/
│   │   │   ├── UsageData.swift      # Shared Codable models
│   │   │   ├── APIClient.swift      # HTTP layer
│   │   │   ├── KeychainHelper.swift # Keychain token reader
│   │   │   ├── SharedDefaults.swift # App Group UserDefaults wrapper
│   │   │   ├── CircularGaugeView.swift
│   │   │   ├── ProgressBarView.swift
│   │   │   ├── ResetTimeFormatter.swift
│   │   │   └── UsageColor.swift     # Color threshold logic
│   │   └── Widget/
│   │       ├── AIMeterWidget.swift  # WidgetKit entry, TimelineProvider
│   │       ├── SmallWidgetView.swift
│   │       └── MediumWidgetView.swift
│   └── Tests/
│       ├── APIClientTests.swift
│       ├── KeychainHelperTests.swift
│       └── UsageDataTests.swift
├── docs/
│   └── plans/
├── CHANGELOG.md
└── README.md
```

---

## Roadmap

- **Notifications** — alert when utilization crosses configurable thresholds (planned for v2)
- **Additional providers** — GitHub Copilot, OpenAI Codex usage monitoring
- **Historical charts** — usage trends over time
- **Multiple accounts** — support for switching between Claude accounts

---

## License

MIT License

Copyright (c) 2026 Khairul

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
