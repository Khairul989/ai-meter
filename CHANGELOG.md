# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.12.0] - 2026-03-05

### Added

- Daily trend chart (Swift Charts) — combo bar + line chart showing messages/day and tokens/day
- Trend range picker: 7D / 14D / 30D with summary stats (avg msgs/day, total msgs, total tokens)
- Disk-cached JSONL parsing — parsed token data persists across app restarts for instant startup
- Incremental JSONL parsing — only re-parses files modified since last scan
- Loading indicator ("Scanning logs...") while initial JSONL parse runs
- Daily message count tracking from Claude Code conversation logs

### Changed

- Replaced QuotaChartView (historical quota trend) with new TrendChartView (token + message trend)
- JSONL parse results now include message counts alongside token data

## [1.11.0] - 2026-03-05

### Added

- Menu bar quota display — shows provider-specific usage percentages (e.g. `5h 26% · 7d 60%` for Claude)
- Menu bar provider picker in Settings — choose which provider's quota to show (Claude / Copilot / GLM)
- Per-provider menu bar formats: Claude (5h + 7d), Copilot (Premium %), GLM (token %)

### Changed

- Settings page reorganized into grouped sections: Accounts, Display, Notifications, General
- Each section uses card backgrounds with uppercase headers for visual clarity
- Icons added to account entries, update button, and quit button

## [1.10.0] - 2026-03-05

### Added

- WKWebView login flow — sign in via embedded browser (supports Google, Apple, Microsoft OAuth)
- Popup window handling for Google Sign-In (`WKUIDelegate`)
- Plan name detection from `rate_limit_tier` field (e.g. "Max 5×", "Pro")
- Plan badge displayed next to "AI Meter" header
- Extra credits from `overage_spend_limit` endpoint (spend limit + balance)
- Historical trend chart (Swift Charts) with 1h/6h/1d/7d range picker
- Breakdown bar showing Session/Weekly/Sonnet proportions
- Card background styling for all quota cards

### Changed

- Auth switched from OAuth PKCE to session cookie approach (claude.ai web API)
- Credentials stored as files in `~/.config/aimeter/` (session, org, org_name, plan)
- API endpoints changed to `claude.ai/api/organizations/{orgId}/usage`
- Browser-mimicking headers via `ClaudeHeaderBuilder` to avoid Cloudflare blocks

### Removed

- OAuth PKCE flow (`OAuthManager.swift`)
- `KeychainHelper.swift` and `KeychainHelperTests.swift`

## [1.9.0] - 2026-03-05

### Added

- Own OAuth PKCE authentication flow (separate rate limit bucket from Claude Code)
- Sign in/out UI in Settings tab and directly on Claude tab
- File-based token storage at `~/.config/aimeter/token` (no Keychain dependency)

### Changed

- Default polling interval restored to 60s (1m/2m/3m/5m picker)
- No longer requires Claude Code to be installed

### Removed

- `KeychainHelper.swift` — no longer reads Claude Code's Keychain token
- `SettingsView.swift` — unused standalone settings window

## [1.8.0] - 2026-03-05

### Added

- Sparkle 2 auto-update framework (EdDSA signed, no Apple Developer Program required)
- Automatic update check on app launch via `SPUStandardUpdaterController`
- "Check for Updates..." button in Settings tab
- Release script (`scripts/release.sh`) for building, signing, and publishing to GitHub Releases
- Appcast XML hosted on GitHub Releases for Sparkle feed
- Pre-built install instructions in README for non-developer users

## [1.7.0] - 2026-03-04

### Changed

- OAuth rate limit handling with retry-after backoff
- Default polling interval increased to 100s to reduce rate limit hits

## [1.6.0] - 2026-03-02

### Added

- Live countdown on Session card — ticks every second via `TimelineView(.periodic)` without requiring an API refresh

### Changed

- `ResetTimeFormatter.format` accepts an injectable `now: Date` parameter for testability and live updates
- Countdown format changed from `"3h01"` to `"3h 1m"` for readability
- Timezone default auto-detects device timezone (`TimeZone.current`) instead of hardcoded UTC+8

### Fixed

- `APIClient` ISO8601 formatter now includes fractional seconds (`withFractionalSeconds`) to correctly parse API timestamps

## [1.5.0] - 2026-02-27

### Added

- GLM tab for Z.ai quota monitoring (5hr token quota percentage + account tier)
- `GLMService` polling `api.z.ai/api/monitor/usage/quota/limit` with env var → Keychain key resolution
- GLM API key management in Settings: auto-detects `GLM_API_KEY` env var, falls back to manual Keychain entry
- GLM token quota included in menu bar utilization indicator

## [1.4.0] - 2026-02-27

### Changed

- Claude and Copilot tab icons replaced with real brand icons (custom image assets) instead of generic SF Symbols (sparkles / airplane)

## [1.3.0] - 2026-02-26

### Changed

- Replaced vertical stacked provider layout with tabbed design (Claude / Copilot / Settings tabs)
- Settings gear button moved from footer into the tab bar
- Footer "Updated X ago" now reflects the active tab's provider data
- Footer hidden on Settings tab

## [1.2.0] - 2026-02-26

### Added

- Native macOS notifications when quota metrics cross configurable thresholds
- Warning and critical threshold pickers in settings (default 80% / 90%)
- Crossing detection — notifies once per crossing, resets when utilization drops below warning
- Notifications cover all metrics: Claude Session, Weekly, Sonnet, Credits, Copilot Premium
- App icon using custom AI Meter artwork
- Development team set in project.yml for persistent Keychain access

## [1.1.0] - 2026-02-26

### Added

- GitHub Copilot usage monitoring via `gh` CLI Keychain token (`gh:github.com`)
- Copilot section in popover with Chat, Completions, and Premium Interactions quotas
- "Unlimited" badge for unlimited quotas (Chat and Completions on paid plans)
- Premium Interactions shows usage % with remaining/total count
- Inline settings panel replaces broken separate settings window
- Menu bar icon now reflects highest utilization across all providers

### Fixed

- Settings button not working (replaced `showSettingsWindow:` with inline panel)
- Extra credits displayed in cents instead of dollars (divided by 100)
- SF Symbol `robot`/`robot.fill` replaced with `sparkles` (invalid symbol names)

## [1.0.0] - 2026-02-26

### Added

- macOS menu bar app with popover showing Claude API usage
- Session (5h), Weekly (7d), Sonnet (7d dedicated), and Extra Credits usage cards
- Color-coded progress bars (green <50%, yellow 50-80%, red >=80%)
- Reset time display in configurable timezone
- WidgetKit extension with small (single gauge) and medium (all gauges) widgets
- Circular gauge components with animated progress rings
- OAuth token read from macOS Keychain (Claude Code credentials)
- API polling with configurable refresh interval (30s / 60s / 120s)
- App Group shared data between app and widget
- Settings: refresh interval, timezone, launch at login
- Error states: no token found, stale data indicator
- LSUIElement (no dock icon, menu bar only)
