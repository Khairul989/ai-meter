import SwiftUI

// MARK: - Token Age

private enum TokenAgeStatus {
    case fresh       // < 9 months
    case rotateSoon  // 9–11 months
    case rotateNow   // 11–12 months
    case expired     // ≥ 12 months
}

private func tokenAgeStatus(interval: TimeInterval) -> TokenAgeStatus {
    let months = interval / (86_400 * 30)
    if months < 9 { return .fresh }
    if months < 11 { return .rotateSoon }
    if months < 12 { return .rotateNow }
    return .expired
}

private func tokenAgeLabel(interval: TimeInterval) -> String {
    let days = Int(interval / 86_400)
    if days < 30 { return "\(days)d" }
    let months = days / 30
    if months < 12 { return "\(months) mo" }
    return "12+ mo"
}

// MARK: - DiffPreviewContext
// ProposedWrite is not Identifiable — wrap it so .sheet(item:) can use it.
// CONTRACT: slug must come from the route-edit sheet that owns the folder picker.

struct DiffPreviewContext: Identifiable {
    let id = UUID()
    let proposal: ProposedWrite
    let slug: String
    /// Persists the underlying route to the store. Invoked only after the user confirms
    /// the `.envrc` write; cancelling the preview must NOT call this.
    let commit: () -> Void
}

// MARK: - ClaudeRoutingView

struct ClaudeRoutingView: View {

    @StateObject private var store = ClaudeRoutingStore()

    // Sheet bindings
    @State private var showingAddProfile = false
    @State private var editingProfile: ClaudeProfile?
    @State private var rotatingProfile: ClaudeProfile?
    @State private var showingAddRoute = false
    @State private var editingRoute: ClaudeFolderRoute?
    @State private var diffPreview: DiffPreviewContext?

    // Cascade-delete state
    @State private var deletingProfile: ClaudeProfile?
    @State private var keepKeychain = false

