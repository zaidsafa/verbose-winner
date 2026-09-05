import Foundation

enum PersonalGoogleDriveAccessError: Error, Equatable, Sendable {
    case notConnected
    case cleanupRequired
}

protocol PersonalGoogleDriveTokenRefreshing: Sendable {
    func refresh(_ token: PersonalGoogleDriveRefreshToken) async throws
        -> PersonalGoogleDriveGrant
}

extension PersonalGoogleDriveTokenClient: PersonalGoogleDriveTokenRefreshing {}

/// Sole in-process owner of access-token refresh for one personal Drive
/// connection. Concurrent consumers share one provider exchange; rotated refresh
/// material is generation-bound in Keychain before an access token is returned.
actor PersonalGoogleDriveAccessOwner {
    private struct RefreshOutcome: Sendable {
        let grant: PersonalGoogleDriveGrant
        let snapshot: PersonalGoogleDriveCredentialSnapshot
    }

    private struct Flight: Sendable {
        let id: UUID
        let task: Task<RefreshOutcome, Error>
    }

    private let configuration: PersonalGoogleDriveConfiguration
    private let store: PersonalGoogleDriveCredentialStore
    private let refresher: any PersonalGoogleDriveTokenRefreshing
    private let now: @Sendable () -> Int64
    private var cached: PersonalGoogleDriveGrant?
    private var flight: Flight?

    init(configuration: PersonalGoogleDriveConfiguration,
         store: PersonalGoogleDriveCredentialStore = PersonalGoogleDriveCredentialStore(),
         refresher: (any PersonalGoogleDriveTokenRefreshing)? = nil,
         now: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) {
        self.configuration = configuration
        self.store = store
        self.refresher = refresher
            ?? PersonalGoogleDriveTokenClient(configuration: configuration, now: now)
        self.now = now
    }

    func accessToken() async throws -> GoogleDriveAccessToken {
        try Task.checkCancellation()
        let observedAt = try validNow()
        if let cached,
           cached.accessExpiresAt > observedAt + 30_000,
           let token = try? cached.accessToken(now: observedAt) {
            return token
        }

        if let flight { return try await settle(flight) }

        guard let current = try store.load(configuration: configuration) else {
            throw PersonalGoogleDriveAccessError.notConnected
        }
        guard current.phase == .active else {
            throw PersonalGoogleDriveAccessError.cleanupRequired
        }
        let refresh = try current.usableRefreshToken(now: observedAt)
        let refresher = refresher
        let store = store
        let now = now
        let id = UUID()
        let task = Task<RefreshOutcome, Error> {
            // This unstructured task intentionally settles independently of any
            // one caller so a provider-side rotation cannot be abandoned midway.
            let grant = try await refresher.refresh(refresh)
            let completedAt = now()
            guard completedAt >= observedAt,
                  completedAt <= TeamAuthWire.maximumSafeTime else {
                throw PersonalGoogleDriveOAuthError.invalidResponse
            }
            let next = try store.replace(current, with: grant, now: completedAt)
            return RefreshOutcome(grant: grant, snapshot: next)
        }
        let created = Flight(id: id, task: task)
        flight = created
        return try await settle(created)
    }

    func clearMemory() { cached = nil }

    func isConnected() throws -> Bool {
        guard let value = try store.load(configuration: configuration) else { return false }
        guard value.phase == .active else {
            throw PersonalGoogleDriveAccessError.cleanupRequired
        }
        _ = try value.usableRefreshToken(now: validNow())
        return true
    }

    private func settle(_ current: Flight) async throws -> GoogleDriveAccessToken {
        do {
            let outcome = try await current.task.value
            if flight?.id == current.id {
                flight = nil
                cached = outcome.grant
            }
            try Task.checkCancellation()
            return try outcome.grant.accessToken(now: validNow())
        } catch {
            if flight?.id == current.id { flight = nil }
            throw error
        }
    }

    private func validNow() throws -> Int64 {
        let value = now()
        guard value >= 0, value <= TeamAuthWire.maximumSafeTime - 30_000 else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        return value
    }
}
