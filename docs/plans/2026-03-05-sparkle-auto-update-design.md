# Sparkle Auto-Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Sparkle 2 auto-update so users get update prompts without rebuilding from source.

**Architecture:** Sparkle 2 added via SPM, wrapped in an `UpdaterManager` ObservableObject. Checks appcast.xml hosted on GitHub Releases on launch and via manual button. EdDSA signing (no Apple Developer Program needed).

**Tech Stack:** Swift/SwiftUI, Sparkle 2 (SPM), XcodeGen, GitHub Releases, EdDSA

---

## Task 1: Generate EdDSA Key Pair

**Context:** Sparkle uses EdDSA (ed25519) to verify update authenticity. We generate once, store public key in the app, keep private key local for signing releases.

**Step 1: Clone and build Sparkle tools locally**

Run:
```bash
cd /tmp && git clone https://github.com/sparkle-project/Sparkle.git --depth 1 --branch 2.x
cd Sparkle
xcodebuild -project Sparkle.xcodeproj -scheme generate_keys -configuration Release -derivedDataPath /tmp/sparkle-build ONLY_ACTIVE_ARCH=YES
```

**Step 2: Generate the EdDSA key pair**

Run:
```bash
/tmp/sparkle-build/Build/Products/Release/generate_keys
```

This outputs a public key string like `dFh1a2B3...=`. It stores the private key in your Keychain automatically under "Sparkle EdDSA Key".

**IMPORTANT:** Copy and save the public key — you'll need it in Task 3. The private key lives in your Keychain and is used by `sign_update` automatically.

**Step 3: Also build sign_update and generate_appcast for later**

Run:
```bash
xcodebuild -project /tmp/Sparkle/Sparkle.xcodeproj -scheme sign_update -configuration Release -derivedDataPath /tmp/sparkle-build ONLY_ACTIVE_ARCH=YES
xcodebuild -project /tmp/Sparkle/Sparkle.xcodeproj -scheme generate_appcast -configuration Release -derivedDataPath /tmp/sparkle-build ONLY_ACTIVE_ARCH=YES
```

**Step 4: Copy tools to project**

Run:
```bash
mkdir -p /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/scripts/sparkle-tools
cp /tmp/sparkle-build/Build/Products/Release/sign_update /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/scripts/sparkle-tools/
cp /tmp/sparkle-build/Build/Products/Release/generate_appcast /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/scripts/sparkle-tools/
```

