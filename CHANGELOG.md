# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-04-20

### Added

- Dedicated Claude analytics window with redesigned model distribution and daily traffic panels
- Dedicated Codex analytics window with session telemetry sourced from local `~/.codex` state
- Weekly pace indicator on the Claude 7-day limit row, mirroring the 5-hour session pace

### Changed

- Major Mac-first visual redesign across the app with new telemetry-inspired surfaces, navigation, and provider presentation
- Claude quota popover rebuilt around a session hero, grouped limits, cleaner pacing signals, and a more native analytics split
- Codex popover redesigned with a provider-specific telemetry layout, slimmer status sections, and updated footer treatment
- MiniMax hero gauge now shows raw request counts (used / total) instead of just a percentage
- MiniMax Model Bank focuses on weekly usage, removing the redundant interval card
- Claude plan detection migrated to the bootstrap endpoint after `seat_tier` became unreliable upstream
- App icon replaced with the new owl branding

### Fixed

- Codex Analytics "unable to open database file" error when `state_5.sqlite` is in WAL mode without sidecars
- Claude pace messaging now shows the steady-pace delta again alongside the reset and runout guidance
- Release icon assets now use the updated full-background owl icon set at every macOS size

## [1.44.0] - 2026-04-18

### Added

- Claude Design quota card that appears automatically when `seven_day_omelette` is present in the Claude usage response

### Changed

- Claude Code model labels now use friendly names like `Opus 4.7`, `Sonnet 4.6`, and `Haiku 4.5`
- Provider number shortcuts now follow the user-defined tab order instead of the original hard-coded provider sequence
- Release automation rebuilt around stricter preflight checks, changelog-driven notes, configurable signing/repo settings, and safer dry-run behavior

### Fixed

- Claude Code model and daily usage parsing now recognizes newly launched Claude models like `claude-opus-4-7` without requiring another hardcoded model list update
- Settings shortcut reference now matches the actual provider count and uses `⌘7` for Settings when six provider tabs are present

## [1.43.0] - 2026-04-13

### Added

- Multi-account support for Claude, GLM, Kimi, and MiniMax with per-provider account cards in Settings
- Account switchers in provider tabs when multiple accounts are configured
- Codex load balancing: automatic failover to next available account on 429 rate-limit or 401 unauthorized
- "Auto-switch enabled" indicator in Codex tab when multiple accounts are configured
- MiniMax quota tab: collapsible model sections with mini progress bar in header; models with active usage auto-expand on load
- opencode multi-account support: proxy now handles `/responses` and `/v1/responses` paths, routing them through the Codex load balancer for automatic account failover

### Changed

- Settings > Accounts redesigned around per-provider account management
- Key storage migrated to account-scoped patterns for Claude and API-key providers
- Codex proxy failover loop simplified to while-let pattern with natural termination
- Account state normalization batched into single dispatch for reduced main-thread churn
- MiniMax quota tab now scrollable with 60% screen-height cap to handle large model lists

### Fixed

- Thread-safe account state management using shadow dictionary pattern for `@Published` property
- Race condition in `setAccounts` where rapid calls could leave stale ready states after sign-out

## [1.39.0] - 2026-04-05

### Changed

- Consolidated app-managed credentials into a single AppKeychain entry to eliminate repeated keychain permission dialogs
- Standardized local signing around the `AIMeter Dev` self-signed certificate and updated release signing flow

## [1.38.0] - 2026-04-05

### Added

- Codex local proxy service for multi-account token forwarding to the AIMeter-selected account

### Changed

- Disabled Codex WebSocket mode in proxy config and use HTTP/SSE fallback for web-session auth

### Fixed

- Codex account switching now forwards the selected account instead of always using the first logged-in account
- NIO proxy pipeline cleanup during WebSocket upgrade

## [1.37.0] - 2026-04-05

### Added

- Multi-account Codex support with account-scoped keychain storage and active-account selection
- Codex account switcher in the tab UI when multiple accounts are available

### Fixed

- Codex login flow now detects ChatGPT session state via async `/api/auth/session` polling
- Popup webview callbacks no longer corrupt the main login state

## [1.36.0] - 2026-04-04

