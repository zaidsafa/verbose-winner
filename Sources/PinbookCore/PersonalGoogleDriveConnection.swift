import Foundation

enum PersonalGoogleDriveConnectionError: Error, Equatable, Sendable {
    case cleanupRequired
}

@MainActor protocol PersonalGoogleDriveAuthorizing: AnyObject, Sendable {
    func authorize(consent: Bool) async throws -> PersonalGoogleDriveGrant
    func cancel()
}

#if canImport(UIKit) && canImport(AppAuth)
extension PersonalGoogleDriveAuthorizer: PersonalGoogleDriveAuthorizing {}
#endif

/// Owns the authorization-to-Keychain transition. A newly issued refresh token
/// is first persisted as revocation-pending, then atomically activated. Any
/// cancellation or activation failure must revoke and remove that exact fenced
/// generation before the caller can safely retry.
@MainActor final class PersonalGoogleDriveConnectionOwner {
    private let configuration: PersonalGoogleDriveConfiguration
    private let authorizer: any PersonalGoogleDriveAuthorizing
    private let store: PersonalGoogleDriveCredentialStore
    private let revoker: any PersonalGoogleDriveRevoking
    private let now: @MainActor () -> Int64
    private var running = false

    init(configuration: PersonalGoogleDriveConfiguration,
         authorizer: any PersonalGoogleDriveAuthorizing,
         store: PersonalGoogleDriveCredentialStore = PersonalGoogleDriveCredentialStore(),
         revoker: any PersonalGoogleDriveRevoking = PersonalGoogleDriveRevocationClient(),
         now: @escaping @MainActor () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) {
        self.configuration = configuration
        self.authorizer = authorizer
        self.store = store
        self.revoker = revoker
        self.now = now
    }

    func connect(consent: Bool) async throws -> PersonalGoogleDriveCredentialSnapshot {
        try Task.checkCancellation()
        guard consent else { throw PersonalGoogleDriveCredentialError.consentRequired }
        guard !running else { throw PersonalGoogleDriveOAuthError.busy }
        running = true
        defer { running = false }

        if let existing = try store.load(configuration: configuration) {
            if existing.phase == .active {
                throw PersonalGoogleDriveCredentialError.alreadyConnected
            }
            throw PersonalGoogleDriveConnectionError.cleanupRequired
        }

        let grant = try await withTaskCancellationHandler {
            try await authorizer.authorize(consent: true)
        } onCancel: { [weak authorizer] in
            Task { @MainActor in authorizer?.cancel() }
        }

        let staged: PersonalGoogleDriveCredentialSnapshot
        do {
            staged = try store.stageInitialForActivation(
                grant, configuration: configuration, now: now(), consent: true
            )
        } catch let error as PersonalGoogleDriveCredentialError
            where error == .alreadyConnected {
            // Revoking a second token can also invalidate the valid connection
            // already stored for this dedicated Google project.
            throw error
        } catch {
            guard await revokeIgnoringCallerCancellation(grant.refresh) else {
                throw PersonalGoogleDriveConnectionError.cleanupRequired
            }
            throw error
        }

        if Task.isCancelled {
            guard await cleanup(staged) else {
                throw PersonalGoogleDriveConnectionError.cleanupRequired
            }
            throw CancellationError()
        }

        do {
            // No suspension after the cancellation decision: activation is the
            // operation's success linearization point.
            return try store.activate(staged, now: now())
        } catch {
            guard await cleanup(staged) else {
                throw PersonalGoogleDriveConnectionError.cleanupRequired
            }
            throw error
        }
    }

    func cancel() { authorizer.cancel() }

    private func cleanup(_ staged: PersonalGoogleDriveCredentialSnapshot) async -> Bool {
        guard await revokeIgnoringCallerCancellation(staged.tokenForRevocation()) else {
            return false
        }
        let store = store
        return await Task.detached {
            do {
                try store.remove(staged, consent: true)
                return true
            } catch { return false }
        }.value
    }

    private func revokeIgnoringCallerCancellation(
        _ token: PersonalGoogleDriveRefreshToken
    ) async -> Bool {
        let revoker = revoker
        return await Task.detached {
            do {
                try await revoker.revoke(token)
                return true
            } catch { return false }
        }.value
    }
}
