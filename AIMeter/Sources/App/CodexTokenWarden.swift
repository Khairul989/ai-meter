import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: AppConstants.bundleId, category: "CodexTokenWarden")

// MARK: - CodexTokenWarden

/// Proactively keeps OAuth-upgraded Codex account tokens fresh.
///
/// - Schedules a silent refresh for each OAuth-capable account at `expiresAt − refreshMarginSeconds`.
/// - On app foreground, refreshes any account that is within the margin window.
/// - Marks an account as `requiresManualSignIn` only on terminal failure (400 invalid_grant / 401).
/// - Transient failures (network, 5xx) back off exponentially and keep retrying silently.
/// - Legacy session-token accounts (no OAuth refresh token) are ignored — they expire as today.
@MainActor
final class CodexTokenWarden: ObservableObject {

    // MARK: Published state

    /// Account IDs for which silent refresh has terminally failed. UI shows the banner only for these.
    @Published private(set) var manualSignInRequired: Set<String> = []

    // MARK: Private state

    private let authManager: CodexAuthManager
    private let oauthService: CodexOAuthService

    /// Sleeping tasks that will fire the next refresh for each account.
    private var scheduledTasks: [String: Task<Void, Never>] = [:]

    /// Retained so the Combine subscription lives as long as the warden.
    private var accountsCancellable: AnyCancellable?

    /// Retained so the NSNotification observer is removed on deinit.
    private var foregroundObserver: NSObjectProtocol?

    /// Guards against registering duplicate observers/sinks if start() is called more than once.
    private var hasStarted = false

    // MARK: - Init

    init(authManager: CodexAuthManager, oauthService: CodexOAuthService) {
        self.authManager = authManager
        self.oauthService = oauthService
    }

    // MARK: - Public API

