import Foundation

struct CodexProxyStore {
    static let defaultPort: UInt16 = 2455

    private let fileManager: FileManager = .default

    func writeConfig(port: UInt16 = defaultPort) throws {
        let directoryURL = codexDirectoryURL()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let existingConfig = readExistingConfig()
        let mergedConfig = mergeProxySettings(into: existingConfig, port: port)

        try mergedConfig.write(to: configURL(), atomically: true, encoding: .utf8)
    }

    private func readExistingConfig() -> String? {
        let url = configURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func mergeProxySettings(into existing: String?, port: UInt16) -> String {
        let proxySection = """
        [model_providers.aimeter-proxy]
        name = "OpenAI"
        base_url = "http://127.0.0.1:\(port)/backend-api/codex"
        wire_api = "responses"
        supports_websockets = false
        requires_openai_auth = true
        """

        guard let existing = existing else {
            return """
            model = "gpt-5.4"
            model_provider = "aimeter-proxy"

            \(proxySection)
            """
        }

        var resultLines: [String] = []
        var inAimeterSection = false
        var aimeterSectionInserted = false
        var hasRootModel = false
        var hasRootModelProvider = false

        let lines = existing.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // We are leaving whatever section we were in
                inAimeterSection = false

                if trimmed == "[model_providers.aimeter-proxy]" {
                    // Skip the old aimeter-proxy section entirely, insert new one at correct spot
                    inAimeterSection = true
                    if !aimeterSectionInserted {
                        resultLines.append(proxySection)
                        aimeterSectionInserted = true
                    }
                    // Skip all lines until we exit this section
                    i += 1
                    while i < lines.count {
                        let check = lines[i].trimmingCharacters(in: .whitespaces)
                        if check.hasPrefix("[") && check.hasSuffix("]") {
                            break
                        }
                        i += 1
                    }
                    continue
                } else {
                    resultLines.append(line)
                    i += 1
                    continue
                }
            }

            if inAimeterSection {
                // Skip lines that match our known keys; pass through everything else
                let key = trimmed.components(separatedBy: "=")[0].trimmingCharacters(in: .whitespaces)
                let knownKeys = ["name", "base_url", "wire_api", "supports_websockets", "requires_openai_auth"]
                if knownKeys.contains(key) {
                    i += 1
                    continue
                }
                resultLines.append(line)
                i += 1
                continue
            }

            // Root-level keys: replace model and model_provider
            if trimmed.lowercased().hasPrefix("model =") {
                hasRootModel = true
                resultLines.append("model = \"gpt-5.4\"")
                i += 1
                continue
            }
            if trimmed.lowercased().hasPrefix("model_provider =") {
                hasRootModelProvider = true
                resultLines.append("model_provider = \"aimeter-proxy\"")
                i += 1
                continue
            }

            // Pass through everything else
            resultLines.append(line)
            i += 1
        }

        // Prepend model and model_provider at the top if not found
        var finalLines: [String] = []
        if !hasRootModel {
            finalLines.append("model = \"gpt-5.4\"")
        }
        if !hasRootModelProvider {
            finalLines.append("model_provider = \"aimeter-proxy\"")
        }
        if !hasRootModel || !hasRootModelProvider {
            finalLines.append("")
        }

        // Insert aimeter-proxy section if it wasn't in the original
        if !aimeterSectionInserted {
            finalLines.append(proxySection)
        }

        finalLines.append(contentsOf: resultLines)

        return finalLines.joined(separator: "\n")
    }

    private func codexDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private func configURL() -> URL {
        codexDirectoryURL().appendingPathComponent("config.toml")
    }
}
