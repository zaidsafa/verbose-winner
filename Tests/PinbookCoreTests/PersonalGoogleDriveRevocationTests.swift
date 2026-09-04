import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor PersonalDriveRevocationHTTPStub: PersonalGoogleDriveRevocationHTTPExecuting {
    private var results: [Result<TeamAuthResponse, Error>]
    private(set) var requests: [URLRequest] = []

    init(_ results: [Result<TeamAuthResponse, Error>]) { self.results = results }

    func execute(_ request: URLRequest) throws -> TeamAuthResponse {
        requests.append(request)
        guard !results.isEmpty else { throw PersonalGoogleDriveOAuthError.unavailable }
        return try results.removeFirst().get()
    }
}

private actor BlockingPersonalDriveRevocationHTTPStub:
    PersonalGoogleDriveRevocationHTTPExecuting {
    private var continuation: CheckedContinuation<TeamAuthResponse, any Error>?
    private(set) var requestCount = 0

    func execute(_ request: URLRequest) async throws -> TeamAuthResponse {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: .init(status: 200, body: Data()))
        continuation = nil
    }
}

private actor PersonalDriveDisconnectRevokerStub: PersonalGoogleDriveRevoking {
    enum Mode { case success, failure, blocked }
    let mode: Mode
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ mode: Mode) { self.mode = mode }

    func revoke(_ token: PersonalGoogleDriveRefreshToken) async throws {
        calls += 1
        if mode == .failure { throw PersonalGoogleDriveOAuthError.unavailable }
        if mode == .blocked {
            await withCheckedContinuation { continuation = $0 }
        }
    }

    func isBlocked() -> Bool { calls == 1 && continuation != nil }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private func revocationToken() throws -> PersonalGoogleDriveRefreshToken {
    try PersonalGoogleDriveRefreshToken("refresh+/=&" + String(repeating: "r", count: 24))
}

private func revocationBody(_ request: URLRequest) throws -> Data {
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 512)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { throw PersonalGoogleDriveOAuthError.unavailable }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

@Suite(.serialized)
struct PersonalGoogleDriveRevocationTests {
    @Test func sendsOneUseEncodedRefreshTokenAndAcceptsOnlyEmptySuccess() async throws {
        let stub = PersonalDriveRevocationHTTPStub([
            .success(.init(status: 200, body: Data())),
        ])
        try await PersonalGoogleDriveRevocationClient(executor: stub)
            .revoke(revocationToken())
        let request = try #require(await stub.requests.first)
        #expect(request.url == PersonalGoogleDriveRevocationClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        let body = try revocationBody(request)
        #expect(String(decoding: body, as: UTF8.self) ==
                "token=refresh%2B%2F%3D%26" + String(repeating: "r", count: 24))
        #expect(request.value(forHTTPHeaderField: "Content-Length") == String(body.count))

        let nonempty = PersonalDriveRevocationHTTPStub([
            .success(.init(status: 200, body: Data("{}".utf8))),
        ])
        await #expect(throws: PersonalGoogleDriveOAuthError.invalidResponse) {
            try await PersonalGoogleDriveRevocationClient(executor: nonempty)
                .revoke(revocationToken())
        }
    }

    @Test func exactAlreadyInvalidIsIdempotentAndOtherFailuresStayRetryable() async throws {
        let already = PersonalDriveRevocationHTTPStub([
            .success(.init(status: 400, body: Data("{\"error\":\"invalid_token\"}".utf8))),
        ])
        try await PersonalGoogleDriveRevocationClient(executor: already)
            .revoke(revocationToken())

        let failures: [TeamAuthResponse] = [
            .init(status: 400, body: Data("{\"error\":\"invalid_request\"}".utf8)),
            .init(status: 400,
                  body: Data("{\"error\":\"invalid_token\",\"extra\":true}".utf8)),
            .init(status: 500, body: Data()),
        ]
        for response in failures {
            let stub = PersonalDriveRevocationHTTPStub([.success(response)])
            await #expect(throws: PersonalGoogleDriveOAuthError.unavailable) {
                try await PersonalGoogleDriveRevocationClient(executor: stub)
                    .revoke(revocationToken())
            }
            #expect(await stub.requests.count == 1)
        }
    }

    @Test func concurrentRevocationFailsBusyWithoutSecondDispatch() async throws {
        let stub = BlockingPersonalDriveRevocationHTTPStub()
        let client = PersonalGoogleDriveRevocationClient(executor: stub)
        let token = try revocationToken()
        let first = Task { try await client.revoke(token) }
        while await stub.requestCount == 0 { await Task.yield() }
        await #expect(throws: PersonalGoogleDriveOAuthError.busy) {
            try await client.revoke(token)
        }
        #expect(await stub.requestCount == 1)
        await stub.finish()
        try await first.value
    }

    @Test func disconnectRevokesBeforeExactLocalDeletion() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.disconnect", keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        _ = try store.saveInitial(
            personalDriveCredentialGrant(), configuration: configuration,
            now: 1_000_000, consent: true
        )
        let revoker = PersonalDriveDisconnectRevokerStub(.success)
        let owner = PersonalGoogleDriveDisconnectOwner(store: store, revoker: revoker)
        #expect(try await owner.disconnect(configuration: configuration, consent: true))
        #expect(try store.load(configuration: configuration) == nil)
        #expect(await revoker.calls == 1)
        #expect(try await !owner.disconnect(configuration: configuration, consent: true))
        #expect(await revoker.calls == 1)
    }

    @Test func failedOrUnconsentedDisconnectKeepsCredentialForRetry() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.disconnect-fail",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        let saved = try store.saveInitial(
            personalDriveCredentialGrant(), configuration: configuration,
            now: 1_000_000, consent: true
        )
        let revoker = PersonalDriveDisconnectRevokerStub(.failure)
        let owner = PersonalGoogleDriveDisconnectOwner(store: store, revoker: revoker)
        await #expect(throws: PersonalGoogleDriveCredentialError.consentRequired) {
            try await owner.disconnect(configuration: configuration, consent: false)
        }
        #expect(await revoker.calls == 0)
        await #expect(throws: PersonalGoogleDriveOAuthError.unavailable) {
            try await owner.disconnect(configuration: configuration, consent: true)
        }
        let persisted = try store.load(configuration: configuration)
        let pending = try #require(persisted)
        #expect(pending.generation != saved.generation)
        #expect(pending.phase == .revocationPending)
    }

    @Test func durableRevocationMarkerFencesLateRefreshAndThenDeletes() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.disconnect-stale",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        let initial = try store.saveInitial(
            personalDriveCredentialGrant(), configuration: configuration,
            now: 1_000_000, consent: true
        )
        let revoker = PersonalDriveDisconnectRevokerStub(.blocked)
        let owner = PersonalGoogleDriveDisconnectOwner(store: store, revoker: revoker)
        let disconnect = Task {
            try await owner.disconnect(configuration: configuration, consent: true)
        }
        while await !revoker.isBlocked() { await Task.yield() }
        #expect(throws: PersonalGoogleDriveCredentialError.staleOperation) {
            try store.replace(
                initial,
                with: personalDriveCredentialGrant(refresh: "n", now: 2_000_000),
                now: 2_000_000
            )
        }
        let persisted = try store.load(configuration: configuration)
        let marker = try #require(persisted)
        #expect(marker.phase == .revocationPending)
        await revoker.finish()
        #expect(try await disconnect.value)
        #expect(try store.load(configuration: configuration) == nil)
    }
}