    /// Call once from app launch (e.g. inside `handlePopoverAppear`).
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Subscribe to account list changes. dropFirst prevents double-scheduling on
        // the initial publish that fires synchronously during start().
        accountsCancellable = authManager.$accounts
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] accounts in
                self?.syncAccounts(accounts)
            }

        // Schedule refreshes for all OAuth-capable accounts that already exist.
        syncAccounts(authManager.accounts)

        // Refresh near-expiry tokens whenever the app comes to the foreground.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleForeground()
            }
        }

        logger.info("warden.started accounts=\(self.managedAccounts.count, privacy: .public)")
    }

    /// Reschedule next refresh for one account (call after add or after a successful refresh).
    func reschedule(accountId: String) {
        guard let account = authManager.accounts.first(where: { $0.id == accountId }),
              account.hasOAuthUpgrade else { return }
        cancelTask(for: accountId)
        scheduleNextRefresh(for: accountId, backoffSeconds: nil)
    }

    /// Cancel the scheduled refresh for a removed account.
    func cancel(accountId: String) {
        cancelTask(for: accountId)
        manualSignInRequired.remove(accountId)
    }

    /// Refresh immediately if the token is within the margin window or already expired.
    func refreshNowIfDue(accountId: String) async {
        guard let account = authManager.accounts.first(where: { $0.id == accountId }),
              account.hasOAuthUpgrade else { return }

        let oauthExpiresAt = account.oauthAccessTokenExpiresAt ?? .distantPast
        let secondsRemaining = oauthExpiresAt.timeIntervalSinceNow
        guard secondsRemaining < codexOAuthRefreshMarginSeconds else { return }

        await performRefresh(accountId: accountId, backoffSeconds: nil)
    }

    /// Returns true when the warden has determined this account requires manual re-authentication.
    func requiresManualSignIn(_ account: CodexAccount) -> Bool {
        manualSignInRequired.contains(account.id)
    }

    // MARK: - Private: account sync

    private var managedAccounts: [CodexAccount] {
        authManager.accounts.filter(\.hasOAuthUpgrade)
    }

    private func syncAccounts(_ accounts: [CodexAccount]) {
        let oauthIds = Set(accounts.filter(\.hasOAuthUpgrade).map(\.id))
        let existingIds = Set(scheduledTasks.keys)

        for removed in existingIds.subtracting(oauthIds) {
            cancel(accountId: removed)
        }

        for id in oauthIds.subtracting(existingIds) {
            scheduleNextRefresh(for: id, backoffSeconds: nil)
        }
    }

    // MARK: - Private: scheduling

    private func scheduleNextRefresh(for accountId: String, backoffSeconds: TimeInterval?) {
        let delay: TimeInterval
        if let backoff = backoffSeconds {
            delay = backoff
        } else if let account = authManager.accounts.first(where: { $0.id == accountId }),
                  let expiresAt = account.oauthAccessTokenExpiresAt {
            // Sleep until `expiresAt − margin`, at least 1 s from now
            delay = max(expiresAt.timeIntervalSinceNow - codexOAuthRefreshMarginSeconds, 1)
        } else {
            // No cached token yet — try soon
            delay = 5
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(max(delay, 0)))
            guard !Task.isCancelled else { return }
            await self.performRefresh(accountId: accountId, backoffSeconds: nil)
        }

        scheduledTasks[accountId] = task
    }

    private func cancelTask(for accountId: String) {
        scheduledTasks[accountId]?.cancel()
        scheduledTasks[accountId] = nil
    }

    // MARK: - Private: foreground hook

    private func handleForeground() async {
        await withTaskGroup(of: Void.self) { group in
            for account in managedAccounts {
                group.addTask { [weak self] in
                    await self?.refreshNowIfDue(accountId: account.id)
                }
            }
        }
    }

    // MARK: - Private: refresh + error classification

    private func performRefresh(accountId: String, backoffSeconds: TimeInterval?) async {
        logger.info("warden.refresh.attempt account=\(accountId, privacy: .public)")

        do {
            _ = try await oauthService.refreshAccessToken(for: accountId)
            // Success: clear terminal flag, reload account so SwiftUI sees new expiresAt
            manualSignInRequired.remove(accountId)
            authManager.reloadAccount(id: accountId)
            // Reschedule from the freshly updated expiresAt
            cancelTask(for: accountId)
            scheduleNextRefresh(for: accountId, backoffSeconds: nil)
            logger.info("warden.refresh.success account=\(accountId, privacy: .public)")
        } catch {
            switch classify(error) {
            case .terminal:
                logger.warning("warden.refresh.terminal account=\(accountId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                manualSignInRequired.insert(accountId)
                cancelTask(for: accountId)
                // Do not reschedule — banner is now the user's only path forward.

            case .transient:
                let next = nextBackoff(current: backoffSeconds)
                logger.info("warden.refresh.transient account=\(accountId, privacy: .public) retryIn=\(next, privacy: .public)s")
                cancelTask(for: accountId)
                scheduleNextRefresh(for: accountId, backoffSeconds: next)
            }
        }
    }

    // MARK: - Private: error classification

    private enum RefreshFailureKind { case terminal, transient }

    /// Classify a refresh error as terminal (manual re-auth required) or transient (retry).
    ///
    /// Terminal: HTTP 400 with `invalid_grant` in the body, or HTTP 401.
    /// Transient: network errors (URLError), HTTP 5xx, or any other unexpected error.
    private func classify(_ error: Error) -> RefreshFailureKind {
        if let oauthError = error as? CodexOAuthError {
            switch oauthError {
            case .tokenExchangeFailed(let status, let message):
                if status == 401 { return .terminal }
                if status == 400 && message.lowercased().contains("invalid_grant") { return .terminal }
                if status >= 500 { return .transient }
                // Other 4xx (e.g. 400 without invalid_grant): treat as terminal to avoid hammering
                return .terminal
            case .invalidTokenResponse:
                // Corrupt or missing refresh token in keychain — treat as terminal
                return .terminal
            default:
                return .transient
            }
        }

        // URLError or other system errors are transient (network blip, timeout, etc.)
        if error is URLError { return .transient }
        return .transient
    }

    // MARK: - Private: backoff

    /// Exponential backoff sequence: 30 s → 60 s → 300 s → 900 s (capped).
    private func nextBackoff(current: TimeInterval?) -> TimeInterval {
        guard let c = current else { return 30 }
        if c < 60 { return 60 }
        if c < 300 { return 300 }
        return 900
    }
}
