import SwiftUI

enum UsageColor {
    /// Read thresholds from UserDefaults, with sensible defaults
    private static var elevatedThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdElevated") as? Int ?? 50
    }

    private static var highThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdHigh") as? Int ?? 80
    }

    private static var criticalThreshold: Int {
        UserDefaults.standard.object(forKey: "colorThresholdCritical") as? Int ?? 95
    }

    private static func normalizedThresholds() -> (elevated: Int, high: Int, critical: Int) {
        let elevated = min(max(elevatedThreshold, 0), 98)
        let high = min(max(highThreshold, elevated + 1), 99)
        let critical = min(max(criticalThreshold, high + 1), 100)
        return (elevated, high, critical)
    }

    static var utilizationGradient: LinearGradient {
        let thresholds = normalizedThresholds()
        let elevated = Double(thresholds.elevated) / 100
        let high = Double(thresholds.high) / 100
        let critical = Double(thresholds.critical) / 100

        return LinearGradient(
            stops: [
                .init(color: .green, location: 0.0),
                .init(color: .yellow, location: elevated),
                .init(color: .orange, location: high),
                .init(color: .red, location: critical),
                .init(color: .red, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func forUtilization(_ value: Int) -> Color {
        let thresholds = normalizedThresholds()
        switch value {
        case ..<thresholds.elevated: return .green
        case ..<thresholds.high: return .yellow
        case ..<thresholds.critical: return .orange
        default: return .red
        }
    }

    static func levelDescription(_ value: Int) -> String {
        let thresholds = normalizedThresholds()
        switch value {
        case ..<thresholds.elevated:
            return "Normal"
        case ..<thresholds.high:
            return "Elevated"
        case ..<thresholds.critical:
            return "High"
        default:
            return "Critical"
        }
    }
}
