# Claude Per-Folder Account Routing — Spec

**Date:** 2026-05-03
**Status:** Locked, ready for implementation
**Estimate:** 4–4.5 focused days
**Owner:** AIMeter

---

## Summary

AIMeter becomes the configurator and onboarding UX for per-folder Claude Code OAuth account routing. Users with multiple Claude accounts (personal Max, company Teams Max, client accounts) define profiles, paste tokens once, map folders to profiles, and AIMeter writes `.envrc` files that direnv consumes at runtime.

**AIMeter is setup-time only.** It does not shim the `claude` binary, proxy traffic, or run as a background daemon. After the `.envrc` is written, AIMeter is out of the loop.

---

## Scope

### In
- N-profile management (add, label-rename, delete; slug pinned at creation)
- Pasted token storage in macOS Keychain (one entry per profile)
- Folder-to-profile route table
- `.envrc` writer with marker-block merge (preserves user's other env vars)
- Diff preview before every write
- Token age tracking (1-year rotation cadence)
- "Rotate token" guided flow
- First-run onboarding card with prefilled example profile

### Out
- Default route in `$HOME` — user edits `~/.zshrc` themselves (one-line snippet AIMeter shows)
- Background health-check daemon (no validation endpoint exists; see §Failure Modes #8)
- "Test Token" button (would burn inference quota)
- Per-profile usage attribution / analytics (deferred to v2)
- Auto-running `direnv allow` (user runs it themselves)
- Claude Code OAuth flow (user runs `claude setup-token` themselves; AIMeter only ingests output)

---

## Architecture

### Data Model

```swift
struct ClaudeProfile: Identifiable, Codable {
    let id: UUID                    // internal stable ID
    let slug: String                // immutable, used as Keychain service ID; e.g. "claude-personal"
    var label: String               // user-facing, mutable; e.g. "Personal Max"
    var notes: String?              // optional free-text
    var isDefault: Bool             // exactly one profile is default
    let createdAt: Date             // for token-age UI; bumped on rotate
    var lastRotatedAt: Date?        // explicit rotation timestamp (nil = same as createdAt)
}

struct ClaudeFolderRoute: Identifiable, Codable {
    let id: UUID
    let folderBookmark: Data        // security-scoped bookmark (sandboxed file access)
    let folderPath: String          // display copy of resolved path
    var profileId: UUID             // → ClaudeProfile.id
}

struct ClaudeRoutingState: Codable {
    var profiles: [ClaudeProfile]
    var routes: [ClaudeFolderRoute]
}
```

Persistence: JSON in AIMeter's app-support directory. Tokens never persisted here — Keychain only.

### Keychain Layout

| Field | Value |
|---|---|
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | profile slug, e.g. `claude-personal` |
| `kSecAttrAccount` | `$USER` (current macOS username) |
| `kSecValueData` | UTF-8 OAuth token from `claude setup-token` |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlock` |

Slug naming convention: `claude-<user-chosen-slug>`. Slug must match `^[a-z0-9][a-z0-9-]{0,30}$`. Validated on profile creation, enforced by UI.

### `.envrc` File Shape

AIMeter manages only the block between markers. Everything outside the markers is preserved verbatim.

```sh
# (any pre-existing user content stays here, untouched)

# >>> aimeter claude routing >>>
if token=$(security find-generic-password -s claude-work -w 2>&1); then
  export CLAUDE_CODE_OAUTH_TOKEN="$token"
else
  echo "AIMeter: keychain entry 'claude-work' missing or denied" >&2
fi
# <<< aimeter claude routing <<<

# (any post-existing user content stays here, untouched)
```

If markers are absent, AIMeter appends the block at end-of-file. If markers are present, AIMeter replaces only the lines between them.

### `~/.zshrc` Snippet (User-Owned)

AIMeter shows this for copy-paste; does not write to the file:

```sh
# Default Claude account (everywhere outside per-folder overrides)
if token=$(security find-generic-password -s claude-personal -w 2>/dev/null); then
  export CLAUDE_CODE_OAUTH_TOKEN="$token"
fi
```

### Module Layout (proposed)

| File | Purpose |
|---|---|
| `ClaudeRoutingStore.swift` | Persistence + Keychain CRUD, single source of truth |
| `EnvrcWriter.swift` | Marker-block read/merge/write, atomic rename, diff generation |
| `ClaudeRoutingView.swift` | Settings → Claude tab section (profile list + route table) |
| `ClaudeProfileEditSheet.swift` | Add/edit profile modal |
| `ClaudeRouteEditSheet.swift` | Add/edit folder route modal |
| `EnvrcDiffPreviewSheet.swift` | Diff preview before write |
| `ClaudeRotateSheet.swift` | Guided rotation flow |

---

## User Flows

### First Run

1. User opens **Settings → Claude** for the first time.
2. AIMeter shows an onboarding card:
   > **Get started**
   > 1. Run `claude setup-token` in your terminal.
   > 2. Paste the token into a profile below.
   > 3. AIMeter stages it to Keychain and writes the wiring.
3. Profile list contains one prefilled example row, italicized:
   > *Example — edit or delete me* · `claude-personal` · default · token field empty
4. User edits the example row, pastes their first token, hits Save.
5. AIMeter stages the token to Keychain (`security add-generic-password -s claude-personal …`).
6. Onboarding card collapses to a compact "Add another account" CTA.

### Add Profile

1. User clicks **+ Add Profile**.
2. Modal sheet: label input, slug input (auto-suggested from label, editable, validated against regex and uniqueness), token paste field (SecureField), optional notes.
3. On Save: AIMeter validates Keychain write succeeds, then persists the profile entry.
4. If this is the first profile and no default exists, it auto-becomes default.

### Route a Folder

1. User clicks **+ Add Folder Route** in the route table.
2. NSOpenPanel folder picker (security-scoped bookmark stored).
3. Profile picker dropdown (lists all defined profiles).
4. Save → diff preview sheet shows the `.envrc` change for that folder.
5. User clicks **Write `.envrc`** → AIMeter writes (atomic rename), then displays a confirmation with the `direnv allow` command:
   > Run this in the folder for direnv to pick up the change:
   > `direnv allow /Volumes/KhaiSSD/Documents/Github/work`
6. Diff preview also surfaces the first-time Keychain prompt warning:
   > **First time this `.envrc` runs**, macOS will ask "direnv wants to access your keychain." Click **Always Allow**. This happens once per binary.

### Delete Profile

1. User clicks delete on a profile row.
2. Confirmation modal enumerates affected folder routes:
   > Profile **Personal Max** (`claude-personal`) is referenced by 3 folder routes:
   > - /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
   > - /Volumes/KhaiSSD/Documents/Github/personal/Nimbus
   > - ~/Code/sandbox
3. Three explicit choices:
   - **Delete profile and remove routes** (regenerates affected `.envrc` files with the marker block removed)
   - **Delete profile and reassign routes to** [picker showing other profiles]
   - **Cancel**
4. Optional checkbox: **Keep Keychain entry** (default off; toggle on for rollback safety).
5. On confirm: delete Keychain entry (unless toggle on), update `.envrc` files, persist state.

### Rotate Token

1. User clicks **Rotate** on a profile row (manually triggered, or via age-badge red state).
2. Sheet walks through the steps:
   > **Rotate `claude-personal` token**
   > 1. Run `claude /logout && claude /login` in your terminal to refresh the underlying auth.
   > 2. Run `claude setup-token`.
   > 3. Paste the new token below.
3. On Save: AIMeter overwrites the Keychain entry, bumps `lastRotatedAt` to now. `.envrc` files unchanged (they reference Keychain by slug, which is stable).

---

## Failure Modes Table

| # | Landmine | Mitigation | Residual |
|---|---|---|---|
| 1 | `.envrc` overwrite stomps user's other env vars | Block-marker idiom (conda/nvm pattern); merge only between markers; mandatory diff preview | User edits inside markers → stomped on next regen. Acceptable; markers self-document |
| 2 | Silent missing Keychain entry → empty token → opaque `claude` failure | Pre-write check verifies entries readable; shell snippet drops `2>/dev/null`, emits stderr on missing entry | Entry deleted post-write → user sees stderr line, recovers in seconds |
| 3 | Deletion cascade orphans folder routes | Modal enumerates affected routes; three explicit choices: remove / reassign / cancel | User chooses "remove" hastily → routes lost but `.envrc` files cleanable via remove-block mode. Recoverable |
| 4 | Stale Keychain entries pile up over years | Default behavior: delete Keychain entry with profile; "Keep Keychain entry" toggle (default off) for rollback | Toggle wrong way → re-run `claude setup-token` recovers |
| 5 | Slug rename breaks `.envrc` references | Pin slug at creation; renames are label-only; UI shows slug as monospace under label | User confused why label rename doesn't update Keychain. Mitigated by "Keychain ID (immutable)" hint in edit sheet |
| 6 | First-shell Keychain prompt confuses user ("direnv wants to access your keychain") | Diff preview UI calls it out explicitly; "Reset Keychain ACL" helper button for users who clicked Deny | User clicks Deny anyway → recoverable via Keychain Access app |
| 7 | First-run blank-list dead end | Onboarding card with 3-step flow + one prefilled example profile (italicized "Example — edit or delete me") | User thinks example is real → italicized label clarifies |
| 8 | Token rotation / expiry | Age-based UI (green / yellow / orange / red badges by months elapsed); manual "Rotate" button per profile; no validation endpoint exists, no inference burn | Token revoked early server-side → user discovers via 401, hits Rotate, re-stages. Edge case |
| 9 | Editor + AIMeter race on `.envrc` | Atomic rename via temp-file + POSIX rename; AIMeter writes only on user-initiated Save; modern editors reload on file replace | User actively typing in `.envrc` at exact Save moment. Pathological, single-user |
| 10 | AIMeter crash mid-write corrupts `.envrc` | Same atomic rename primitive (write to `.envrc.aimeter-tmp`, fsync, rename). Crash before rename → original intact. Crash after → new file complete | APFS guarantees atomic rename. No half-state visible |

---

## Estimate Breakdown

| Task | Effort |
|---|---|
| Settings → Claude UI section (profile list + route table) | 0.5 day |
| `ClaudeRoutingStore` (persistence + Keychain CRUD) | 0.5 day |
| Profile CRUD UI (add/edit/delete/rename modals) | 0.5 day |
| Folder picker + security-scoped bookmark wiring | 0.25 day |
| `EnvrcWriter` (marker merge, atomic rename, remove-block mode) | 1 day |
| Diff preview sheet | 0.25 day |
| Token age UI (badges, age column) | 0.25 day |
| Rotate sheet (text + Keychain overwrite) | 0.25 day |
| Validation (slug regex, uniqueness, default invariant, broken-reference detection) | 0.5 day |
| First-run onboarding card + prefilled example | 0.25 day |
| Manual test pass + polish | 0.5 day |

**Total: 4.75 days.** Round to 4–5 focused days.

---

## Acceptance Criteria

- [ ] User can add N profiles via paste-token UI; tokens land in Keychain only (verify with `security find-generic-password -s claude-<slug> -w`)
- [ ] Folder routes regenerate `.envrc` files with marker-block merge; pre-existing user lines preserved (verify with sample `.envrc` containing `DATABASE_URL=...`)
- [ ] Diff preview shown before every write; user can cancel
- [ ] Profile delete with affected routes triggers cascade modal with three options
- [ ] Slug rename is rejected (slug field disabled in edit sheet); label rename succeeds
- [ ] Token age badge transitions green → yellow → orange → red across 0/9/11/12 month thresholds
- [ ] Rotate flow overwrites Keychain entry, bumps `lastRotatedAt`, leaves `.envrc` files untouched
- [ ] AIMeter never writes to `~/.zshrc` (verify by inspection + by greping shell rc after a full save cycle)
- [ ] Crash simulation (kill -9 mid-write) leaves `.envrc` either fully old or fully new — never corrupted
- [ ] Empty `claude-<slug>` Keychain entry → shell shows stderr line, does not silently set empty `CLAUDE_CODE_OAUTH_TOKEN`

---

## Open Questions for Khairul

None. All landmines neutralized, all design decisions locked. Ready for implementation handoff to a sonnet implementer.
