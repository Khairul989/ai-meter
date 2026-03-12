import SwiftUI

enum UsageColor {
    static func forUtilization(_ value: Int) -> Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        case ..<95: return .orange
        default: return .red
        }
    }

    static func levelDescription(_ value: Int) -> String {
        switch value {
        case ..<50:  "Normal"
        case ..<80:  "Elevated"
        case ..<95:  "High"
        default:     "Critical"
        }
    }
}
