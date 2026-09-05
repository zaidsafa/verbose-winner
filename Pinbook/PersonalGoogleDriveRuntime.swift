import Observation
import UIKit

enum PersonalGoogleDriveRuntimeState: Equatable {
    case unavailable
    case disconnected
    case connecting
    case connected
    case syncing
    case disconnecting
    case cleanupRequired
}

struct PersonalGoogleDriveSyncResult: Equatable {
    let remoteSnapshots: Int
    let downloadedSnapshots: Int
    let appliedChanges: Int
    let conflicts: Int
    let uploaded: Bool
}

/// Production owner for the personal Drive callback and connection lifecycle.
/// External requests require a previously consented connection and either a
/// manual sync or the user's persisted automatic-sync choice. Ephemeral fixtures
/// disable the complete external boundary even if a QA credential exists.
@MainActor @Observable
final class PersonalGoogleDriveRuntime {
    private(set) var state: PersonalGoogleDriveRuntimeState = .unavailable
    private(set) var lastError: Error?

    private let configuration: PersonalGoogleDriveConfiguration?
    private let authorizer: PersonalGoogleDriveAuthorizer?
    private let connection: PersonalGoogleDriveConnectionOwner?
    private let disconnectOwner: PersonalGoogleDriveDisconnectOwner?
    private let accessOwner: PersonalGoogleDriveAccessOwner?
    private let store = PersonalGoogleDriveCredentialStore()
    private let uploadOwner = PersonalCloudUploadOwner()
    private let allowsExternalRequests: Bool

    init(allowsExternalRequests: Bool = true) {
        self.allowsExternalRequests = allowsExternalRequests
        guard allowsExternalRequests else {
            configuration = nil
            authorizer = nil
            connection = nil
            disconnectOwner = nil
            accessOwner = nil
            state = .disconnected
            return
        }
        do {
            let configuration = try PersonalGoogleDriveConfiguration.installed()
            let authorizer = PersonalGoogleDriveAuthorizer(
                configuration: configuration,
                presenting: { Self.foregroundPresenter() }
            )
            self.configuration = configuration
            self.authorizer = authorizer
            connection = PersonalGoogleDriveConnectionOwner(
                configuration: configuration, authorizer: authorizer, store: store
            )
            disconnectOwner = PersonalGoogleDriveDisconnectOwner(store: store)
            accessOwner = PersonalGoogleDriveAccessOwner(
                configuration: configuration, store: store
            )
            refreshState()
        } catch {
            configuration = nil
            authorizer = nil
            connection = nil
            disconnectOwner = nil
            accessOwner = nil
            state = .unavailable
            lastError = error
        }
    }

    /// True only when the exact pending personal-Drive AppAuth flow consumed the
    /// callback. Pinbook deep links remain owned by AppShellView.
    func handleRedirect(_ url: URL) -> Bool {
        authorizer?.handleRedirect(url) ?? false
    }

    func connect() async throws {
        guard state == .disconnected,
              let connection else { throw PersonalGoogleDriveOAuthError.busy }
        state = .connecting
        lastError = nil
        do {
            _ = try await connection.connect(consent: true)
            state = .connected
        } catch {
            lastError = error
            refreshState()
            throw error
        }
    }

    func disconnect() async throws {
        guard state == .connected || state == .cleanupRequired,
              let configuration, let disconnectOwner else {
            throw PersonalGoogleDriveOAuthError.busy
        }
        state = .disconnecting
        lastError = nil
        do {
            _ = try await disconnectOwner.disconnect(
                configuration: configuration, consent: true
            )
            await accessOwner?.clearMemory()
            state = .disconnected
        } catch {
            lastError = error
            refreshState()
            throw error
        }
    }

    func accessToken() async throws -> GoogleDriveAccessToken {
        guard state == .connected, let accessOwner else {
            throw PersonalGoogleDriveAccessError.notConnected
        }
        return try await accessOwner.accessToken()
    }

    func sync(using service: BackupRecoveryService) async throws
        -> PersonalGoogleDriveSyncResult {
        guard state == .connected, let accessOwner else {
            throw PersonalGoogleDriveAccessError.notConnected
        }
        state = .syncing
        lastError = nil
        do {
            let transport = GoogleDriveBackupTransport {
                try await accessOwner.accessToken()
            }
            let result: PersonalGoogleDriveSyncResult
            do {
                result = try await performSync(using: service, transport: transport)
            } catch GoogleDriveBackupError.unauthorized {
                await accessOwner.clearMemory()
                result = try await performSync(using: service, transport: transport)
            }
            state = .connected
            return result
        } catch {
            lastError = error
            refreshState()
            throw error
        }
    }

    func refreshState() {
        guard allowsExternalRequests else {
            state = .disconnected
            return
        }
        guard let configuration else {
            state = .unavailable
            return
        }
        do {
            guard let credential = try store.load(configuration: configuration) else {
                state = .disconnected
                return
            }
            state = credential.phase == .active ? .connected : .cleanupRequired
        } catch {
            state = .cleanupRequired
            lastError = error
        }
    }

    private static func foregroundPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: { !$0.isHidden && $0.alpha > 0 })
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController,
              !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    private func performSync(using service: BackupRecoveryService,
                             transport: GoogleDriveBackupTransport) async throws
        -> PersonalGoogleDriveSyncResult {
        try Task.checkCancellation()
        let original = try await service.captureBackup(exportedAt: nil)
        let reconciliation = try await PersonalCloudSyncEngine.reconcile(
            local: original, using: transport
        )
        if reconciliation.merged != original {
            let prepared = try await service.prepareRestore(
                data: try PersonalCloudSyncEngine.encode(reconciliation.merged)
            )
            _ = try await service.applyRestore(prepared)
        }

        let final = try await service.captureBackup(exportedAt: nil)
        let bytes = try PersonalCloudSyncEngine.encode(final)
        var uploaded = false
        if !reconciliation.alreadyContains(bytes) {
            let createdAt = Int64(Date().timeIntervalSince1970 * 1_000)
            let ticket = try await uploadOwner.reserve(
                bytes, createdAt: createdAt, using: transport
            )
            _ = try await uploadOwner.append(bytes, ticket: ticket, using: transport)
            uploaded = true
        }
        return PersonalGoogleDriveSyncResult(
            remoteSnapshots: reconciliation.remoteSnapshotCount,
            downloadedSnapshots: reconciliation.downloadedSnapshotCount,
            appliedChanges: reconciliation.appliedChanges,
            conflicts: reconciliation.conflicts,
            uploaded: uploaded
        )
    }
}
