# Codex OAuth PKCE — Design Doc

**Date:** 2026-04-20
**Author:** AIMeter dev
**Status:** Draft — awaiting review

## Problem

AIMeter proxies Claude Code requests to the ChatGPT Codex Responses API at `https://chatgpt.com/backend-api/codex/responses`. Authentication today uses a ChatGPT **web-session token** scraped from `/api/auth/session` via `CodexAuthManager`'s WKWebView. Empirically, requests signed with this token are routed to the **batch/async Codex tier** that processes events on a ~60-second cycle. A trivial "hi" through Claude Code takes 1m 39s minimum — two round trips × ~45s per cycle — even after trimming tools from 104 → 55 and disabling non-essential Claude Code traffic.

The reference project [`claude-codex-proxy`](https://github.com/raine/claude-codex-proxy) uses a **Codex CLI OAuth token** obtained via PKCE against `https://auth.openai.com` with the Codex CLI's public client ID (`app_EMoamEEZ73f0CkXaXp7hrann`). Same URL, same headers, same request body — but the token carries claims identifying the caller as the Codex CLI, so OpenAI routes those requests to the **real-time streaming tier** used by `codex` CLI itself. First-token latency there is comparable to talking directly to a ChatGPT frontend, not the batch pipeline.

## Goal

Give each AIMeter-tracked ChatGPT account an **optional, parallel** OAuth-PKCE credential set. When present, use it for proxy-routed Claude Code requests. When absent, fall back to the existing web-session token. Preserve multi-account support end-to-end.

## Non-Goals

- Removing the existing web-session auth path (still needed for quota monitoring, account discovery, and as fallback).
- Supporting headless / device-code auth (the reference has `auth device` for SSH contexts; we can add later, not now).
- Touching any other AIMeter tab's auth (Claude, Copilot, GLM, etc. — unaffected).
- Token introspection or claim inspection beyond what's necessary to extract the `chatgpt_account_id`.

## Root-Cause Evidence (why we believe the auth tier matters)

From the live proxy log after all payload-side optimizations:

| Request shape | Tool count | Body size | Model | "hi" latency |
|---|---:|---:|---|---:|
| Pre-fix web-session | 104 | 208 KB | gpt-5.4 | 4m 52s |
| Post-fix web-session | 55 | 174 KB | gpt-5.4 | 1m 39s |
| Reference proxy (OAuth, same tools would apply) | — | — | gpt-5.4 | seconds |
| `codex` CLI native (OAuth, ~10 tools) | 10 | <20 KB | gpt-5.4 | seconds |

SSE timestamps from our batched runs show `response.created` arriving ~45–60s after HTTP 200, and `response.completed` arriving ~60s after content is done. These are fixed server-side delays — not proportional to tool count or prompt length. They disappear in the OAuth-tier traffic that `codex` CLI observes. This is the one variable we have not yet changed.

## Design

### Architecture overview

```
┌─────────────────────────────────────┐
│ CodexAccount (existing)             │
│   id, email, accessToken (web)      │
│   idToken, chatGPTAccountId         │
│   oauthAccessToken? (NEW)           │
│   oauthRefreshToken? (NEW)          │
│   oauthExpiresAt? (NEW)             │
└───────┬─────────────────────────────┘
        │ loaded by
        ▼
┌─────────────────────────────────────┐
│ CodexAuthManager (existing)         │
│   handles web-session login         │
│   publishes accounts list           │
└───────┬─────────────────────────────┘
        │ queried by
        ▼
┌─────────────────────────────────────┐   ┌──────────────────────────┐
│ ClaudeCompatProxyService            │──▶│ CodexOAuthService (NEW)  │
│   performStreamingUpstreamRequest   │   │   PKCE code gen          │
│   → if oauth* present, refresh &    │   │   browser launch         │
│     use oauth access token          │   │   local callback server  │
│   → else use web-session accessToken│   │   token exchange/refresh │
└─────────────────────────────────────┘   │   single-flight guard    │
                                          └──────────────────────────┘
                                                  ▲
                                                  │ triggered by
                                                  │
                                          ┌──────────────────────────┐
                                          │ AccountRow UI (existing) │
                                          │   NEW: "⚡ Upgrade" button│
                                          └──────────────────────────┘
```

### Auth flow (per account)

1. User clicks **⚡ Upgrade for fast routing** on an existing account row.
2. `CodexOAuthService.startLogin(for: accountID)` generates:
   - `code_verifier` — 43 random chars from the PKCE unreserved set
   - `code_challenge` — `base64url(SHA256(verifier))`
   - `state` — 32 random bytes, base64url
3. Starts a local NIO HTTP listener bound to `127.0.0.1:1455` (reusing NIO already in the project for `ClaudeCompatProxyService`).
4. Opens the system browser via `NSWorkspace.shared.open(url)` pointing at:
   ```
   https://auth.openai.com/oauth/authorize?
     response_type=code
     &client_id=app_EMoamEEZ73f0CkXaXp7hrann
     &redirect_uri=http://localhost:1455/auth/callback
     &scope=openid%20profile%20email%20offline_access
     &code_challenge=<challenge>
     &code_challenge_method=S256
     &id_token_add_organizations=true
     &codex_cli_simplified_flow=true
     &state=<state>
     &originator=claude-codex-proxy
   ```
5. User signs in to OpenAI with the ChatGPT account they want to upgrade. Browser redirects to `http://localhost:1455/auth/callback?code=…&state=…`.
6. Callback server validates `state`, extracts `code`, returns a 200 HTML page ("You can close this window").
7. Service POSTs to `https://auth.openai.com/oauth/token` with:
   ```
   grant_type=authorization_code
   code=<code>
   redirect_uri=http://localhost:1455/auth/callback
   client_id=app_EMoamEEZ73f0CkXaXp7hrann
   code_verifier=<verifier>
   ```
8. Response `{access_token, refresh_token, id_token, expires_in}` → parsed. `chatgpt_account_id` is extracted from the `id_token` JWT (existing `decodeIDTokenClaims` logic in `ClaudeCompatProxyService`).
9. **Match to the AIMeter account**: compare the extracted `chatgpt_account_id` to the account the user was upgrading. If mismatch (they signed in as a different ChatGPT account), show an error: "Signed in as X, expected Y. Try again." Don't save.
10. On match, save via `CodexSessionKeychain` under new key kinds. Account row flips to "⚡ Upgraded" state.
11. Shut down the callback server.

### Token refresh

- Before each upstream request, `ClaudeCompatProxyService` asks `CodexOAuthService.currentAccessToken(for: accountID)`.
- Service checks: if `oauthExpiresAt > now + 5min`, returns cached token.
- Else performs single-flight refresh via POST `https://auth.openai.com/oauth/token`:
  ```
  grant_type=refresh_token
  refresh_token=<stored>
  client_id=app_EMoamEEZ73f0CkXaXp7hrann
  ```
- On 401 mid-request (token revoked upstream): invalidate, force one refresh, retry once (mirror of reference's `codex/client.ts:26-34` behavior). Second 401 → surface to user, mark account as needing re-auth.

### Proxy request selection

In `ClaudeCompatProxyService.performStreamingUpstreamRequest`:

```swift
let bearerToken: String
if let oauthToken = try? await oauthService.currentAccessToken(for: context.accountId) {
    bearerToken = oauthToken
} else {
    bearerToken = context.accessToken  // existing web-session token
}
request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
```

The `originator: claude-codex-proxy` header, `openai-beta`, `ChatGPT-Account-Id`, and session headers stay unchanged.

## New Types

### `CodexOAuthService`

```swift
@MainActor
final class CodexOAuthService: ObservableObject {
    static let shared = CodexOAuthService()

    @Published private(set) var pendingLoginAccountID: String?
    @Published private(set) var lastError: String?

    func startLogin(for accountID: String, expectedChatGPTAccountID: String?) async throws -> CodexOAuthTokens
    func currentAccessToken(for accountID: String) async throws -> String?  // nil if not upgraded
    func revokeLocalTokens(for accountID: String)
    func hasOAuthTokens(for accountID: String) -> Bool
}

struct CodexOAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let expiresAt: Date
    let chatGPTAccountID: String?
}
```

### `CodexOAuthCallbackServer`

Tiny NIO HTTP listener — single request lifecycle. Binds on start, returns a single-shot `Future<(code, state)>` via Combine, closes after one successful callback.

```swift
actor CodexOAuthCallbackServer {
    func listen() async throws -> (code: String, state: String)  // one-shot, auto-closes
    func stop() async
}
```

Binding: same `NIOPosix.MultiThreadedEventLoopGroup` pattern as `ClaudeCompatProxyService` but on port 1455 and with a dedicated handler that only matches `/auth/callback`.

### `CodexAccount` additions

```swift
struct CodexAccount {
    // existing fields...
    let accessToken: String         // web-session (unchanged)
    var idToken: String?             // unchanged

    // NEW — optional, preserves full backwards compat
    var oauthRefreshToken: String?
    var oauthAccessToken: String?
    var oauthAccessTokenExpiresAt: Date?
}

var hasOAuthUpgrade: Bool { oauthRefreshToken != nil }
```

### Keychain key additions

`CodexSessionKeychain` gets two new kinds:
- `.oauthRefreshToken` (persistent)
- `.oauthAccessTokenCache` (persistent cache with `oauthExpiresAt` sibling)

Existing `.accessToken`, `.sessionToken`, `.idToken` kinds unchanged.

## File Changes

| File | Change |
|---|---|
| **`AIMeter/Sources/App/CodexOAuthService.swift`** | NEW. ~300 LOC. PKCE gen, browser launch, token exchange, refresh with single-flight guard, account-ID verification. |
| **`AIMeter/Sources/App/CodexOAuthCallbackServer.swift`** | NEW. ~120 LOC. NIO HTTP listener on 127.0.0.1:1455, one-shot `/auth/callback` handler. |
| `AIMeter/Sources/App/CodexAuthManager.swift` | Extend `CodexAccount` with three optional OAuth fields. Load/save via keychain. No change to web-session flow. |
| `AIMeter/Sources/Shared/CodexSessionKeychain.swift` | Add `.oauthRefreshToken`, `.oauthAccessTokenCache` kinds. |
| `AIMeter/Sources/App/ClaudeCompatProxyService.swift` | In `performStreamingUpstreamRequest`: resolve bearer token via `CodexOAuthService.currentAccessToken(for:)` with fallback to `context.accessToken`. Also add OAuth-aware 401 retry path. |
| Settings tab UI (wherever account rows render, e.g. `SettingsView.swift`) | Per-account "⚡ Upgrade for fast routing" button when `!hasOAuthUpgrade`; "⚡ Upgraded" badge + "Remove OAuth" menu item otherwise. |

## UI Flow

Account row, two states:

```
┌─ Existing: not upgraded ────────────────────────┐
│ erniezakri5489@trackdefect.my   [Active]        │
│ ⚡ Upgrade for fast routing  ·  Remove account   │
└─────────────────────────────────────────────────┘

┌─ After upgrade ─────────────────────────────────┐
│ erniezakri5489@trackdefect.my   [Active] [⚡]   │
│ Re-authenticate OAuth  ·  Remove account        │
└─────────────────────────────────────────────────┘
```

Clicking **⚡ Upgrade**:
1. Disable button, show inline spinner "Opening browser…"
2. System browser opens, user signs in
3. Swift app receives callback → inline spinner "Finishing sign-in…"
4. On account-ID match: row updates to upgraded state with a toast "Fast routing enabled for <email>".
5. On mismatch or error: show inline error under the button.

Cancellation: if the browser tab closes without completing in 5 minutes, the callback server times out, button re-enables, error shows "Sign-in was cancelled or timed out."

## Edge Cases

- **Port 1455 conflict.** If `claude-codex-proxy serve` or another tool is already listening on 1455, bind fails. Surface a clear error: "Port 1455 is in use by another process. Close it and try again." No fallback port — OpenAI only whitelists 1455 for that client.
- **Wrong ChatGPT account chosen in browser.** Validated against the existing account's `chatGPTAccountID` before save. Rejects with actionable message.
- **Multiple accounts simultaneously upgrading.** Serialize: `CodexOAuthService.startLogin` is `@MainActor` and sets `pendingLoginAccountID`; UI disables other Upgrade buttons while one is in progress.
- **Refresh token revoked server-side.** Second 401 in a single request (after forced refresh) → mark account's OAuth as invalid, clear `oauthRefreshToken`, surface notification "Account needs re-authentication." Web-session fallback resumes automatically.
- **Token expiry during active stream.** `URLSession.AsyncBytes` doesn't allow mid-request token swap. Acceptable: let the stream fail, and the outer retry logic (for new requests) will pick up the refreshed token.
- **Concurrent upstream requests for the same account.** Refresh is single-flight (`actor` or `DispatchQueue` serial) — concurrent callers await the same in-flight refresh.
- **User logs out of ChatGPT web session.** OAuth tokens are unaffected (separate credential). Web-session token goes stale; we keep using OAuth.
- **User removes the account.** All four key kinds (web-session + OAuth) deleted together.

## Security Notes

- PKCE `code_verifier` lives in memory only until token exchange. Never persisted.
- `state` is single-use. Server rejects callbacks where `state` doesn't match the in-flight login.
- Callback server binds on `127.0.0.1` only, never `0.0.0.0`.
- Refresh tokens stored in Keychain with same ACL as existing web-session tokens (AIMeter bundle ID only).
- Access tokens cached in Keychain too, not in UserDefaults. Cache invalidated on refresh.
- No logging of token values anywhere. Existing log redaction rules (subsystem `ClaudeCompatProxy`) extended to `oauthRefreshToken`, `oauthAccessToken`, `Authorization`, `id_token`.

## Testing Plan

Manual:
1. Fresh AIMeter with one web-session account. Click Upgrade. Verify browser opens, sign in, callback received, row state updates.
2. Send "hi" via Claude Code routed through proxy. Check `claude-compat-proxy.log` — new bearer value (different JWT signature). Time the round trip.
3. Compare: before-upgrade latency vs after-upgrade latency for identical prompts. Expect 4–10× speedup.
4. Force token refresh: edit Keychain to set `oauthAccessTokenExpiresAt` to 1 minute ago, send request, verify refresh POST hits the log and request succeeds.
5. Revoke refresh token externally (log out of OpenAI everywhere) → next request 401 → force-refresh 401 → account flagged for re-auth.
6. Upgrade a second account. Both upgraded. Proxy rotates between them correctly.
7. Remove an upgraded account. Keychain cleanup verified (no orphan OAuth entries).
8. Port 1455 conflict: start `claude-codex-proxy serve` in parallel, click Upgrade, verify friendly error.

Automated (optional, later):
- Unit tests for PKCE code generation (verify `base64url(SHA256(verifier))` matches challenge)
- Unit test for callback server handling of query params / validation of `state`
- Mock URLSession test for token exchange + refresh single-flight

## Rollout

**Phase 1 (this doc):** Ship the parallel auth path. Zero breaking change. Users can opt in per account. Feature labeled "experimental" in the UI for the first release.

**Phase 2 (future, separate doc):** Once stable, consider making OAuth the default for new accounts. Keep web-session as fallback for any account OpenAI starts rate-limiting on the OAuth tier.

**Phase 3 (future):** Add `auth device` flow for headless / SSH'd Macs if user demand shows up.

## Risks & Open Questions

1. **OpenAI ToS gray area.** Using the Codex CLI's public client ID from a non-official client is the same territory OpenCode and the reference proxy occupy. OpenAI has not pushed back on any of them so far. If they clamp down (device attestation, client secret rotation, per-account OAuth app registration requirement), the whole strategy breaks simultaneously for all third-party tools — but we'd fall back cleanly to web-session auth.
2. **Client ID rotation.** `app_EMoamEEZ73f0CkXaXp7hrann` is hard-coded. If it's ever revoked, a one-line update ships new value. Worth a constant, not a UserDefault — no reason for users to customize.
3. **Unknown: does the OAuth-tier apply different rate limits?** We don't know until we measure. If OAuth tokens get stricter limits, account rotation logic handles it the same way it handles web-session 429s today.
4. **Unknown: does OpenAI log "suspicious" OAuth activity?** Signing in with the Codex CLI's client ID from a machine that hasn't run `codex` could be flagged. No evidence this happens; reference proxy users haven't reported problems. Monitor.

## Implementation Order (for planner skill)

1. **`CodexOAuthService` + `CodexOAuthCallbackServer`** — standalone, testable end-to-end against real OpenAI auth without touching proxy code.
2. **`CodexAccount` + `CodexSessionKeychain` extensions** — storage plumbing only. No behavior change until step 3.
3. **`ClaudeCompatProxyService` bearer token resolution** — hook OAuth into the request path. Existing accounts without OAuth still route through web-session.
4. **Settings UI** — Upgrade button, upgraded badge, error surfaces.
5. **Wire everything + manual test matrix from "Testing Plan"** above.

Each step should be one reviewable commit; step 1 alone ships nothing user-visible but lets us verify the PKCE flow + callback server in isolation.