    // Dismissed state persists across launches
    @AppStorage("claudeRoutingOnboardingDismissed") private var onboardingDismissed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            onboardingCardIfNeeded
            profilesPanel
            routesPanel
        }
        // Add / Edit Profile
        .sheet(isPresented: $showingAddProfile) {
            ClaudeProfileEditSheet(store: store, profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            ClaudeProfileEditSheet(store: store, profile: profile)
        }
        // Rotate token
        .sheet(item: $rotatingProfile) { profile in
            ClaudeRotateSheet(store: store, profile: profile)
        }
        // Add / Edit Folder Rule
        // CONTRACT: sibling sheet must accept (store:, route:, onProposeWrite:) where
        // onProposeWrite is (ProposedWrite, String, () -> Void) -> Void — the closure is
        // the deferred persistence action; it runs only when the diff preview confirms write.
        .sheet(isPresented: $showingAddRoute) {
            ClaudeRouteEditSheet(store: store, route: nil, onProposeWrite: { proposal, slug, commit in
                diffPreview = DiffPreviewContext(proposal: proposal, slug: slug, commit: commit)
            })
        }
        .sheet(item: $editingRoute) { route in
            ClaudeRouteEditSheet(store: store, route: route, onProposeWrite: { proposal, slug, commit in
                diffPreview = DiffPreviewContext(proposal: proposal, slug: slug, commit: commit)
            })
        }
        // Diff preview
        .sheet(item: $diffPreview) { ctx in
            EnvrcDiffPreviewSheet(proposal: ctx.proposal, slug: ctx.slug, onWriteCommitted: ctx.commit)
        }
        // Cascade-delete dialog
        .confirmationDialog(cascadeDialogTitle, isPresented: cascadeDialogBinding, titleVisibility: .visible) {
            cascadeDialogActions
        } message: {
            if let profile = deletingProfile {
                let count = store.routes(for: profile.id).count
                if count > 0 {
                    Text("\(count) folder \(count == 1 ? "rule" : "rules") point to this profile.")
                }
            }
        }
    }

    // MARK: - Onboarding

    @ViewBuilder
    private var onboardingCardIfNeeded: some View {
        // Show while no real profiles exist AND user hasn't dismissed it.
        if store.state.profiles.isEmpty && !onboardingDismissed {
            routingCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                        Text("Get started with folder routing")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button {
                            onboardingDismissed = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        onboardingStep("1", "Run `claude setup-token` in your terminal.")
                        onboardingStep("2", "Paste the token into a profile below.")
                        onboardingStep("3", "AIMeter stages it to Keychain and writes the wiring.")
                    }
                }
            }
        }
    }

    private func onboardingStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Profiles Panel

    private var profilesPanel: some View {
        routingCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Profiles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if store.state.profiles.isEmpty {
                    exampleProfileRow
                        .padding(.vertical, 2)
                } else {
                    ForEach(store.state.profiles) { profile in
                        profileRow(profile)
                        if profile.id != store.state.profiles.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }

                Divider().opacity(0.3)

                Button {
                    showingAddProfile = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
    }

    // Shown only when store is empty — renders a non-interactive placeholder
    // so the user understands the shape before adding their first real profile.
    private var exampleProfileRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Example — edit or delete me")
                    .font(.system(size: 13, weight: .medium))
                    .italic()
                    .foregroundColor(.secondary)
                Text("· claude-personal")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("default")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundColor(.accentColor)

            // Open the add sheet so the user can define their real first profile.
            Button("Edit") {
                showingAddProfile = true
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: ClaudeProfile) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Identity column
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text("· claude-\(profile.slug)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Default badge
            if profile.isDefault {
                Text("default")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundColor(.accentColor)
            }

            // Token-age badge
            tokenAgeBadge(profile: profile)

            // Actions
            Button("Rotate") {
                rotatingProfile = profile
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button("Edit") {
                editingProfile = profile
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button("Delete") {
                deletingProfile = profile
                keepKeychain = false
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private func tokenAgeBadge(profile: ClaudeProfile) -> some View {
        let anchor = profile.lastRotatedAt ?? profile.createdAt
        let interval = Date().timeIntervalSince(anchor)
        let status = tokenAgeStatus(interval: interval)
        let ageText = tokenAgeLabel(interval: interval)

        let (iconName, wordLabel, badgeColor): (String, String, Color) = {
            switch status {
            case .fresh:
                return ("clock.badge.checkmark", "Fresh", .green)
            case .rotateSoon:
                return ("clock.badge.exclamationmark", "Rotate soon", .yellow)
            case .rotateNow:
                return ("clock.badge.exclamationmark", "Rotate now", .orange)
            case .expired:
                return ("exclamationmark.triangle.fill", "Expired", .red)
            }
        }()

        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text("\(wordLabel) · \(ageText)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Routes Panel

    private var routesPanel: some View {
        routingCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Folder rules")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if store.state.routes.isEmpty {
                    Text("No folder rules yet. Add one to route a project folder to a specific profile.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.state.routes) { route in
                        routeRow(route)
                        if route.id != store.state.routes.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }

                Divider().opacity(0.3)

                Button {
                    showingAddRoute = true
                } label: {
                    Label("Add Folder Rule", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(store.state.profiles.isEmpty)
                .help(store.state.profiles.isEmpty ? "Add a Claude profile first." : "")
            }
        }
    }

    @ViewBuilder
    private func routeRow(_ route: ClaudeFolderRoute) -> some View {
        // Resolve the profile for display; nil means broken reference (defensive).
        let profile = store.state.profiles.first { $0.id == route.profileId }

        HStack(alignment: .center, spacing: 8) {
            // Folder path — truncated in the middle so both root and project name stay visible
            Text(route.folderPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .truncationMode(.middle)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)

            Text("→")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Profile identifier column
            VStack(alignment: .leading, spacing: 1) {
                if let profile {
                    Text(profile.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text("claude-\(profile.slug)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    // Broken reference — profile was deleted without cascade.
                    Text("Profile not found")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("Edit to reassign")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Edit") {
                editingRoute = route
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button("Delete") {
                store.deleteRoute(id: route.id)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    }

    // MARK: - Cascade Delete Dialog

    private var cascadeDialogTitle: String {
        guard let profile = deletingProfile else { return "Delete Profile" }
        return "Delete \"\(profile.label)\"?"
    }

    // Binding that activates the dialog whenever deletingProfile is set.
    private var cascadeDialogBinding: Binding<Bool> {
        Binding(
            get: { deletingProfile != nil },
            set: { if !$0 { deletingProfile = nil } }
        )
    }

    // Enumerate one button per remaining profile for reassignment (flat dialog idiom),
    // plus a remove-all button and cancel.
    // Flattening beats a two-step sheet for typical profile counts (2–5 profiles).
    @ViewBuilder
    private var cascadeDialogActions: some View {
        if let profile = deletingProfile {
            // "Remove routes" path — destructive
            let affectedCount = store.routes(for: profile.id).count
            let removeLabel = affectedCount > 0
                ? "Delete profile and remove its \(affectedCount) folder \(affectedCount == 1 ? "rule" : "rules")"
                : "Delete profile"
            Button(removeLabel, role: .destructive) {
                _ = store.deleteProfile(id: profile.id, keepKeychain: keepKeychain, routeAction: .removeRoutes)
                deletingProfile = nil
            }

            // One reassign button per remaining profile
            ForEach(store.state.profiles.filter { $0.id != profile.id }) { target in
                Button("Delete profile and reassign rules to \"\(target.label)\"") {
                    _ = store.deleteProfile(id: profile.id, keepKeychain: keepKeychain, routeAction: .reassignTo(target.id))
                    deletingProfile = nil
                }
            }

            // Keep Keychain toggle surfaced as a text note in the message (dialog buttons can't host controls).
            // The UX directive says default off; a dedicated toggle in the card below the dialog
            // is the SwiftUI-compatible solution.
            Button("Cancel", role: .cancel) {
                deletingProfile = nil
            }
        }
    }

    // MARK: - Card Helper
    // settingsSectionCard is private to SettingsView.swift — replicated here to match visuals.

    @ViewBuilder
    private func routingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
