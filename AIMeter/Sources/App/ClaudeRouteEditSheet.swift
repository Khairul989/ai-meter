import SwiftUI
import AppKit

// MARK: - ClaudeRouteEditSheet

struct ClaudeRouteEditSheet: View {
    @ObservedObject var store: ClaudeRoutingStore
    /// nil = adding new folder rule; non-nil = editing existing
    let route: ClaudeFolderRoute?
    /// Closure receives the diff proposal, the profile slug, and a `commit` action that
    /// persists the route to the store. The diff preview sheet must invoke `commit` ONLY
    /// after the user confirms the write — cancelling must leave the store untouched.
    let onProposeWrite: (ProposedWrite, String, @escaping () -> Void) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Field state

    @State private var selectedFolderURL: URL? = nil
    @State private var folderDisplayPath: String = ""
    @State private var selectedProfileId: UUID? = nil
    @State private var errorMessage: String? = nil

    // MARK: - Derived

    private var isAdding: Bool { route == nil }

    private var canContinue: Bool {
        selectedFolderURL != nil && selectedProfileId != nil
    }

    private var selectedProfile: ClaudeProfile? {
        guard let id = selectedProfileId else { return nil }
        return store.state.profiles.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isAdding ? "Add Folder Rule" : "Edit Folder Rule")
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
                    folderPickerSection
                    profilePickerSection
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
                Button(isAdding ? "Continue" : "Save") {
                    continueAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear(perform: populateForEdit)
    }

    // MARK: - Subviews

    private var folderPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Button("Choose folder…") {
                pickFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if !folderDisplayPath.isEmpty {
                Text(folderDisplayPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private var profilePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Use Claude account:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Menu-based picker for reliable rich row rendering
            Menu {
                ForEach(store.state.profiles) { p in
                    Button {
                        selectedProfileId = p.id
                    } label: {
                        Text("\(p.label)  ·  claude-\(p.slug)")
                    }
                }
            } label: {
                if let profile = selectedProfile {
                    HStack(spacing: 4) {
                        Text(profile.label)
                            .font(.system(size: 12))
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("claude-\(profile.slug)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                } else {
                    HStack {
                        Text("Select an account")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            Text("When you `cd` into this folder, `direnv` will activate this account's token.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder to associate with a Claude account."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Store a security-scoped bookmark so the sandbox can re-access the folder later
        do {
            _ = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            selectedFolderURL = url
            folderDisplayPath = url.path
            errorMessage = nil
        } catch {
            // Bookmark creation can fail on non-sandboxed builds; fall back to storing URL directly
            selectedFolderURL = url
            folderDisplayPath = url.path
            errorMessage = nil
        }
    }

    private func continueAction() {
        errorMessage = nil

        guard let folderURL = selectedFolderURL,
              let profileId = selectedProfileId,
              let profile = selectedProfile else {
            errorMessage = "Please choose a folder and select an account."
            return
        }

        // Generate bookmark data for persistent sandboxed access
        let bookmarkData: Data
        do {
            bookmarkData = try folderURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Fallback for non-sandboxed environments
            bookmarkData = Data()
        }

        // Generate the proposed .envrc change before persisting state
        let proposal: ProposedWrite
        do {
            proposal = try EnvrcWriter.proposedContents(folderURL: folderURL, slug: profile.slug)
        } catch {
            errorMessage = "Couldn't read the folder's .envrc file. Check that the folder exists and is readable."
            return
        }

        // Defer persistence — only commit to the store if the user confirms the .envrc write.
        // Cancelling the diff preview must leave the store untouched (no orphan routes).
        let storeRef = store
        let isAddingNow = isAdding
        let existingRoute = route
        let folderPath = folderURL.path
        let commitToStore: () -> Void = {
            if isAddingNow {
                storeRef.addRoute(
                    folderBookmark: bookmarkData,
                    folderPath: folderPath,
                    profileId: profileId
                )
            } else if let existing = existingRoute {
                storeRef.updateRouteProfile(id: existing.id, profileId: profileId)
            }
        }

        onProposeWrite(proposal, profile.slug, commitToStore)
        dismiss()
    }

    private func populateForEdit() {
        guard let r = route else {
            // Pre-select the default profile for new rules
            selectedProfileId = store.state.profiles.first(where: { $0.isDefault })?.id
                ?? store.state.profiles.first?.id
            return
        }
        // Restore folder path for edit mode
        folderDisplayPath = r.folderPath
        selectedProfileId = r.profileId

        // Attempt to resolve the security-scoped bookmark to get the live URL
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: r.folderBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            selectedFolderURL = url
        } else {
            // Fallback: reconstruct from stored path string
            selectedFolderURL = URL(fileURLWithPath: r.folderPath)
        }
    }
}