### Fixed

- Extra Credits card now shows dollar amounts in the full layout instead of hiding them in compact mode

## [1.35.7] - 2026-04-04

### Added

- Claude Extra Credits support now reads inline `extra_usage` data from the `/usage` API, with `/overage_spend_limit` kept as fallback

## [1.35.6] - 2026-03-30

### Changed

- Reissued the release tag after release numbering drift; no code changes from `1.35.5`

## [1.35.5] - 2026-03-30

### Added

- MiniMax menu bar can now show the next reset time in classic display mode

### Fixed

- MiniMax weekly quota reset now shows day and time instead of time only
- Claude peak hours badge updated to the new weekday schedule and corrected to GMT-based timezone conversion

## [1.35.4] - 2026-03-25

### Changed

- Reissued the release tag after release numbering drift; no code changes from `1.35.3`

## [1.35.3] - 2026-03-25

### Changed

- Reissued the release tag after release numbering drift; no code changes from `1.35.2`

## [1.35.2] - 2026-03-25

### Changed

- Reissued the release tag after release numbering drift; no code changes from `1.35.1`

## [1.35.1] - 2026-03-25

### Fixed

- MiniMax `usage_count` is now treated as remaining quota instead of consumed quota

## [1.35.0] - 2026-03-25

### Added

- MiniMax as a new provider in AIMeter

## [1.34.2] - 2026-03-22

### Fixed

- App hang during normal use — refactored MenuBarLabel to lightweight struct (3 props instead of 8), preventing excessive ImageRenderer re-renders triggered by polling services

## [1.34.1] - 2026-03-22

### Fixed

- Menu bar hang when using Knight Rider or other loading animations — opacity now applied on the SwiftUI Image view instead of re-rendering NSImage each frame
- Classic display mode restored as default (percentage + reset time)

## [1.34.0] - 2026-03-22

### Added

- Loading Animation Patterns — 5 selectable refresh animations in Settings → Display
  - Fade (smooth sinusoidal), Knight Rider (triangle sweep), Pulse (gentle cosine), Blink (sharp dip), None (static dim)
  - Timer-driven animation phase with auto-cancel when refresh completes

## [1.33.0] - 2026-03-22

### Added

- Interactive History Charts for GLM, Codex, and Kimi tabs
  - Reusable `UsageHistoryChartView` with line+area chart, range picker (7D/14D/30D), and hover tooltip
  - GLM: token % over time; Codex: primary window % over time; Kimi: balance (¥) over time
  - Empty state placeholder when no history data yet
  - Uses Swift Charts framework for rendering

## [1.32.0] - 2026-03-22

### Added

- Historical Usage Tracking for All Providers — 56-day retention with automatic pruning
  - Extended GLM, Codex, and Kimi with history services (Claude and Copilot already had them)
  - GLM tracks token %, Codex tracks primary/secondary %, Kimi tracks balance
  - Bumped retention from 31 to 56 days across all providers
  - Persisted to `~/.config/aimeter/` as JSON with atomic writes

## [1.31.0] - 2026-03-22

### Added

- Developer Debug Pane — expanded debug tools in Settings (DEBUG builds only)
  - Test notifications: depleted, restored, warning, and monthly recap
  - Service status: last fetch time per provider
  - Force refresh all providers
  - Clear cached data with confirmation dialog
  - App info: version, build, bundle ID, macOS version

## [1.30.0] - 2026-03-22

### Added

- Provider Status Page Integration — polls Statuspage.io for incident badges
  - Monitors Claude (Anthropic), Copilot (GitHub), and Codex (OpenAI) status pages
  - Shows yellow/red dot with description when incidents are active (hidden when all clear)
  - 5-minute polling interval, silent error handling
  - Toggle in Settings → General ("Check provider status")

## [1.29.0] - 2026-03-22

### Added

- Global Keyboard Shortcut — ⌃⌥A (Control+Option+A) toggles the menu bar popover from anywhere
  - Uses native `NSEvent` global + local monitors (no external dependencies)
  - Finds and clicks the status bar button via window hierarchy traversal
  - Listed in Settings → Shortcuts reference

## [1.28.0] - 2026-03-22

### Added

