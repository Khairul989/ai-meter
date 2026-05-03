import SwiftUI

// MARK: - ClaudeProfileEditSheet

struct ClaudeProfileEditSheet: View {
    @ObservedObject var store: ClaudeRoutingStore
    /// nil = adding new profile; non-nil = editing existing
    let profile: ClaudeProfile?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Field state

    @State private var label: String = ""
    @State private var slug: String = ""
    // Tracks whether user has manually edited the slug — stops auto-sync from label when true
    @State private var slugManuallyEdited: Bool = false
    @State private var token: String = ""
    @State private var notes: String = ""
    @State private var makeDefault: Bool = false
    @State private var showReplaceTokenHint: Bool = false
    @State private var errorMessage: String? = nil

    // MARK: - Derived

    private var isAdding: Bool { profile == nil }

    private var slugValidation: SlugValidation {
        validateSlug(slug)
    }

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isAdding {
            guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            guard case .valid = slugValidation else { return false }
        }
        return true
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isAdding ? "Add Profile" : "Edit Profile")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    labelField
                    keychainIdField
                    if isAdding {
                        tokenField
                    } else {
                        editModeTokenSection
                    }
                    notesField
                    if isAdding && !store.state.profiles.isEmpty {
                        defaultToggle
                    }
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
                Button(isAdding ? "Add Profile" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear(perform: populateForEdit)
    }

    // MARK: - Subviews

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Label")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            TextField("e.g. Personal Max", text: $label)
                .textFieldStyle(.roundedBorder)
                .onChange(of: label) { newValue in
                    // Auto-suggest slug from label in ADD mode until user edits it manually
                    if isAdding && !slugManuallyEdited {
                        slug = slugFromLabel(newValue)
                    }
                }
        }
    }

    private var keychainIdField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keychain ID")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if isAdding {
                HStack(spacing: 6) {
                    Text("claude-")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("personal", text: $slug)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: slug) { _ in
                            slugManuallyEdited = true
                            errorMessage = nil
                        }
                    // Live validation indicator
                    slugValidationBadge
                }

                // Show duplicate conflict immediately if slug is taken
                if case .duplicate(let existing) = slugValidation {
                    Text("That Keychain ID is already used by '\(existing)'. Choose another.")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            } else {
                // EDIT mode — slug is immutable
                Text("claude-\(profile?.slug ?? "")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                Text("Keychain ID is immutable to keep .envrc files stable.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var slugValidationBadge: some View {
        if slug.isEmpty {
            EmptyView()
        } else {
            switch slugValidation {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 13))
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13))
            case .duplicate:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13))
            }
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Token")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            SecureField(
                "Run `claude setup-token` in Terminal, paste the result here",
                text: $token
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
        }
    }

    private var editModeTokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if showReplaceTokenHint {
                Text("To replace the token, use the Rotate flow from the profile list. It guides you through re-authenticating and updates the Keychain safely.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Replace token…") {
                    showReplaceTokenHint = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Notes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(notes.count)/200")
                    .font(.system(size: 10))
                    .foregroundColor(notes.count > 180 ? .orange : .secondary)
            }
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(minHeight: 56, maxHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                // Enforce 200-char cap
                .onChange(of: notes) { newValue in
                    if newValue.count > 200 {
                        notes = String(newValue.prefix(200))
                    }
                }
        }
    }

    private var defaultToggle: some View {
        Toggle("Make this the default profile", isOn: $makeDefault)
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
    }

    // MARK: - Actions

    private func save() {
        errorMessage = nil
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesValue: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        if isAdding {
            do {
                let created = try store.addProfile(
                    label: trimmedLabel,
                    slug: slug,
                    token: token.trimmingCharacters(in: .whitespaces),
                    notes: notesValue
                )
                // Honor explicit default toggle — addProfile auto-defaults only the very first profile
                if makeDefault {
                    store.setDefault(id: created.id)
                }
                dismiss()
            } catch ClaudeRoutingStore.ValidationError.invalidSlug {
                errorMessage = "Keychain ID must start with a letter or number and use only lowercase letters, numbers, and dashes (max 31 chars)."
            } catch ClaudeRoutingStore.ValidationError.duplicateSlug {
                let existing = store.state.profiles.first { $0.slug == slug }?.label ?? "another profile"
                errorMessage = "That Keychain ID is already used by '\(existing)'. Choose another."
            } catch ClaudeProfileKeychainError.unhandled(let status) {
                errorMessage = "Couldn't save the token to your Keychain (status \(status)). Try again or check Keychain Access."
            } catch ClaudeProfileKeychainError.unexpectedData {
                errorMessage = "Keychain saved the token but didn't read it back correctly. Try again."
            } catch {
                errorMessage = "Unexpected error: \(error.localizedDescription)"
            }
        } else {
            guard let existing = profile else { return }
            store.updateProfileLabel(id: existing.id, label: trimmedLabel)
            store.updateProfileNotes(id: existing.id, notes: notesValue)
            dismiss()
        }
    }

    private func populateForEdit() {
        guard let p = profile else { return }
        label = p.label
        notes = p.notes ?? ""
        // slug and token are not editable in EDIT mode — don't populate
    }

    // MARK: - Slug Helpers

    /// Derives a slug from a label string: lowercase + replace whitespace with `-` + strip invalid chars
    private func slugFromLabel(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespaces)
            .joined(separator: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private enum SlugValidation {
        case valid
        case invalid
        case duplicate(existingLabel: String)
    }

    private func validateSlug(_ s: String) -> SlugValidation {
        guard !s.isEmpty else { return .invalid }
        let pattern = "^[a-z0-9][a-z0-9-]{0,30}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        guard regex?.firstMatch(in: s, range: range) != nil else { return .invalid }
        if let existing = store.state.profiles.first(where: { $0.slug == s }) {
            return .duplicate(existingLabel: existing.label)
        }
        return .valid
    }
}
