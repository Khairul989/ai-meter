import Foundation
import os

// MARK: - Data Model

struct ClaudeProfile: Identifiable, Codable {
    let id: UUID
    /// Immutable — used as Keychain service ID. Only labels can be renamed.
    let slug: String
    var label: String
    var notes: String?
    var isDefault: Bool
    let createdAt: Date
    /// Explicit rotation timestamp. Nil means token has never been rotated since creation.
    var lastRotatedAt: Date?
}

struct ClaudeFolderRoute: Identifiable, Codable {
    let id: UUID
    /// Security-scoped bookmark for sandboxed file access.
    let folderBookmark: Data
    /// Display copy — resolved once at creation.
    let folderPath: String
    var profileId: UUID
}

struct ClaudeRoutingState: Codable {
    var profiles: [ClaudeProfile]
    var routes: [ClaudeFolderRoute]
}

// MARK: - Store

@MainActor
final class ClaudeRoutingStore: ObservableObject {

    @Published private(set) var state: ClaudeRoutingState

    // MARK: - Cascade option for profile deletion

    enum RouteCascade {
        case removeRoutes
        case reassignTo(UUID)
    }

    // MARK: - Errors

    enum ValidationError: Error {
        case invalidSlug
        case duplicateSlug
        case profileNotFound
    }

    // MARK: - Private