- Menu Bar Display Modes — choose Percent, Pace, or Both in Settings → Display
  - Percent: "45%" (default, existing behavior)
  - Pace: "+5%" or "-3%" (delta from expected usage)
  - Both: "45% · +5%" (combined view)
  - Pace calculated for Claude's 5-hour session; other providers fall back to percent-only
  - New `MenuBarDisplayMode` enum with picker in Display settings

## [1.27.0] - 2026-03-22

### Added

- Usage Pace Analysis — color-coded pace indicator for Claude's 5-hour session window
  - New `UsagePace` utility: calculates expected vs actual usage, stage classification (on-track/ahead/behind), and ETA
  - `SessionPaceView` shows pace delta and depletion warning (e.g., "Ahead (+12%) · Runs out in 2h 15m")
  - Green = on-track/behind, yellow = slightly ahead, red = ahead/far ahead
  - Only for Claude session (other providers lack window duration data)

## [1.26.0] - 2026-03-22

### Added

- Provider Drag-to-Reorder — customize tab order via up/down buttons in Settings → Display
  - Tab enum refactored from hardcoded to data-driven with `@AppStorage("providerTabOrder")`
  - TabBarView, dropdown menu, and keyboard navigation all follow the stored order
  - `decodedProviderOrder` handles missing/corrupt values gracefully
  - Reset to Defaults restores original order

## [1.25.0] - 2026-03-22

### Added

- Session Depleted/Restored Notifications — alerts when any provider's quota hits 0% and when it recovers
  - New `SessionQuotaTracker` state machine tracking normal/depleted transitions per provider
  - Integrated into Claude, Copilot, Codex, and GLM services (Kimi skipped — balance-based)
  - Respects existing `notificationsEnabled` toggle
  - Fires each notification only once per transition (no spam)

## [1.24.0] - 2026-03-22

### Added

- Personal Info Redaction — toggle in Settings (Accounts section) to hide emails and org names throughout the UI
  - New `PersonalInfoRedactor` utility with regex-based email detection and whole-identity field replacement
  - Applied to Claude org name and Codex email displays in settings
  - "Reset to Defaults" also resets the redaction toggle

## [1.23.0] - 2026-03-19

### Added

- Monthly Recap — Spotify Wrapped-style usage summary with scrollable card UI in a dedicated window
  - Claude stats: average/peak session & weekly utilization, plan name, peak date
  - Copilot stats: chat, completions, premium utilization with progress bars
  - Highlights card with power user badge (avg > 70%)
  - Shareable PNG export (1080×1920) via native share sheet
  - Auto-generates on 1st of month with notification, also accessible from settings
- Settings Window — dedicated sidebar settings window (Cmd+, to open)
  - Sidebar navigation: Accounts, Display, Notifications, Shortcuts, General
  - Replaces inline settings in popover for more room
