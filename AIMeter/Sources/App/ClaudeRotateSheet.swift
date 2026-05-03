import SwiftUI
import AppKit

// MARK: - ClaudeRotateSheet

struct ClaudeRotateSheet: View {
    @ObservedObject var store: ClaudeRoutingStore
    let profile: ClaudeProfile

    @Environment(\.dismiss) private var dismiss

    // MARK: - Field state

    @State private var newToken: String = ""
    @State private var errorMessage: String? = nil

    // MARK: - Derived

    private var canRotate: Bool {
        !newToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rotate token for ")
                    .font(.system(size: 14, weight: .semibold))
                + Text(profile.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Steps + token input
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepsSection
                    tokenInputSection
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer buttons — macOS convention: Cancel left, primary right
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rotate") {
                    rotate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRotate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 480, minHeight: 280)
    }

    // MARK: - Subviews

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(
                number: 1,
                text: "Run this in your terminal to refresh your Anthropic auth:",
                command: "claude /logout && claude /login"
            )
            stepRow(
                number: 2,
                text: "Then run this to generate a new token:",
                command: "claude setup-token"
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    stepBadge(3)
                    Text("Paste the new token below.")
                        .font(.system(size: 12))
                }
            }
        }
    }

    private func stepRow(number: Int, text: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                stepBadge(number)
                Text(text)
                    .font(.system(size: 12))
            }
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    // Indent to align with text above
                    .padding(.leading, 28)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Copy to clipboard")
            }
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(Color.accentColor)
            .clipShape(Circle())
    }

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New token")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            SecureField(
                "Run `claude setup-token` in Terminal, paste the result here",
                text: $newToken
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .onChange(of: newToken) { _ in
                errorMessage = nil
            }
        }
    }

    // MARK: - Actions

    private func rotate() {
        errorMessage = nil
        do {
            try store.rotateToken(id: profile.id, newToken: newToken.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch ClaudeRoutingStore.ValidationError.profileNotFound {
            errorMessage = "This profile no longer exists. Close this sheet and try again."
        } catch ClaudeProfileKeychainError.unhandled(let status) {
            errorMessage = "Couldn't save the token to your Keychain (status \(status)). Try again or check Keychain Access."
        } catch ClaudeProfileKeychainError.unexpectedData {
            errorMessage = "Keychain saved the token but didn't read it back correctly. Try again."
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }
    }
}
