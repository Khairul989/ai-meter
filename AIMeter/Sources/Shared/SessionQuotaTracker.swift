import Foundation

@MainActor
final class SessionQuotaTracker {
    enum QuotaState {
        case normal
        case depleted
    }

    enum Transition {
        case depleted
        case restored
    }

    private var states: [String: QuotaState] = [:]

    /// Call this after each usage fetch. Returns the transition if one occurred.
    func update(provider: String, usagePercent: Double) -> Transition? {
        let currentState = states[provider] ?? .normal
        let isDepleted = usagePercent >= 99.9 // ≤0.1% remaining

        switch (currentState, isDepleted) {
        case (.normal, true):
            states[provider] = .depleted
            return .depleted
        case (.depleted, false):
            states[provider] = .normal
            return .restored
        default:
            return nil
        }
    }
}
