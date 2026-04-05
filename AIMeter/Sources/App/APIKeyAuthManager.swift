import Foundation
import SwiftUI
import Combine

// MARK: - APIKeyAccount

struct APIKeyAccount: Identifiable, Equatable {
    let id: String
    let apiKey: String
    let label: String
}

// MARK: - APIKeyAuthManagers

@MainActor
final class APIKeyAuthManagers: ObservableObject {
    let glm: APIKeyAuthManager
    let kimi: APIKeyAuthManager
    let minimax: APIKeyAuthManager
    private var cancellables = Set<AnyCancellable>()

    init(glm: APIKeyAuthManager, kimi: APIKeyAuthManager, minimax: APIKeyAuthManager) {
        self.glm = glm
        self.kimi = kimi
        self.minimax = minimax

        glm.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        kimi.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        minimax.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

// MARK: - APIKeyAuthManager

@MainActor
final class APIKeyAuthManager: ObservableObject {
    @Published var accounts: [APIKeyAccount] = []
    @Published var activeAccountId: String?

    let keychain: APIKeyKeychainHelper
    private let activeAccountKey: String

    var activeAccount: APIKeyAccount? {
        accounts.first { $0.id == activeAccountId }
    }
    var activeAPIKey: String? { activeAccount?.apiKey }
    var isAuthenticated: Bool { activeAccount != nil }

    init(keychain: APIKeyKeychainHelper) {
        self.keychain = keychain
        self.activeAccountKey = "\(keychain.serviceName)ActiveAccountId"
        loadCredentials()
    }

    // MARK: - Load

    private func loadCredentials() {
        // Migration: check for legacy un-namespaced key
        if let legacyKey = keychain.readAPIKey() {
            let defaultId = "Default"
            keychain.saveAPIKey(legacyKey, accountId: defaultId)
            keychain.addAccountId(defaultId)
            keychain.deleteAPIKey()
        }

        let accountIds = keychain.savedAccountIds()
        accounts = accountIds.compactMap { id in
            guard let apiKey = keychain.readAPIKey(accountId: id) else { return nil }
            return APIKeyAccount(id: id, apiKey: apiKey, label: id)
        }

        let savedActive = UserDefaults.standard.string(forKey: activeAccountKey)
        if let savedActive, accounts.contains(where: { $0.id == savedActive }) {
            activeAccountId = savedActive
        } else {
            activeAccountId = accounts.first?.id
        }
    }

    // MARK: - Account Management

    func addAccount(label: String, apiKey: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedLabel.isEmpty, !trimmedKey.isEmpty else { return }

        keychain.saveAPIKey(trimmedKey, accountId: trimmedLabel)
        keychain.addAccountId(trimmedLabel)

        let accountIds = keychain.savedAccountIds()
        accounts = accountIds.compactMap { id in
            guard let key = keychain.readAPIKey(accountId: id) else { return nil }
            return APIKeyAccount(id: id, apiKey: key, label: id)
        }
        activeAccountId = trimmedLabel
        UserDefaults.standard.set(trimmedLabel, forKey: activeAccountKey)
    }

    func removeAccount(id: String) {
        keychain.deleteAPIKey(accountId: id)
        keychain.removeAccountId(id)

        accounts.removeAll { $0.id == id }

        if activeAccountId == id {
            activeAccountId = accounts.first?.id
            if let newActive = activeAccountId {
                UserDefaults.standard.set(newActive, forKey: activeAccountKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeAccountKey)
            }
        }
    }

    func setActiveAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        UserDefaults.standard.set(id, forKey: activeAccountKey)
    }
}
