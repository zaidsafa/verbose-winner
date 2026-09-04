import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class AgreementMemoryStore: TeamAgreementKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: Data]()
    var failAfterInsert = false
    func load(scope: String) -> Data? { lock.withLock { values[scope] } }
    func insert(scope: String, sealed: Data) throws -> Bool {
        try lock.withLock {
            guard values[scope] == nil else { return false }
            values[scope] = sealed
            if failAfterInsert { throw TeamAgreementKeyError.unavailable }
            return true
        }
    }
}
private final class AgreementFixtureKeys: TeamAgreementKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Data: P256.KeyAgreement.PrivateKey]()
    private(set) var creates = 0
    var afterAgree: (@Sendable () -> Void)?
    func generate() throws -> TeamAgreementKeyMaterial {
        let key = P256.KeyAgreement.PrivateKey(), sealed = Data(UUID().uuidString.utf8)
        lock.withLock { values[sealed] = key; creates += 1 }
        return try .init(sealed: sealed, publicKey: wire(key.publicKey))
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        guard let value = lock.withLock({ values[sealed] }) else { throw TeamAgreementKeyError.keyUnavailable }
        return try wire(value.publicKey)
    }
    func agree(sealed: Data, peer: TeamDeviceEnrollmentWire.PublicKey) throws -> Data {
        guard let value = lock.withLock({ values[sealed] }) else { throw TeamAgreementKeyError.keyUnavailable }
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: peer.key.x963Representation)
        let secret = try value.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Data($0) }
        afterAgree?(); return secret
    }
    private func wire(_ key: P256.KeyAgreement.PublicKey) throws -> TeamDeviceEnrollmentWire.PublicKey {
        try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PublicKey(x963Representation: key.x963Representation))
    }
}
private final class AgreementAccess: @unchecked Sendable {
    private let lock = NSLock(); private var allowed = true
    func deny() { lock.withLock { allowed = false } }
    func check() throws { if !lock.withLock({ allowed }) { throw TeamAgreementKeyError.accessLost } }
}

@Suite(.serialized)
struct TeamAgreementKeyCustodyTests {
    private func owner(account: String = "account", enrollment: String = "enrollment",
                       store: AgreementMemoryStore = .init(), keys: AgreementFixtureKeys = .init(),
                       access: AgreementAccess = .init()) throws -> TeamAgreementKeyCustody {
        try .init(origin: "https://pinbook.invalid", accountID: account,
            authorityEpoch: "epoch", enrollmentID: enrollment, storage: store,
            keys: keys, requireAccess: access.check)
    }

    @Test func explicitPrepareIsStableCurrentNeverCreatesAndDescriptionsAreRedacted() throws {
        let store = AgreementMemoryStore(), keys = AgreementFixtureKeys(), access = AgreementAccess()
        let value = try owner(store: store, keys: keys, access: access)
        #expect(throws: TeamAgreementKeyError.keyUnavailable) { try value.current() }
        let first = try value.prepare(), second = try value.prepare()
        #expect(first.keyThumbprint == second.keyThumbprint && keys.creates == 1)
        #expect(try value.current().keyThumbprint == first.keyThumbprint)
        #expect(!first.description.contains(first.keyThumbprint))
    }

    @Test func exactBindingsHaveSeparateOpaqueAgreementIdentities() throws {
        let store = AgreementMemoryStore(), keys = AgreementFixtureKeys()
        let first = try owner(store: store, keys: keys).prepare()
        let account = try owner(account: "other", store: store, keys: keys).prepare()
        let enrollment = try owner(enrollment: "other", store: store, keys: keys).prepare()
        #expect(first.keyThumbprint != account.keyThumbprint)
        #expect(first.keyThumbprint != enrollment.keyThumbprint && keys.creates == 3)
    }

    @Test func ambiguousInsertAdoptsOnlyTheExactReadableWinner() throws {
        let store = AgreementMemoryStore(), keys = AgreementFixtureKeys()
        store.failAfterInsert = true
        let value = try owner(store: store, keys: keys)
        let first = try value.prepare()
        #expect(try value.current().keyThumbprint == first.keyThumbprint)
        #expect(keys.creates == 1)
    }

    @Test func twoCustodiesDeriveEqualWrappingKeyAndRejectChangedThumbprint() throws {
        let store = AgreementMemoryStore(), keys = AgreementFixtureKeys()
        let alice = try owner(account: "alice", enrollment: "alice-enrollment", store: store, keys: keys)
        let bob = try owner(account: "bob", enrollment: "bob-enrollment", store: store, keys: keys)
        let alicePublic = try alice.prepare(), bobPublic = try bob.prepare()
        var first = try alice.derive(peer: bobPublic, algorithm: "ECDH-ES+A256KW",
            partyU: Data("delivery".utf8), partyV: Data("bob".utf8))
        var second = try bob.derive(peer: alicePublic, algorithm: "ECDH-ES+A256KW",
            partyU: Data("delivery".utf8), partyV: Data("bob".utf8))
        defer {
            first.resetBytes(in: first.startIndex..<first.endIndex)
            second.resetBytes(in: second.startIndex..<second.endIndex)
        }
        #expect(first == second)
        let changed = TeamAgreementPublic(keyThumbprint: alicePublic.keyThumbprint,
            publicKey: bobPublic.publicKey)
        #expect(throws: TeamAgreementKeyError.keyUnavailable) {
            try alice.derive(peer: changed, algorithm: "ECDH-ES+A256KW",
                partyU: Data(), partyV: Data())
        }
    }

    @Test func accessLossAfterAgreementAndMalformedScopeFailClosed() throws {
        let store = AgreementMemoryStore(), keys = AgreementFixtureKeys(), access = AgreementAccess()
        let first = try owner(store: store, keys: keys, access: access)
        let peer = try owner(account: "peer", enrollment: "peer-enrollment",
            store: store, keys: keys).prepare()
        _ = try first.prepare(); keys.afterAgree = access.deny
        #expect(throws: TeamAgreementKeyError.accessLost) {
            try first.derive(peer: peer, algorithm: "ECDH-ES+A256KW",
                partyU: Data("delivery".utf8), partyV: Data("peer".utf8))
        }
        #expect(throws: TeamAgreementKeyError.invalidScope) {
            try TeamAgreementKeyCustody(origin: "http://pinbook.invalid", accountID: "account",
                authorityEpoch: "epoch", enrollmentID: "enrollment", storage: store,
                keys: keys, requireAccess: {})
        }
    }
}
