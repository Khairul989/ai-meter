# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
