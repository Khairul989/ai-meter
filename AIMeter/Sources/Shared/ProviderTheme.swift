import SwiftUI

enum ProviderTheme: String, CaseIterable {
    case claude, copilot, glm, kimi

    var accentColor: Color {
        switch self {
        case .claude:  Color(red: 0.85, green: 0.55, blue: 0.35)
        case .copilot: Color(red: 0.35, green: 0.55, blue: 0.85)
        case .glm:     Color(red: 0.25, green: 0.75, blue: 0.65)
        case .kimi:    Color(red: 0.65, green: 0.45, blue: 0.85)
        }
    }

    var displayName: String {
        switch self {
        case .claude:  "Claude"
        case .copilot: "Copilot"
        case .glm:     "GLM"
        case .kimi:    "Kimi"
        }
    }
}