    // Compiled once — slug must start with lowercase alphanumeric,
    // followed by up to 30 lowercase-alphanumeric-or-hyphen chars (31 total max).
    private static let slugRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]{0,30}$")
    }()

    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "ClaudeRoutingStore")

    private static var storeURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("AIMeter", isDirectory: true)
            .appendingPathComponent("claude-routing.json")
    }

    // MARK: - Init

    init() {
        self.state = Self.load()
    }

    // MARK: - Profile CRUD

    /// Add a new profile and store its token in Keychain.
    /// - Throws `ValidationError` for bad/duplicate slug, or `ClaudeProfileKeychainError` on Keychain failure.
    @discardableResult
    func addProfile(
        label: String,
        slug: String,
        token: String,
        notes: String?
    ) throws -> ClaudeProfile {
        guard isValidSlug(slug) else {
            throw ValidationError.invalidSlug
        }
        guard !state.profiles.contains(where: { $0.slug == slug }) else {
            throw ValidationError.duplicateSlug
        }

        // Auto-default if this is the first profile.
        let isFirst = state.profiles.isEmpty
        let profile = ClaudeProfile(
            id: UUID(),
            slug: slug,
            label: label,
            notes: notes,
            isDefault: isFirst,
            createdAt: Date(),
            lastRotatedAt: nil
        )

        // Keychain write (with read-back verification) before persisting state.
        try ClaudeProfileKeychain.set(slug: slug, token: token)

        state.profiles.append(profile)
        save()
        return profile
    }

    func updateProfileLabel(id: UUID, label: String) {
        guard let idx = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[idx].label = label
        save()
    }

    func updateProfileNotes(id: UUID, notes: String?) {
        guard let idx = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[idx].notes = notes
        save()
    }

    /// Set the default profile. Clears isDefault on all others; exactly one default maintained.
    func setDefault(id: UUID) {
        for idx in state.profiles.indices {
            state.profiles[idx].isDefault = (state.profiles[idx].id == id)
        }
        save()
    }

    /// Delete a profile and handle dependent routes.
    /// - Returns folder paths of affected routes so the caller can regenerate `.envrc` files.
    @discardableResult
    func deleteProfile(
        id: UUID,
        keepKeychain: Bool,
        routeAction: RouteCascade
    ) -> [String] {
        // Capture slug BEFORE mutation — needed for Keychain cleanup after removal.
        let slug = state.profiles.first(where: { $0.id == id })?.slug

        // Collect affected paths BEFORE mutating routes.
        let affectedPaths = state.routes
            .filter { $0.profileId == id }
            .map(\.folderPath)

        switch routeAction {
        case .removeRoutes:
            state.routes.removeAll { $0.profileId == id }
        case .reassignTo(let targetId):
            for idx in state.routes.indices where state.routes[idx].profileId == id {
                state.routes[idx].profileId = targetId
            }
        }

        state.profiles.removeAll { $0.id == id }

        // Maintain "exactly one default" invariant.
        // If the deleted profile was default, promote the first remaining profile.
        let hasDefault = state.profiles.contains { $0.isDefault }
        if !hasDefault, let firstIdx = state.profiles.indices.first {
            state.profiles[firstIdx].isDefault = true
        }

        if !keepKeychain, let slug {
            do {
                try ClaudeProfileKeychain.delete(slug: slug)
            } catch {
                Self.logger.error("ClaudeRoutingStore: Keychain delete for '\(slug)' failed: \(error)")
            }
        }

        save()
        return affectedPaths
    }

    /// Overwrite the Keychain token and bump `lastRotatedAt`.
    func rotateToken(id: UUID, newToken: String) throws {
        guard let idx = state.profiles.firstIndex(where: { $0.id == id }) else {
            throw ValidationError.profileNotFound
        }
        let slug = state.profiles[idx].slug
        try ClaudeProfileKeychain.set(slug: slug, token: newToken)
        state.profiles[idx].lastRotatedAt = Date()
        save()
    }

    // MARK: - Route CRUD

    @discardableResult
    func addRoute(
        folderBookmark: Data,
        folderPath: String,
        profileId: UUID
    ) -> ClaudeFolderRoute {
        let route = ClaudeFolderRoute(
            id: UUID(),
            folderBookmark: folderBookmark,
            folderPath: folderPath,
            profileId: profileId
        )
        state.routes.append(route)
        save()
        return route
    }

    func updateRouteProfile(id: UUID, profileId: UUID) {
        guard let idx = state.routes.firstIndex(where: { $0.id == id }) else { return }
        state.routes[idx].profileId = profileId
        save()
    }

    /// Remove and return the deleted route so the caller can clean up `.envrc`.
    @discardableResult
    func deleteRoute(id: UUID) -> ClaudeFolderRoute? {
        guard let idx = state.routes.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = state.routes.remove(at: idx)
        save()
        return removed
    }

    // MARK: - Queries

    func profile(for routeId: UUID) -> ClaudeProfile? {
        guard let route = state.routes.first(where: { $0.id == routeId }) else { return nil }
        return state.profiles.first(where: { $0.id == route.profileId })
    }

    func routes(for profileId: UUID) -> [ClaudeFolderRoute] {
        state.routes.filter { $0.profileId == profileId }
    }

    /// Routes whose profileId no longer references a known profile.
    /// Should never happen in normal operation; present as a defensive check.
    func brokenRoutes() -> [ClaudeFolderRoute] {
        let profileIds = Set(state.profiles.map(\.id))
        return state.routes.filter { !profileIds.contains($0.profileId) }
    }

    /// Elapsed time since the token was last rotated (or created if never rotated).
    func tokenAge(profileId: UUID) -> TimeInterval? {
        guard let profile = state.profiles.first(where: { $0.id == profileId }) else { return nil }
        let anchor = profile.lastRotatedAt ?? profile.createdAt
        return Date().timeIntervalSince(anchor)
    }

    // MARK: - Persistence

    private static func load() -> ClaudeRoutingState {
        let url = storeURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ClaudeRoutingState.self, from: data)
        else {
            return ClaudeRoutingState(profiles: [], routes: [])
        }
        return decoded
    }

    private func save() {
        let url = Self.storeURL
        let dir = url.deletingLastPathComponent()
        do {
            // Create ~/Library/Application Support/AIMeter/ on first run if absent.
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            // Atomic write — crash before rename leaves old file intact.
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("ClaudeRoutingStore: persist failed: \(error)")
        }
    }

    // MARK: - Validation

    private func isValidSlug(_ slug: String) -> Bool {
        let range = NSRange(slug.startIndex..., in: slug)
        return Self.slugRegex.firstMatch(in: slug, range: range) != nil
    }
}