- Debug tools (#if DEBUG) — test buttons for recap window and notifications
- RecapService with monthly aggregation, persistence (~/.config/aimeter/recaps/), and auto-trigger

### Changed

- History retention extended from 7 to 31 days (required for monthly recaps)
- Notifications now use osascript backend (fixes delivery for ad-hoc signed builds)
- Settings tab (Cmd+6 / gear icon) now opens the settings window instead of inline view
- Added Cmd+, keyboard shortcut to open settings

### Fixed

- December recap crash — month+1 overflow (13) causing force-unwrap nil
- Copilot peakDate wrong for unlimited-chat plans (now uses max across all metrics)
- RecapService lifetime bug — promoted from local var to @State to survive task restarts
- Notification permission dialog never appearing for LSUIElement apps

## [1.20.0] - 2026-03-16

### Added

- Codex usage tracker — new provider for OpenAI Codex with web login (ChatGPT session auth), 5h/7d rate limit windows, and code review quota display
- Web login flow for Codex — WKWebView-based ChatGPT sign-in with cookie monitoring and access token extraction via `/api/auth/session`
- CodexService, CodexAPIClient, CodexAuthManager, CodexSessionKeychain — full provider stack following existing CopilotService pattern
- CodexTabView with sign-in prompt, usage cards, token-expired banner, and plan badge
- 8 new tests for Codex API response parsing (CodexAPIClientTests)
- Official provider icons — OpenAI logo for Codex, GLM Z logo, Kimi chat bubble logo as custom assets
- Icon-only unselected tabs — tab bar shows label only for active tab, preventing overflow with 5+ providers

### Changed

- Tab bar now uses custom asset icons for all providers (Claude, Copilot, GLM, Kimi, Codex) instead of system SF Symbols
- Dropdown navigation menu uses small icon variants for all providers
- Settings page wrapped in ScrollView (max 500px) to prevent content clipping on smaller displays
- Keyboard shortcuts updated: ⌘5 = Codex tab, ⌘6 = Settings

## [1.19.0] - 2026-03-15

### Added

- Onboarding wizard — 3-step welcome flow (Welcome → Providers → Ready) on first launch
- Skeleton/shimmer loading states — animated placeholders replace plain spinners in ModelUsageView and TrendChartView
- EmptyStateView component — SF Symbol illustrations with hints, used across all chart empty states
- Data export — "Export History…" menu in Settings with CSV export for Claude and Copilot quota history
- Rate limit countdown timer — live "retrying in Xs" countdown on all provider error banners
- Network connectivity detection — `NWPathMonitor` pauses polling when offline, shows "Offline" banner
- HTTPPollingService base class — DRY refactor of GLMService and KimiService (~60% code reduction)
- Customizable usage color thresholds — Normal/Elevated/High breakpoints configurable in Settings > Display
- Per-provider refresh intervals — optional override per provider (30s/1m/2m/5m) in Settings
- Keyboard shortcuts section in Settings — documents all available shortcuts (⌘R, ⌘1-5, arrows, Esc)
- "Open claude.ai" globe button in popover footer
- Settings reset to defaults button in General section
- Centralized `AppConstants` — API URLs, file paths, and defaults in one place
- 48 new tests (49→97 total): UsageColor, NetworkMonitor, HTTPPollingService, GLMService, QuotaHistoryService

### Changed

- TrendChartView renamed to "Daily Usage" with fresh look — Claude accent color bars, 100pt height, constrained X-axis domain
- Exponential backoff with jitter on rate limits — `retryAfter × 1.5^n + jitter` capped at 4 consecutive hits
- Request deduplication — `isFetching` guard prevents overlapping fetch() calls in all services
- JSONL date parsing uses local timezone (fixes timezone mismatch for UTC+ users)
- TrendChartView empty state now checks both messages AND tokens (was messages-only)

### Fixed

- TrendChartView not loading data on initial launch — `applyTrend()` now called after disk cache load
- TrendChartView horizontal expansion on hover — added `.chartXScale(domain:)` constraint
- 14D x-axis label overlap — stride increased from 2 to 3

## [1.18.0] - 2026-03-14

### Fixed

- Keychain migration data loss — legacy files now deleted only after verified keychain write-back
- GLM/Kimi services now handle HTTP 429 rate limiting with `Retry-After` backoff (previously retried at normal interval)
- Notification threshold validation — `warning` clamped below `critical` to prevent logic inversion

### Changed

- Consolidated `GLMKeychainHelper` and `KimiKeychainHelper` into static instances on `APIKeyKeychainHelper`
- Extracted shared `APIKeyInputView` component from duplicate GLM/Kimi tab key-entry UI
- Copilot API timeout standardized from 5s to 15s (consistent with other providers)
- `NotificationManager` tracker cached in memory to reduce UserDefaults I/O
- `HistoryServiceBase` now logs warnings when history files are corrupted and moved to backup
- JSONL parser skips files larger than 100MB to prevent memory pressure
- `PollingServiceBase` adds `deinit` timer cleanup for safety

### Added

- Rate-limited error banners on GLM and Kimi tabs
- Data staleness indicator on small and large widgets (medium already had it)

## [1.17.0] - 2026-03-13

### Added

- `ErrorBannerView` — reusable error banner component with optional retry action
- Error banners on GLM, Copilot, and Kimi tabs with retry functionality
- App version display in Settings (version + build number)
- Keyboard shortcuts: Escape to close settings, Cmd+5 to toggle settings
- Threshold animation on notification visualization bar
- Comprehensive VoiceOver accessibility labels across all tabs, pills, buttons, chart widgets
- Shared utilities: `AppTypeScale`, `ProviderTheme`, `UsageColor` with `levelDescription` helper

## [1.16.1] - 2026-03-12

### Added

- Tab bar navigation restored as default — provider tabs with brand icons for Claude and Copilot
- Navigation style picker in Settings > Display — switch between "Tab Bar" and "Dropdown"

### Fixed

- Removed duplicate chevron icons from all dropdown menus
- Claude and Copilot brand icons now display at correct size in dropdown menu

## [1.16.0] - 2026-03-12

### Added

- Keychain-based credential storage — session keys and API keys now stored securely with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Auto-migration from legacy plaintext files to Keychain on first launch
- Ephemeral URLSession for all API calls — no cookie leakage across requests
- Unified `PollingServiceBase` — shared timer management for all 5 polling services
- Generic `HistoryServiceBase` — deduplicated history persistence for quota and Copilot history
- Extracted tab views: ClaudeTabView, CopilotTabView, GLMTabView, KimiTabView, InlineSettingsView (PopoverView reduced from 974 to ~250 lines)
- `@EnvironmentObject` injection replacing 8 `@ObservedObject` parameters
- Error banner on Claude tab when fetch fails
- Keyboard shortcuts: Cmd+1-4 for tab switching, Cmd+Q for quit
- Sign-out confirmation dialog
- Accessibility labels on usage cards, gauges, progress bars, and quota rows
- Orange color tier for 80-95% utilization (green < 50%, yellow < 80%, orange < 95%, red >= 95%)
- Gauge progress clamped to 100% max
- `onKeySaved` callback — saving GLM/Kimi API key triggers immediate fetch
- DRY version management — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` defined once in project.yml
- New tests: ResetTimeFormatterTests, SessionAuthManagerTests, ClaudeCodeStatsServiceTests (16 new tests, 49 total)
- Secrets added to .gitignore (.env, .pem, .key, .p12)

### Changed

- Cached `DateFormatter` instances in ClaudeCodeStatsService (no longer allocated per render)
- `validateSessionKey` converted from callback-based to async/await
- Keychain helpers unified via generic `APIKeyKeychainHelper`
- API key resolution priority: Keychain first, environment variable fallback
- Removed duplicate chevron icons from all dropdown menus
- Code signing disabled by default (no Apple Developer account required to build)
- Widget description updated to "Monitor AI usage — Claude and Copilot"

## [1.15.0] - 2026-03-12

### Added

- Kimi (Moonshot AI) as a new provider — displays cash and voucher balance in CNY
- Inline API key entry on the Kimi tab (no need to go to Settings first)
- Provider dropdown in header replaces the old tab bar — cleaner navigation with more room for providers
- Back button in Settings returns to the previously active provider tab
- Inline API key entry on GLM tab (consistent with Kimi)

### Changed

- Popover width increased from 320 to 360 for better readability
- Settings pickers replaced with dropdown menus (Menu bar, Timezone, Refresh, Warning, Critical thresholds)
- Warning and Critical notification rows now highlighted in yellow and red respectively

## [1.14.0] - 2026-03-11

### Added

- Copilot quota snapshot history — records each API poll result with timestamp for burn rate tracking
- Copilot trend chart — multi-series line chart (Chat/Completions/Premium) with "Usage %" and "Remaining" toggle
- Beta badge on Copilot trend chart — clearly marks the feature as experimental
- New Claude icon

### Fixed

- Copilot trend chart Y-axis now uses actual entitlement value as upper bound instead of auto-scaling above it
- Copilot API rate-limit backoff — reschedules polling timer on 429 responses using `retry-after` header

## [1.13.0] - 2026-03-07

### Added

- Manual refresh shortcut (⌘R) — immediately refreshes all provider data when popover is open
- Refresh button in popover footer with ⌘R tooltip
- Menu bar sparkles icon pulses during refresh to indicate activity

## [1.12.1] - 2026-03-06

### Changed

- Menu bar now shows 5h reset time instead of 7d utilization (e.g. `5h 26% · 3:45pm`)

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
