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

### Quota Popover

| Claude | Copilot |
|:---:|:---:|
| <img src="docs/screenshots/claude_quota.jpeg" width="320" alt="Claude quota popover"> | <img src="docs/screenshots/copilot_quota.jpeg" width="320" alt="Copilot quota popover"> |
| Session telemetry, limit bank, pace tracking, and model insight | Monthly quota, lane breakdown, and recent activity chart |

### Analytics Window

<img src="docs/screenshots/claude_analytics.jpeg" width="680" alt="Claude Analytics window">

Deep-dive into session history — visible tokens, cache leverage, model distribution, and daily traffic trends across your Claude Code sessions.

### Settings

| Display | Keyboard Shortcuts |
|:---:|:---:|
| <img src="docs/screenshots/display_settings.jpeg" width="320" alt="Display settings"> | <img src="docs/screenshots/keyboard_shortcuts.jpeg" width="320" alt="Keyboard shortcuts"> |
| Navigation style, refresh interval, timezone, color thresholds, and provider order | Full keyboard navigation map for power users |

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Claude Code installed and authenticated (provides the Keychain credential)

---

## Install (Pre-built)

1. Download the latest `AIMeter-vX.X.X.zip` from [Releases](https://github.com/Khairul989/ai-meter/releases/latest)
2. Unzip and move `AIMeter.app` to `/Applications`
3. **First launch only:** right-click the app -> "Open" (bypasses Gatekeeper for unsigned apps)
4. AIMeter appears in your menu bar

Updates are checked automatically on launch. You can also check manually via Settings -> "Check for Updates..."

---

## Build from Source

1. Clone the repo
2. Create a self-signed code signing certificate named `AIMeter Dev`:
   - Open **Keychain Access** → Certificate Assistant → **Create a Certificate**
   - Name: `AIMeter Dev`, Certificate Type: **Code Signing**
3. `cd AIMeter && xcodegen generate`
4. Open `AIMeter.xcodeproj` in Xcode and run

> **Note:** The certificate name must match `CODE_SIGN_IDENTITY` in `project.yml`. If you use a different name, update the value in `project.yml` accordingly. Without a valid code signing certificate, keychain operations may trigger repeated macOS permission dialogs.

---

## Release Automation

Build and publish a signed Sparkle release with:

```bash
./scripts/release.sh v1.43.1
```

The script will:

- validate the version tag and required tooling
- bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `AIMeter/project.yml`
- regenerate `AIMeter.xcodeproj` with XcodeGen
- archive, sign, zip, and generate `appcast.xml`
- publish a GitHub release with notes pulled from `CHANGELOG.md` when a matching version entry exists

Useful flags:

- `--dry-run` builds artifacts without creating the GitHub release
- `--allow-dirty` bypasses the clean-worktree guard for local testing
- `--signing-identity "Your Cert Name"` overrides the default `AIMeter Dev` certificate
- `--repo owner/repo` publishes to a different GitHub repository

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
