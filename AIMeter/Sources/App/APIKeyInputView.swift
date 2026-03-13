import SwiftUI

/// Reusable "no API key" prompt with inline save field
struct APIKeyInputView: View {
    let providerName: String
    let placeholder: String
    let accentColor: Color
    let onSave: (String) -> Void

    @State private var keyInput: String = ""
    @State private var keySaved: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundColor(accentColor.opacity(0.6))
            Text("No \(providerName) API key found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Paste your API key below or add it in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                SecureField(placeholder, text: $keyInput)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                if !keyInput.isEmpty {
                    Button(keySaved ? "Saved ✓" : "Save") {
                        onSave(keyInput)
                        keySaved = true
                        keyInput = ""
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(keySaved ? .green : .accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
