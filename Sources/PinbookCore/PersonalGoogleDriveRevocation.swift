import Foundation

protocol PersonalGoogleDriveRevoking: Sendable {
    func revoke(_ token: PersonalGoogleDriveRefreshToken) async throws
}

protocol PersonalGoogleDriveRevocationHTTPExecuting: Sendable {
    func execute(_ request: URLRequest) async throws -> TeamAuthResponse
}

private struct PersonalGoogleDriveRevocationHTTPExecutor:
    PersonalGoogleDriveRevocationHTTPExecuting {
    func execute(_ request: URLRequest) async throws -> TeamAuthResponse {
        try await TeamAuthURLExchange(
            request: request,
            configuration: TeamAuthHTTPClient.configuration(),
            localTestAnchor: nil,
            responseProfile: .googleRevoke,
            maximumResponseBytes: 4 * 1_024
        ).run()
    }
}

private final class PersonalGoogleDriveRevocationSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    func acquire() throws {
        try lock.withLock {
            guard !active else { throw PersonalGoogleDriveOAuthError.busy }
            active = true
        }
    }

    func release() { lock.withLock { active = false } }
}

/// One-shot remote OAuth revocation. A successful empty 200, or Google's exact
/// already-invalid token response, establishes the desired remote state. Local
/// credential deletion remains a separate generation-bound operation.
final class PersonalGoogleDriveRevocationClient: PersonalGoogleDriveRevoking, Sendable {
    static let endpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    private let executor: any PersonalGoogleDriveRevocationHTTPExecuting
    private let slot = PersonalGoogleDriveRevocationSlot()

    init(executor: any PersonalGoogleDriveRevocationHTTPExecuting =
        PersonalGoogleDriveRevocationHTTPExecutor()) {
        self.executor = executor
    }

    func revoke(_ token: PersonalGoogleDriveRefreshToken) async throws {
        try slot.acquire()
        defer { slot.release() }
        try Task.checkCancellation()
        let body = Data(("token=" + Self.form(token.value)).utf8)
        guard body.count <= 24_000 else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBodyStream = InputStream(data: body)
        let response: TeamAuthResponse
        do {
            response = try await executor.execute(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalGoogleDriveOAuthError.unavailable
        }
        if response.status == 200 {
            guard response.body.isEmpty else {
                throw PersonalGoogleDriveOAuthError.invalidResponse
            }
            return
        }
        if response.status == 400, Self.isAlreadyInvalid(response.body) { return }
        throw PersonalGoogleDriveOAuthError.unavailable
    }

    private static func isAlreadyInvalid(_ data: Data) -> Bool {
        do {
            let object = try TeamStrictJSON.object(data, maximumBytes: 4 * 1_024)
            let keys = Set(object.keys)
            guard keys.contains("error"),
                  keys.isSubset(of: ["error", "error_description"]),
                  object["error"] as? String == "invalid_token" else { return false }
            if let description = object["error_description"] {
                guard let value = description as? String,
                      value.utf8.count <= 1_024 else { return false }
            }
            return true
        } catch { return false }
    }

    private static func form(_ value: String) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte)
                || (48...57).contains(byte) || byte == 45 || byte == 46
                || byte == 95 || byte == 126 {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }
}

/// Explicit disconnect coordinator. Remote revocation must reach an authoritative
/// outcome before the exact local Keychain generation is removed. A failure or
/// cancellation retains a fenced local token so the user can retry honestly.
final class PersonalGoogleDriveDisconnectOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var active: UUID?
    private let store: PersonalGoogleDriveCredentialStore
    private let revoker: any PersonalGoogleDriveRevoking

    init(store: PersonalGoogleDriveCredentialStore = PersonalGoogleDriveCredentialStore(),
         revoker: any PersonalGoogleDriveRevoking = PersonalGoogleDriveRevocationClient()) {
        self.store = store
        self.revoker = revoker
    }

    /// Returns false when no credential exists. Consent is still mandatory so a
    /// stale screen cannot silently turn a later connection into a disconnect.
    func disconnect(configuration: PersonalGoogleDriveConfiguration,
                    consent: Bool) async throws -> Bool {
        try Task.checkCancellation()
        guard consent else { throw PersonalGoogleDriveCredentialError.consentRequired }
        guard let loaded = try store.load(configuration: configuration) else { return false }
        let operation = try begin()
        defer { finish(operation) }
        let current = loaded.phase == .revocationPending
            ? loaded : try store.beginRevocation(loaded)
        try await revoker.revoke(current.tokenForRevocation())
        try Task.checkCancellation()
        try store.remove(current, consent: true)
        return true
    }

    private func begin() throws -> UUID {
        try lock.withLock {
            guard active == nil else { throw PersonalGoogleDriveOAuthError.busy }
            let operation = UUID()
            active = operation
            return operation
        }
    }

    private func finish(_ operation: UUID) {
        lock.withLock {
            if active == operation { active = nil }
        }
    }
}
