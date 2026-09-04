import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

@MainActor private final class PersonalDriveConnectionAuthorizerStub:
    PersonalGoogleDriveAuthorizing {
    private let immediate: PersonalGoogleDriveGrant?
    private var continuation: CheckedContinuation<PersonalGoogleDriveGrant, Error>?
    private(set) var calls = 0
    private(set) var cancels = 0

    init(immediate: PersonalGoogleDriveGrant? = nil) { self.immediate = immediate }

    func authorize(consent: Bool) async throws -> PersonalGoogleDriveGrant {
        calls += 1
        guard consent else { throw PersonalGoogleDriveOAuthError.invalidRequest }
        if let immediate { return immediate }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func cancel() { cancels += 1 }

    func succeed(_ grant: PersonalGoogleDriveGrant) {
        continuation?.resume(returning: grant)
        continuation = nil
    }

    var isWaiting: Bool { continuation != nil }
}

private actor PersonalDriveConnectionRevokerStub: PersonalGoogleDriveRevoking {
    let succeeds: Bool
    private(set) var calls = 0

    init(succeeds: Bool = true) { self.succeeds = succeeds }

    func revoke(_ token: PersonalGoogleDriveRefreshToken) async throws {
        calls += 1
        if !succeeds { throw PersonalGoogleDriveOAuthError.unavailable }
    }
}

@MainActor @Suite(.serialized)
struct PersonalGoogleDriveConnectionTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic personal Drive connection did not settle")
    }

    @Test func successFencesThenActivatesExactProtectedGeneration() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.connection-success",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration("123-connection")
        let authorizer = PersonalDriveConnectionAuthorizerStub(
            immediate: try personalDriveCredentialGrant(now: 1_000_000)
        )
        let revoker = PersonalDriveConnectionRevokerStub()
        let owner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: authorizer,
            store: store, revoker: revoker, now: { 1_000_000 }
        )

        let connected = try await owner.connect(consent: true)
        #expect(connected.phase == .active)
        #expect(try store.load(configuration: configuration)?.generation
                == connected.generation)
        let revokeCalls = await revoker.calls
        #expect(authorizer.calls == 1)
        #expect(revokeCalls == 0)
    }

    @Test func existingActiveOrFencedCredentialNeverContactsProvider() async throws {
        let configuration = try personalDriveCredentialConfiguration("124-connection")
        let activeStore = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.connection-existing",
            keychain: PersonalDriveCredentialKeychainStub()
        )
        let active = try activeStore.saveInitial(
            personalDriveCredentialGrant(now: 1_000_000),
            configuration: configuration, now: 1_000_000, consent: true
        )
        let activeAuthorizer = PersonalDriveConnectionAuthorizerStub()
        let activeOwner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: activeAuthorizer,
            store: activeStore, revoker: PersonalDriveConnectionRevokerStub(),
            now: { 1_000_000 }
        )
        await #expect(throws: PersonalGoogleDriveCredentialError.alreadyConnected) {
            try await activeOwner.connect(consent: true)
        }
        #expect(activeAuthorizer.calls == 0)

        let fenced = try activeStore.beginRevocation(active)
        let fencedAuthorizer = PersonalDriveConnectionAuthorizerStub()
        let fencedOwner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: fencedAuthorizer,
            store: activeStore, revoker: PersonalDriveConnectionRevokerStub(),
            now: { 1_000_000 }
        )
        await #expect(throws: PersonalGoogleDriveConnectionError.cleanupRequired) {
            try await fencedOwner.connect(consent: true)
        }
        #expect(fencedAuthorizer.calls == 0)
        try activeStore.remove(fenced, consent: true)
    }

    @Test func cancellationAfterIssuanceRevokesAndRemovesFence() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.connection-cancel",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration("125-connection")
        let authorizer = PersonalDriveConnectionAuthorizerStub()
        let revoker = PersonalDriveConnectionRevokerStub()
        let owner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: authorizer,
            store: store, revoker: revoker, now: { 1_000_000 }
        )
        let task = Task { try await owner.connect(consent: true) }
        try await waitUntil { authorizer.isWaiting }
        await #expect(throws: PersonalGoogleDriveOAuthError.busy) {
            try await owner.connect(consent: true)
        }
        #expect(authorizer.calls == 1)
        task.cancel()
        try await waitUntil { authorizer.cancels == 1 }
        authorizer.succeed(try personalDriveCredentialGrant(now: 1_000_000))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try store.load(configuration: configuration) == nil)
        let revokeCalls = await revoker.calls
        #expect(revokeCalls == 1)
    }

    @Test func failedCancellationCleanupStaysDurablyFenced() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.connection-cleanup",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration("126-connection")
        let authorizer = PersonalDriveConnectionAuthorizerStub()
        let revoker = PersonalDriveConnectionRevokerStub(succeeds: false)
        let owner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: authorizer,
            store: store, revoker: revoker, now: { 1_000_000 }
        )
        let task = Task { try await owner.connect(consent: true) }
        try await waitUntil { authorizer.isWaiting }
        task.cancel()
        authorizer.succeed(try personalDriveCredentialGrant(now: 1_000_000))
        await #expect(throws: PersonalGoogleDriveConnectionError.cleanupRequired) {
            try await task.value
        }
        let loaded = try store.load(configuration: configuration)
        let retained = try #require(loaded)
        #expect(retained.phase == .revocationPending)
        let revokeCalls = await revoker.calls
        #expect(revokeCalls == 1)
        try store.remove(retained, consent: true)
    }

    #if !SWIFT_PACKAGE
    @Test func realKeychainConnectionActivatesAndReopensExactGeneration() async throws {
        let service = "pinbook.personal-drive-credential-device-test."
            + UUID().uuidString.lowercased()
        let store = try PersonalGoogleDriveCredentialStore(deviceTestService: service)
        let configuration = try personalDriveCredentialConfiguration("127-connection")
        let authorizer = PersonalDriveConnectionAuthorizerStub(
            immediate: try personalDriveCredentialGrant(now: 1_000_000)
        )
        let owner = PersonalGoogleDriveConnectionOwner(
            configuration: configuration, authorizer: authorizer,
            store: store, revoker: PersonalDriveConnectionRevokerStub(),
            now: { 1_000_000 }
        )
        let active = try await owner.connect(consent: true)
        let reopened = try PersonalGoogleDriveCredentialStore(deviceTestService: service)
        let persisted = try reopened.load(configuration: configuration)
        let loaded = try #require(persisted)
        #expect(loaded.phase == .active && loaded.generation == active.generation)
        try reopened.remove(loaded, consent: true)
        #expect(try store.load(configuration: configuration) == nil)
    }
    #endif
}
