# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
