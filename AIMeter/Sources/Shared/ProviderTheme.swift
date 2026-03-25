import SwiftUI

enum ProviderTheme: String, CaseIterable {
    case claude, copilot, glm, kimi, codex, minimax

    var accentColor: Color {
        switch self {
        case .claude:   Color(red: 0.85, green: 0.55, blue: 0.35)
        case .copilot:  Color(red: 0.35, green: 0.55, blue: 0.85)
        case .glm:      Color(red: 0.25, green: 0.75, blue: 0.65)
        case .kimi:     Color(red: 0.65, green: 0.45, blue: 0.85)
        case .codex:    Color(red: 0.10, green: 0.75, blue: 0.55)
        case .minimax:  Color(red: 0.95, green: 0.30, blue: 0.40)
        }
    }

    var displayName: String {
        switch self {
        case .claude:   "Claude"
        case .copilot:  "Copilot"
        case .glm:      "GLM"
        case .kimi:     "Kimi"
        case .codex:    "Codex"
        case .minimax:  "MiniMax"
        }
    }
}
