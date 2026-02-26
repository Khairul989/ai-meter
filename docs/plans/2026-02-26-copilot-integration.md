# GitHub Copilot Integration — v1.1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add GitHub Copilot usage monitoring to AIMeter alongside existing Claude API monitoring.

**Architecture:** Multi-provider design. New GitHub Keychain reader + Copilot API client. Popover shows Claude and Copilot sections. Widgets show combined highest utilization.

**Tech Stack:** Same as v1.0 — Swift, SwiftUI, WidgetKit, Keychain Services

---

### API Reference

**Token source:** macOS Keychain, service `gh:github.com`
- Value is prefixed with `go-keyring-base64:`, remainder is base64-encoded
- Decoded token is a `gho_*` GitHub OAuth token

**Endpoint:** `GET https://api.github.com/copilot_internal/user`

**Headers:**
- `Authorization: Bearer <token>`
- `Accept: application/vnd.github+json`
- `X-GitHub-Api-Version: 2022-11-28`

**Response structure (key fields):**
```json
{
  "copilot_plan": "individual",
  "access_type_sku": "yearly_subscriber_quota",
  "quota_reset_date_utc": "2026-03-01T00:00:00.000Z",
  "quota_snapshots": {
    "chat": {
      "entitlement": 0, "remaining": 0, "percent_remaining": 100.0, "unlimited": true
    },
    "completions": {
      "entitlement": 0, "remaining": 0, "percent_remaining": 100.0, "unlimited": true
    },
    "premium_interactions": {
      "entitlement": 300, "remaining": 35, "percent_remaining": 11.72, "unlimited": false
    }
  }
}
```

**Key insight:** `percent_remaining` is how much is LEFT (not used). Usage % = 100 - percent_remaining.
Unlimited quotas (chat, completions on paid plans) should show as "Unlimited" not 0%.

---

### Task 1: GitHub Keychain Helper

**Files:**
- Create: `Sources/Shared/GitHubKeychainHelper.swift`
- Create: `Tests/GitHubKeychainHelperTests.swift`

Read GitHub token from macOS Keychain:
- Service name: `gh:github.com`
- Strip `go-keyring-base64:` prefix
- Base64 decode to get `gho_*` token
- Make token extraction testable (separate decode logic from Keychain read)

---

### Task 2: Copilot API Client

**Files:**
- Create: `Sources/Shared/CopilotAPIClient.swift`
- Create: `Sources/Shared/CopilotUsageData.swift`
- Create: `Tests/CopilotAPIClientTests.swift`

Models:
```swift
struct CopilotUsageData: Codable, Equatable {
    let plan: String                          // "individual", "business", etc.
    let chat: CopilotQuota
    let completions: CopilotQuota
    let premiumInteractions: CopilotQuota
    let resetDate: Date?
    let fetchedAt: Date

    var highestUtilization: Int  // highest usage % across non-unlimited quotas
}

struct CopilotQuota: Codable, Equatable {
    let utilization: Int          // 0-100 usage percentage
    let remaining: Int
    let entitlement: Int
    let unlimited: Bool
}
```

API client:
- Parse response, convert `percent_remaining` to usage % (100 - percent_remaining)
- Handle unlimited quotas (utilization = 0 when unlimited)
- Tests with full response JSON and edge cases

---

### Task 3: Copilot Service

**Files:**
- Create: `Sources/App/CopilotService.swift`
- Modify: `Sources/Shared/SharedDefaults.swift` — add Copilot data save/load

Same pattern as UsageService:
- ObservableObject with @Published copilotData
- Timer-based polling (same interval as Claude)
- Error states: noToken, fetchFailed
- Write to SharedDefaults for widget access
- Separate key in UserDefaults: "copilotData"

---

### Task 4: Update Popover UI for Multi-Provider

**Files:**
- Modify: `Sources/App/PopoverView.swift` — add Copilot section
- Modify: `Sources/App/AIMeterApp.swift` — add CopilotService

Popover layout:
```
AI Meter
─── Claude ───
  Session        96%
  Weekly         47%
  Sonnet         53%
  Extra Credits  49%
─── GitHub Copilot (Pro) ───
  Chat           Unlimited
  Completions    Unlimited
  Premium        88%  (35/300 remaining)
  Reset Mar 1
───
Updated < 1 min ago    ⚙
```

- Section headers for each provider
- Unlimited quotas show "Unlimited" badge instead of percentage
- Show plan type in Copilot header
- If no GitHub token found, show "Connect GitHub CLI" hint instead of Copilot section

---

### Task 5: Update Widgets for Multi-Provider

**Files:**
- Modify: `Sources/Widget/AIMeterWidget.swift` — read Copilot data
- Modify: `Sources/Widget/SmallWidgetView.swift` — consider Copilot in highest utilization
- Modify: `Sources/Widget/MediumWidgetView.swift` — add Copilot gauge

Small widget: show highest utilization across ALL providers
Medium widget: add a Copilot premium gauge alongside Claude gauges

---

### Task 6: Wire Up & Integration Test

**Files:**
- Modify: `Sources/App/AIMeterApp.swift` — start CopilotService
- Build both targets, run all tests, manual verification

---

## Task Dependencies

```
Task 1 (keychain) ──┐
                     ├── Task 3 (service) ── Task 4 (popover UI) ──┐
Task 2 (API client) ┘                       Task 5 (widgets) ──────┤── Task 6 (integration)
```

Parallelizable: Tasks 1+2, Tasks 4+5
