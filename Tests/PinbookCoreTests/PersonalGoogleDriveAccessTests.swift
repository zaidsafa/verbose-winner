import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor PersonalDriveTokenRefresherStub: PersonalGoogleDriveTokenRefreshing {
    private let grant: PersonalGoogleDriveGrant
    private let suspended: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    init(grant: PersonalGoogleDriveGrant, suspended: Bool = false) {
        self.grant = grant
        self.suspended = suspended
    }

    func refresh(_ token: PersonalGoogleDriveRefreshToken) async throws
        -> PersonalGoogleDriveGrant {
        calls += 1
        if suspended {
            await withCheckedContinuation { continuation = $0 }
        }
        return grant
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    var isWaiting: Bool { continuation != nil }
}

@Suite(.serialized)
struct PersonalGoogleDriveAccessTests {
    private func connected(
        suffix: String,
        rotatedAt: Int64 = 2_000_000,
        suspended: Bool = false
    ) throws -> (PersonalGoogleDriveAccessOwner, PersonalGoogleDriveCredentialStore,
                 PersonalGoogleDriveConfiguration, PersonalDriveTokenRefresherStub,
                 UUID) {
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.access-" + suffix,
            keychain: PersonalDriveCredentialKeychainStub()
        )
        let configuration = try personalDriveCredentialConfiguration("201-access-" + suffix)
        let initial = try store.saveInitial(
            personalDriveCredentialGrant(now: 1_000_000),
            configuration: configuration, now: 1_000_000, consent: true
        )
        let refresher = PersonalDriveTokenRefresherStub(
            grant: try personalDriveCredentialGrant(
                refresh: "n", refreshLifetime: nil, now: rotatedAt
            ),
            suspended: suspended
        )
        return (
            PersonalGoogleDriveAccessOwner(
                configuration: configuration, store: store,
                refresher: refresher, now: { rotatedAt }
            ),
            store, configuration, refresher, initial.generation
        )
    }

    @Test func refreshesOnceRotatesExactGenerationAndCachesAccess() async throws {
        let (owner, store, configuration, refresher, original) = try connected(suffix: "cache")
        #expect(try await owner.isConnected())
        _ = try await owner.accessToken()
        _ = try await owner.accessToken()
        #expect(await refresher.calls == 1)
        let loaded = try store.load(configuration: configuration)
        let persisted = try #require(loaded)
        #expect(persisted.generation != original)
        #expect(persisted.phase == .active)
    }

    @Test func concurrentConsumersShareOneRefreshFlight() async throws {
        let (owner, _, _, refresher, _) = try connected(
            suffix: "flight", suspended: true
        )
        let first = Task { try await owner.accessToken() }
        let second = Task { try await owner.accessToken() }
        for _ in 0..<100 {
            if await refresher.isWaiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await refresher.isWaiting)
        #expect(await refresher.calls == 1)
        await refresher.release()
        _ = try await first.value
        _ = try await second.value
        #expect(await refresher.calls == 1)
    }

    @Test func disconnectedAndFencedCredentialsFailClosed() async throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.access-closed",
            keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration("202-access-closed")
        let refresher = PersonalDriveTokenRefresherStub(
            grant: try personalDriveCredentialGrant(now: 1_000_000)
        )
        let owner = PersonalGoogleDriveAccessOwner(
            configuration: configuration, store: store,
            refresher: refresher, now: { 1_000_000 }
        )
        await #expect(throws: PersonalGoogleDriveAccessError.notConnected) {
            try await owner.accessToken()
        }
        let active = try store.saveInitial(
            personalDriveCredentialGrant(now: 1_000_000),
            configuration: configuration, now: 1_000_000, consent: true
        )
        _ = try store.beginRevocation(active)
        await #expect(throws: PersonalGoogleDriveAccessError.cleanupRequired) {
            try await owner.accessToken()
        }
        #expect(await refresher.calls == 0)
    }
}
