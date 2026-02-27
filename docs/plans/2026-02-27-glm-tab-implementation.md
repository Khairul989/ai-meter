# GLM Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a GLM tab to AIMeter showing Z.ai token quota percentage and account tier, with API key sourced from `GLM_API_KEY` env var or manually entered via Settings (saved to Keychain).

**Architecture:** Follows the exact same pattern as `CopilotService` / `CopilotUsageData`. New `GLMUsageData` struct + `GLMService` + `GLMKeychainHelper`. `PopoverView` gets a new `.glm` tab case. `InlineSettingsView` gets a GLM API key section. Key resolution: env var first, Keychain fallback.

**Tech Stack:** SwiftUI, Foundation, Security (Keychain), Combine, macOS 14+

---

### Task 1: Create GLMUsageData

**Files:**
- Create: `AIMeter/Sources/Shared/GLMUsageData.swift`

**Step 1: Create the file**

```swift
import Foundation

struct GLMUsageData: Codable, Equatable {
    let tokensPercent: Int   // TOKENS_LIMIT.percentage
    let tier: String         // data.level e.g. "pro"
    let fetchedAt: Date

    static let empty = GLMUsageData(
        tokensPercent: 0,
        tier: "",
        fetchedAt: .distantPast
    )
}
```

**Step 2: Verify it compiles**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` (no errors)

---

### Task 2: Create GLMKeychainHelper

For manually-entered API keys saved to Keychain. Service name: `"glm-api-key"`.

**Files:**
- Create: `AIMeter/Sources/Shared/GLMKeychainHelper.swift`

**Step 1: Create the file**

```swift
import Foundation
import Security

enum GLMKeychainHelper {
    private static let serviceName = "glm-api-key"

