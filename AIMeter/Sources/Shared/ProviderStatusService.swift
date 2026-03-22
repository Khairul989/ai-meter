import Foundation
import SwiftUI

@MainActor
final class ProviderStatusService: ObservableObject {
    struct StatusInfo {
        let indicator: String   // "none", "minor", "major", "critical"
        let description: String // e.g. "All Systems Operational"
    }

    @Published var statuses: [String: StatusInfo] = [:]

    private let endpoints: [(provider: String, url: String)] = [
        ("Claude",  "https://status.anthropic.com/api/v2/status.json"),
        ("Copilot", "https://www.githubstatus.com/api/v2/status.json"),
        ("Codex",   "https://status.openai.com/api/v2/status.json"),
    ]

    private var timer: Timer?

    func start() {
        fetch()
        // Poll every 5 minutes — status is supplementary, no need for faster polling
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() {
        for endpoint in endpoints {
            Task {
                do {
                    guard let url = URL(string: endpoint.url) else { return }
                    let (data, _) = try await URLSession.shared.data(from: url)
                    // Statuspage.io format: { "status": { "indicator": "none", "description": "..." } }
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? [String: Any],
                       let indicator = status["indicator"] as? String,
                       let description = status["description"] as? String {
                        self.statuses[endpoint.provider] = StatusInfo(indicator: indicator, description: description)
                    }
                } catch {
                    // Silently ignore — status is supplementary info
                }
            }
        }
    }
}

// MARK: - ProviderStatusBannerView

struct ProviderStatusBannerView: View {
    let status: ProviderStatusService.StatusInfo

    private var dotColor: Color {
        status.indicator == "minor" ? .yellow : .red
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(status.description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Provider status: \(status.description)")
    }
}
