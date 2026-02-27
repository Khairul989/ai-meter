# Design: GLM Tab

**Date:** 2026-02-27
**Status:** Approved

## Goal

Add a GLM tab to AIMeter showing token quota percentage and account tier — mirroring what the `glm.sh` statusline displays.

## API

- **Endpoint:** `GET https://api.z.ai/api/monitor/usage/quota/limit`
- **Auth:** `Authorization: <api_key>` (no Bearer prefix — same as glm.sh)
- **Key fields:**
  - `data.limits[].type == "TOKENS_LIMIT"` → `.percentage` (primary metric)
  - `data.level` → account tier (e.g. "pro")

## API Key Resolution

Priority order (same pattern as glm.sh env var usage):
1. `ProcessInfo.processInfo.environment["GLM_API_KEY"]` — auto-loaded from zshrc
2. Keychain — for keys manually entered via Settings
3. Neither found → show "No API key" empty state in the tab

## Data Model — `GLMUsageData`

```swift
struct GLMUsageData {
    let tokensPercent: Int    // TOKENS_LIMIT.percentage
    let tier: String          // data.level e.g. "pro"
}
```

## Service — `GLMService`

Mirrors `CopilotService` pattern:
- `@Published var usageData: GLMUsageData?`
- `@Published var lastUpdated: Date?`
- `@Published var errorMessage: String?`
- Polls every 60s (shared refresh interval setting)
- Resolves API key on init (env → Keychain)
- Graceful error handling — stale data shown, error message surfaced

## UI — `GLMTabView`

Two cards:

1. **Token Quota** — progress bar showing `tokensPercent`, color-coded green/yellow/red (<50/<80/≥80), label "5hr Token Quota" to match statusline naming
2. **Account** — tier badge (capitalised, e.g. "Pro")

Empty state: "No API key found. Add your GLM API key in Settings."

## Settings

New **GLM API Key** section in `InlineSettingsView`:
- If key comes from env var → show read-only label "Using GLM_API_KEY from environment"
- If no env var → show `SecureField` for manual entry, saves to Keychain on submit
- If Keychain key present but no env var → show masked key with a Clear button

## Tab Bar

New tab added between Copilot and Settings:
```swift
tabButton(.glm, icon: .asset("glm"), label: "GLM")
```

Uses `z.square` SF Symbol as placeholder until a real brand icon is available.
```swift
tabButton(.glm, icon: .system("z.square"), label: "GLM")
```

## Files to Create/Modify

- **Create:** `AIMeter/Sources/App/GLMService.swift`
- **Create:** `AIMeter/Sources/Shared/GLMUsageData.swift`
- **Modify:** `AIMeter/Sources/App/PopoverView.swift` — add `.glm` tab case, `GLMTabView`, tab button
- **Modify:** `AIMeter/Sources/App/SettingsView.swift` — add GLM API key section
- **Modify:** `AIMeter/project.yml` — version bump to v1.5.0