Add `scripts/sparkle-tools/` to `.gitignore` (binary tools shouldn't be committed).

**Step 5: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
echo "scripts/sparkle-tools/" >> .gitignore
git add .gitignore
git commit -m "chore: add sparkle-tools to gitignore"
```

---

## Task 2: Add Sparkle SPM Dependency to project.yml

**Files:**
- Modify: `AIMeter/project.yml`

**Step 1: Add Sparkle package and dependency**

Add top-level `packages` key and add dependency to AIMeter target in `AIMeter/project.yml`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    majorVersion: 2

# ... existing targets section ...
targets:
  AIMeter:
    # ... existing config ...
    dependencies:
      - package: Sparkle
```

The full `AIMeter` target should look like:

```yaml
  AIMeter:
    type: application
    platform: macOS
    sources:
      - path: Sources/App
      - path: Sources/Shared
      - path: Resources/Assets.xcassets
    resources:
      - path: Resources
        excludes:
          - WidgetInfo.plist
          - AIMeterWidget.entitlements
          - Assets.xcassets
    info:
      path: Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: AIMeter
        CFBundleShortVersionString: "1.7.0"
        CFBundleVersion: "8"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.khairul.aimeter
        CODE_SIGN_ENTITLEMENTS: Resources/AIMeter.entitlements
        CODE_SIGN_IDENTITY: "Apple Development"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: "X4BB76AA4X"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    entitlements:
      path: Resources/AIMeter.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.application-groups:
          - group.com.khairul.aimeter
        keychain-access-groups:
          - $(AppIdentifierPrefix)com.khairul.aimeter
    dependencies:
      - package: Sparkle
```

**Step 2: Regenerate Xcode project**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
```

Expected: "Generated project AIMeter.xcodeproj" with no errors.

**Step 3: Verify Sparkle resolves**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodebuild -resolvePackageDependencies -project AIMeter.xcodeproj -scheme AIMeter
```

Expected: Sparkle package resolves successfully.

**Step 4: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/project.yml
git commit -m "feat: add Sparkle 2 SPM dependency"
```

---

## Task 3: Add Sparkle Config to Info.plist

**Files:**
- Modify: `AIMeter/project.yml` (Info.plist properties are managed via project.yml)

**Step 1: Add SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks**

In `AIMeter/project.yml`, under `targets.AIMeter.info.properties`, add:

```yaml
    info:
      path: Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: AIMeter
        CFBundleShortVersionString: "1.7.0"
        CFBundleVersion: "8"
        SUFeedURL: "https://github.com/Khairul989/ai-meter/releases/latest/download/appcast.xml"
        SUPublicEDKey: "<PASTE_YOUR_PUBLIC_KEY_FROM_TASK_1>"
        SUEnableAutomaticChecks: true
```

**IMPORTANT:** Replace `<PASTE_YOUR_PUBLIC_KEY_FROM_TASK_1>` with the actual EdDSA public key generated in Task 1.

**Step 2: Regenerate Xcode project**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
```

**Step 3: Verify plist has the keys**

Run:
```bash
grep -A1 "SUFeedURL\|SUPublicEDKey\|SUEnableAutomaticChecks" /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/AIMeter.xcodeproj/project.pbxproj
```

Expected: All three keys appear in the generated project.

**Step 4: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/project.yml
git commit -m "feat: add Sparkle feed URL and EdDSA public key to Info.plist"
```

---

## Task 4: Create UpdaterManager

**Files:**
- Create: `AIMeter/Sources/App/UpdaterManager.swift`

**Step 1: Write UpdaterManager**

Create `AIMeter/Sources/App/UpdaterManager.swift`:

```swift
import Foundation
import Sparkle

final class UpdaterManager: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
```

**Step 2: Build to verify it compiles**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/Sources/App/UpdaterManager.swift
git commit -m "feat: add UpdaterManager wrapping Sparkle updater controller"
```

---

## Task 5: Wire UpdaterManager into App

**Files:**
- Modify: `AIMeter/Sources/App/AIMeterApp.swift`

**Step 1: Add UpdaterManager as StateObject**

Add to `AIMeterApp`:

```swift
import SwiftUI

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @StateObject private var glmService = GLMService()
    @StateObject private var updaterManager = UpdaterManager()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                copilotService: copilotService,
                glmService: glmService,
                updaterManager: updaterManager
            )
            .task {
                service.start(interval: refreshInterval)
                copilotService.start(interval: refreshInterval)
                glmService.start(interval: refreshInterval)
            }
            .onChange(of: refreshInterval) { _, newValue in
                service.stop()
                service.start(interval: newValue)
                copilotService.stop()
                copilotService.start(interval: newValue)
                glmService.stop()
                glmService.start(interval: newValue)
            }
        } label: {
            MenuBarLabel(utilization: max(
                service.usageData.highestUtilization,
                copilotService.copilotData.highestUtilization,
                glmService.glmData.tokensPercent
            ))
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Step 2: Update PopoverView to accept updaterManager**

In `AIMeter/Sources/App/PopoverView.swift`, add the parameter to `PopoverView`:

```swift
struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var glmService: GLMService
    @ObservedObject var updaterManager: UpdaterManager
    // ... rest unchanged
```

Pass it to `InlineSettingsView`:

```swift
            case .settings:
                InlineSettingsView(updaterManager: updaterManager)
```

**Step 3: Build to verify**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES | tail -5
```

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/Sources/App/AIMeterApp.swift AIMeter/Sources/App/PopoverView.swift
git commit -m "feat: wire UpdaterManager into app and popover"
```

---

## Task 6: Add "Check for Updates" Button to Settings

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift` (InlineSettingsView)

**Step 1: Add updaterManager property and button**

Update `InlineSettingsView` to accept `UpdaterManager` and add the button between "Launch at login" and "GLM API Key":

```swift
struct InlineSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @AppStorage("refreshInterval") private var refreshInterval: Double = 100
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var launchAtLogin = false
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifyWarning") private var notifyWarning: Int = 80
    @AppStorage("notifyCritical") private var notifyCritical: Int = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ... existing settings content ...

            Toggle("Launch at login", isOn: $launchAtLogin)
                // ... existing onChange handler ...

            // --- NEW: Check for Updates button ---
            Button("Check for Updates...") {
                updaterManager.checkForUpdates()
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            // --- existing GLM API Key section continues below ---
            VStack(alignment: .leading, spacing: 8) {
                Text("GLM API Key")
                // ...
```

The button should appear right after the "Launch at login" toggle and before the "GLM API Key" section.

**Step 2: Build and verify**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES | tail -5
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/Sources/App/PopoverView.swift
git commit -m "feat: add Check for Updates button in settings"
```

---

## Task 7: Create Release Script

**Files:**
- Create: `scripts/release.sh`

**Step 1: Write the release script**

Create `scripts/release.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh v1.8.0 "feat: Sparkle auto-update"

VERSION="${1:?Usage: release.sh <version-tag> <release-title>}"
TITLE="${2:?Usage: release.sh <version-tag> <release-title>}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AIMETER_DIR="$PROJECT_DIR/AIMeter"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/AIMeter.xcarchive"
APP_PATH="$BUILD_DIR/AIMeter.app"
ZIP_PATH="$BUILD_DIR/AIMeter-${VERSION}.zip"
APPCAST_DIR="$BUILD_DIR/appcast"
SIGN_UPDATE="$PROJECT_DIR/scripts/sparkle-tools/sign_update"
GENERATE_APPCAST="$PROJECT_DIR/scripts/sparkle-tools/generate_appcast"

# Preflight checks
for tool in "$SIGN_UPDATE" "$GENERATE_APPCAST"; do
    if [[ ! -x "$tool" ]]; then
        echo "ERROR: $tool not found or not executable."
        echo "Build Sparkle tools first (see docs/plans/2026-03-05-sparkle-auto-update-design.md Task 1)"
        exit 1
    fi
done

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI required. Install: brew install gh"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "ERROR: xcodebuild required."; exit 1; }

echo "==> Regenerating Xcode project..."
cd "$AIMETER_DIR"
xcodegen generate

echo "==> Archiving AIMeter..."
xcodebuild archive \
    -project AIMeter.xcodeproj \
    -scheme AIMeter \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ONLY_ACTIVE_ARCH=NO \
    | tail -3

echo "==> Exporting .app from archive..."
mkdir -p "$BUILD_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/AIMeter.app" "$APP_PATH"

echo "==> Creating zip..."
cd "$BUILD_DIR"
ditto -c -k --keepParent "AIMeter.app" "$(basename "$ZIP_PATH")"

echo "==> Generating appcast..."
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/"
"$GENERATE_APPCAST" "$APPCAST_DIR"

echo "==> Creating GitHub Release $VERSION..."
gh release create "$VERSION" \
    --repo Khairul989/ai-meter \
    --title "$TITLE" \
    --notes "## What's New\n\n$TITLE\n\n## Install\n\nDownload AIMeter-${VERSION}.zip, unzip, and move AIMeter.app to /Applications.\nFirst launch: right-click -> Open to bypass Gatekeeper." \
    "$ZIP_PATH" \
    "$APPCAST_DIR/appcast.xml"

echo ""
echo "==> Release $VERSION published!"
echo "    https://github.com/Khairul989/ai-meter/releases/tag/$VERSION"
```

**Step 2: Make it executable**

Run:
```bash
chmod +x /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/scripts/release.sh
```

**Step 3: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add scripts/release.sh
git commit -m "feat: add release script for Sparkle-signed builds"
```

---

## Task 8: Update README with Install Instructions

**Files:**
- Modify: `README.md`

**Step 1: Add installation section**

Add to README.md:

```markdown
## Install (Pre-built)

1. Download the latest `AIMeter-vX.X.X.zip` from [Releases](https://github.com/Khairul989/ai-meter/releases/latest)
2. Unzip and move `AIMeter.app` to `/Applications`
3. **First launch only:** right-click the app -> "Open" (bypasses Gatekeeper for unsigned apps)
4. AIMeter appears in your menu bar

Updates are checked automatically on launch. You can also check manually via Settings -> "Check for Updates..."

## Build from Source

1. Clone the repo
2. `cd AIMeter && xcodegen generate`
3. Open `AIMeter.xcodeproj` in Xcode and run
```

**Step 2: Commit**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add README.md
git commit -m "docs: add install instructions for pre-built releases"
```

---

## Task 9: Test End-to-End

**Step 1: Build and run the app**

Run:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES | tail -5
```

Expected: BUILD SUCCEEDED

**Step 2: Run the app and verify**

Open the app, go to Settings tab, verify:
- "Check for Updates..." button is visible between "Launch at login" and "GLM API Key"
- Clicking it opens Sparkle's update dialog (will say "up to date" or fail to connect to appcast — both OK since no release exists yet)

**Step 3: Test release script (dry run)**

We can't fully test until we push, but verify the script runs preflight checks:
```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
./scripts/release.sh v1.8.0 "feat: Sparkle auto-update"
```

This will archive and build. If `gh` auth fails, that's expected in a dry run.

**Step 4: Final commit — version bump**

Update version in `project.yml` to v1.8.0 (CFBundleVersion: 9):

```yaml
        CFBundleShortVersionString: "1.8.0"
        CFBundleVersion: "9"
```

(Update both AIMeter and AIMeterWidget targets.)

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota
git add AIMeter/project.yml
git commit -m "feat: bump version to v1.8.0 for Sparkle auto-update release"
```