    static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    static func saveAPIKey(_ key: String) {
        let data = Data(key.utf8)
        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

**Step 2: Verify it compiles**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 3: Create GLMService

**Files:**
- Create: `AIMeter/Sources/App/GLMService.swift`

**Step 1: Create the file**

```swift
import Foundation
import Combine

@MainActor
final class GLMService: ObservableObject {
    @Published var glmData: GLMUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: GLMError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60

    enum GLMError: Equatable {
        case noKey
        case fetchFailed
    }

    /// Resolve API key: env var first, Keychain fallback
    static func resolveAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return GLMKeychainHelper.readAPIKey()
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() async {
        guard let apiKey = GLMService.resolveAPIKey() else {
            self.error = .noKey
            return
        }

        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(GLMAPIResponse.self, from: data)
            guard decoded.success else {
                self.isStale = true
                self.error = .fetchFailed
                return
            }

            let tokensPercent = decoded.data.limits
                .first(where: { $0.type == "TOKENS_LIMIT" })?.percentage ?? 0
            let tier = decoded.data.level

            self.glmData = GLMUsageData(
                tokensPercent: tokensPercent,
                tier: tier,
                fetchedAt: Date()
            )
            self.isStale = false
            self.error = nil
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}

// MARK: - API response models (private, only used for decoding)

private struct GLMAPIResponse: Decodable {
    let success: Bool
    let data: GLMAPIData
}

private struct GLMAPIData: Decodable {
    let limits: [GLMLimit]
    let level: String
}

private struct GLMLimit: Decodable {
    let type: String
    let percentage: Int?
}
```

**Step 2: Verify it compiles**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 4: Add GLMTabView to PopoverView.swift

Wire up the new tab in the UI. This touches `Tab` enum, `PopoverView`, `TabBarView`, and adds the `GLMTabView` struct.

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift`

**Step 1: Add `.glm` to the `Tab` enum (line 7)**

Change:
```swift
enum Tab {
    case claude, copilot, settings
}
```
To:
```swift
enum Tab {
    case claude, copilot, glm, settings
}
```

**Step 2: Add `glmService` to `PopoverView` (after line 14)**

Change:
```swift
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
```
To:
```swift
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var glmService: GLMService
```

**Step 3: Update `overallHighestUtilization` to include GLM (line 23)**

Change:
```swift
    private var overallHighestUtilization: Int {
        max(service.usageData.highestUtilization, copilotService.copilotData.highestUtilization)
    }
```
To:
```swift
    private var overallHighestUtilization: Int {
        max(service.usageData.highestUtilization,
            copilotService.copilotData.highestUtilization,
            glmService.glmData.tokensPercent)
    }
```

**Step 4: Add `.glm` case to the content switch (after the `.copilot` case)**

Change:
```swift
            case .copilot:
                CopilotTabView(copilotService: copilotService, timeZone: configuredTimeZone)
            case .settings:
```
To:
```swift
            case .copilot:
                CopilotTabView(copilotService: copilotService, timeZone: configuredTimeZone)
            case .glm:
                GLMTabView(glmService: glmService)
            case .settings:
```

**Step 5: Update `isStale` computed property**

Change:
```swift
    private var isStale: Bool {
        switch selectedTab {
        case .claude: return service.isStale
        case .copilot: return copilotService.isStale
        case .settings: return false
        }
    }
```
To:
```swift
    private var isStale: Bool {
        switch selectedTab {
        case .claude: return service.isStale
        case .copilot: return copilotService.isStale
        case .glm: return glmService.isStale
        case .settings: return false
        }
    }
```

**Step 6: Update `updatedText` computed property**

Change:
```swift
    private var updatedText: String {
        let fetchedAt: Date
        switch selectedTab {
        case .claude: fetchedAt = service.usageData.fetchedAt
        case .copilot: fetchedAt = copilotService.copilotData.fetchedAt
        case .settings: return ""
        }
```
To:
```swift
    private var updatedText: String {
        let fetchedAt: Date
        switch selectedTab {
        case .claude: fetchedAt = service.usageData.fetchedAt
        case .copilot: fetchedAt = copilotService.copilotData.fetchedAt
        case .glm: fetchedAt = glmService.glmData.fetchedAt
        case .settings: return ""
        }
```

**Step 7: Add GLM tab button to `TabBarView.body`**

Change:
```swift
            tabButton(.claude,   icon: .asset("claude"),   label: "Claude")
            tabButton(.copilot,  icon: .asset("copilot"),  label: "Copilot")
            Spacer()
            tabButton(.settings, icon: .system("gear"),     label: nil)
```
To:
```swift
            tabButton(.claude,   icon: .asset("claude"),   label: "Claude")
            tabButton(.copilot,  icon: .asset("copilot"),  label: "Copilot")
            tabButton(.glm,      icon: .system("z.square"), label: "GLM")
            Spacer()
            tabButton(.settings, icon: .system("gear"),     label: nil)
```

**Step 8: Add GLMTabView struct at the bottom of the file (after CopilotTabView)**

Find the end of `CopilotTabView` and add after it:

```swift
// MARK: - GLMTabView

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService

    var body: some View {
        if glmService.error == .noKey {
            noKeyView
        } else {
            VStack(spacing: 8) {
                UsageCardView(
                    title: "5hr Token Quota",
                    icon: "z.square",
                    value: "\(glmService.glmData.tokensPercent)%",
                    utilization: glmService.glmData.tokensPercent
                )
                if !glmService.glmData.tier.isEmpty {
                    HStack {
                        Text("Account")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(glmService.glmData.tier.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var noKeyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No API key found")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add your GLM_API_KEY in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
```

**Step 9: Verify it compiles**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 5: Wire GLMService into AIMeterApp.swift

**Files:**
- Modify: `AIMeter/Sources/App/AIMeterApp.swift`

**Step 1: Add `glmService` StateObject**

Change:
```swift
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
```
To:
```swift
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @StateObject private var glmService = GLMService()
```

**Step 2: Pass `glmService` to `PopoverView`**

Change:
```swift
            PopoverView(service: service, copilotService: copilotService)
                .task {
                    service.start(interval: refreshInterval)
                    copilotService.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue)
                    copilotService.stop()
                    copilotService.start(interval: newValue)
                }
```
To:
```swift
            PopoverView(service: service, copilotService: copilotService, glmService: glmService)
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
```

**Step 3: Update `MenuBarLabel` utilization to include GLM**

Change:
```swift
        } label: {
            MenuBarLabel(utilization: max(service.usageData.highestUtilization, copilotService.copilotData.highestUtilization))
        }
```
To:
```swift
        } label: {
            MenuBarLabel(utilization: max(
                service.usageData.highestUtilization,
                copilotService.copilotData.highestUtilization,
                glmService.glmData.tokensPercent
            ))
        }
```

**Step 4: Verify it compiles**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 6: Add GLM API Key section to InlineSettingsView

Find `InlineSettingsView` in `PopoverView.swift` (it's used in the settings tab — check if it's in `SettingsView.swift` or `PopoverView.swift`).

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift` (InlineSettingsView is likely here, check first)

**Step 1: Read the file to find InlineSettingsView**

```bash
grep -n "InlineSettingsView" AIMeter/Sources/App/PopoverView.swift AIMeter/Sources/App/SettingsView.swift
```

**Step 2: Add state vars for GLM key management**

At the top of `InlineSettingsView`, add:
```swift
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    private var glmKeyFromEnv: Bool { GLMService.keyIsFromEnvironment }
    private var glmKeyInKeychain: Bool { GLMKeychainHelper.readAPIKey() != nil }
```

**Step 3: Add GLM API Key row to the Form/VStack**

Add this section before the Quit button:

```swift
            // GLM API Key
            if glmKeyFromEnv {
                HStack {
                    Text("GLM API Key")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("From GLM_API_KEY env")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if glmKeyInKeychain && glmKeyInput.isEmpty {
                HStack {
                    Text("GLM API Key")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("••••••••")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Clear") {
                        GLMKeychainHelper.deleteAPIKey()
                        glmKeySaved = false
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            } else {
                HStack {
                    SecureField("GLM API Key", text: $glmKeyInput)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                    if !glmKeyInput.isEmpty {
                        Button(glmKeySaved ? "Saved ✓" : "Save") {
                            GLMKeychainHelper.saveAPIKey(glmKeyInput)
                            glmKeySaved = true
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(glmKeySaved ? .green : .accentColor)
                    }
                }
            }
```

**Step 4: Verify it compiles**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 7: Run xcodegen and do a full build

New Swift files were added — xcodegen must be re-run to include them in the project.

**Step 1: Run xcodegen**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate 2>&1 | tail -5
```

Expected: `Created project at .../AIMeter.xcodeproj`

**Step 2: Full build**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`
