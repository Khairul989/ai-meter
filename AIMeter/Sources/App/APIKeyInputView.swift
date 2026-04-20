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

struct ProviderAPIKeyEmptyStateView: View {
    let providerName: String
    let iconSystemName: String
    let iconAssetName: String?
    let headline: String
    let subtitle: String
    let placeholder: String
    let accentColor: Color
    let onSave: (String) -> Void

    @State private var keyInput: String = ""

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 68, height: 68)
                    if let iconAssetName {
                        Image(iconAssetName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .foregroundColor(accentColor)
                    } else {
                        Image(systemName: iconSystemName)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }

                VStack(spacing: 4) {
                    Text(headline)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                SecureField(placeholder, text: $keyInput)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                    keyInput = ""
                } label: {
                    Text("Connect")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1.0)
            }

            Text("You can also manage keys from Settings.")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        )
    }
}
