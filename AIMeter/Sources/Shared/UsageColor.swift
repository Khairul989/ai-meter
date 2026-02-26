import SwiftUI

enum UsageColor {
    static func forUtilization(_ value: Int) -> Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}
