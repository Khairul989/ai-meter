import Foundation

struct ClaudeSwitcherStatus: Equatable {
    let providerSettingsDirectoryExists: Bool
    let zshWrapperDetected: Bool
    let aiMeterBridgeInstalled: Bool

    var isInstalled: Bool {
        providerSettingsDirectoryExists || zshWrapperDetected
    }

    var note: String? {
        guard isInstalled else { return nil }
        return "Affects the default claude command only. Custom switcher commands like minimax use their own settings."
    }
}

struct ClaudeProxyStore {
    static let defaultPort: UInt16 = 2466

    private struct Metadata: Codable {
        let port: UInt16
        let enabledAt: Date
        let mode: String
    }

    private let fileManager: FileManager = .default
    private let injectedEnvKeys: [String] = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "CLAUDE_CODE_SUBAGENT_MODEL",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
        "NIMBUS_PROFILE"
    ]

    func isEnabled() -> Bool {
        fileManager.fileExists(atPath: metadataURL().path)
    }

    func activate(port: UInt16 = defaultPort) throws {
        try ensureSupportDirectory()
        try installLaunchBridge()

        let settingsURL = defaultClaudeSettingsURL()
        let existing = readJSONObject(at: settingsURL)
        let routedSettings = generatedProxySettings(from: existing, port: port)
        try writeJSONObject(routedSettings, to: proxySettingsURL())

        let metadata = Metadata(port: port, enabledAt: Date(), mode: "chatgpt")
        let encoded = try JSONEncoder.appEncoder.encode(metadata)
        try encoded.write(to: metadataURL(), options: .atomic)
    }

    func deactivate() throws {
        try? fileManager.removeItem(at: metadataURL())
    }

    func detectedSwitcherStatus() -> ClaudeSwitcherStatus {
        let zshrcURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
        let zshrc = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        let wrapperDetected = zshrc.contains("AI Provider Switcher")
            || zshrc.contains("CLAUDE_SWITCHER_SETTINGS")
            || zshrc.contains("_switch_provider()")
        let aiMeterBridgeInstalled = zshrc.contains("AIMETER_CLAUDE_ROUTE_STATE=")

        return ClaudeSwitcherStatus(
            providerSettingsDirectoryExists: fileManager.fileExists(atPath: claudeSwitcherSettingsDirectoryURL().path),
            zshWrapperDetected: wrapperDetected,
            aiMeterBridgeInstalled: aiMeterBridgeInstalled
        )
    }

    private func proxyEnvironment(port: UInt16) -> [String: String] {
        [
            "ANTHROPIC_BASE_URL": "http://127.0.0.1:\(port)",
            "ANTHROPIC_AUTH_TOKEN": "aimeter-local-proxy",
            "ANTHROPIC_MODEL": "sonnet",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "opus",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "sonnet",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "haiku",
            "CLAUDE_CODE_SUBAGENT_MODEL": "haiku",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "NIMBUS_PROFILE": "lite"
        ]
    }

    private func generatedProxySettings(from existing: [String: Any], port: UInt16) -> [String: Any] {
        var merged = existing
        var env = merged["env"] as? [String: Any] ?? [:]
        injectedEnvKeys.forEach { env.removeValue(forKey: $0) }
        proxyEnvironment(port: port).forEach { env[$0.key] = $0.value }
        merged["env"] = env
        return merged
    }

    private func ensureSupportDirectory() throws {
        let directoryURL = supportDirectoryURL()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func readJSONObject(at url: URL) -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func writeJSONObject(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func defaultClaudeSettingsURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func supportDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("aimeter", isDirectory: true)
    }

    private func proxySettingsURL() -> URL {
        supportDirectoryURL().appendingPathComponent("chatgpt-proxy.json")
    }

    private func metadataURL() -> URL {
        supportDirectoryURL().appendingPathComponent("claude-proxy-state.json")
    }

    private func claudeSwitcherSettingsDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("claude-switcher", isDirectory: true)
            .appendingPathComponent("settings", isDirectory: true)
    }

    private func installLaunchBridge() throws {
        let zshrcURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
        let original = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        let updated = bridgedZshrc(from: original)
        guard updated != original else { return }
        try updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
    }

    private func bridgedZshrc(from source: String) -> String {
        let claudeSectionStart = "# ---------- CLAUDE ----------"
        let claudeSectionEnd = "# ---------- PROVIDER SWITCH ----------"

        let replacement = """
# ---------- CLAUDE ----------
AIMETER_CLAUDE_ROUTE_STATE="$HOME/.claude/aimeter/claude-proxy-state.json"
AIMETER_CLAUDE_ROUTE_SETTINGS="$HOME/.claude/aimeter/chatgpt-proxy.json"

_aimeter_claude_route_enabled() {
  [ -f "$AIMETER_CLAUDE_ROUTE_STATE" ] || return 1
  grep -q '"mode"[[:space:]]*:[[:space:]]*"chatgpt"' "$AIMETER_CLAUDE_ROUTE_STATE"
}

_aimeter_run_claude_default() {
  echo "Using Claude Subscription"
  _copy_essentials_to_clipboard
  _run_claude "$@"
}

_aimeter_run_claude_route() {
  if _aimeter_claude_route_enabled && [ -f "$AIMETER_CLAUDE_ROUTE_SETTINGS" ]; then
    echo "Using ChatGPT via AIMeter"
    _copy_essentials_to_clipboard
    _run_claude --settings "$AIMETER_CLAUDE_ROUTE_SETTINGS" "$@"
    return $?
  fi

  _aimeter_run_claude_default "$@"
}

claude() {
  clear_provider_env
  _aimeter_run_claude_route "$@"
}

"""

        if let startRange = source.range(of: claudeSectionStart),
           let endRange = source.range(of: claudeSectionEnd, range: startRange.upperBound..<source.endIndex) {
            return source.replacingCharacters(in: startRange.lowerBound..<endRange.lowerBound, with: replacement)
        }

        if source.contains("AIMETER_CLAUDE_ROUTE_STATE=") {
            return source
        }

        return source + "\n\n" + replacement
    }
}
