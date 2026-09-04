import CryptoKit
import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

extension SessionMemoryKeychain: TeamDeviceMetadataAPI {}

private final class DeviceWriteBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var arrivals = 0
    func arrive() throws {
        let count = lock.withLock { arrivals += 1; return arrivals }
        if count == 2 { semaphore.signal(); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 5) == .success else { throw TeamDeviceCustodyError.unavailable(errSecNotAvailable) }
    }
}
private func onDeviceTestQueue(_ action: @escaping @Sendable () -> Bool) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: action()) }
    }
}

private final class DeviceMemoryStore: TeamDeviceMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var writes = 0
    var beforeWrite: (@Sendable (Int) throws -> Void)?
    var afterWrite: (@Sendable (Int) throws -> Void)?
    func load() throws -> Data? { lock.withLock { data } }
    func replace(expected: Data?, next: Data) throws {
        let index = lock.withLock { writes += 1; return writes }
        try beforeWrite?(index)
        try lock.withLock {
            guard data == expected else { throw TeamDeviceCustodyError.staleOperation }
            data = next
        }
        try afterWrite?(index)
    }
    func corrupt(_ transform: (Data) throws -> Data) throws {
        try lock.withLock { data = try transform(data!) }
    }
    var writeCount: Int { lock.withLock { writes } }
}
// Synthetic in-memory handles; never a production SecureEnclave substitute.
final class DeviceFixtureKeys: TeamDeviceKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Data: P256.Signing.PrivateKey]()
    private var generated = 0
    private var signed = 0
    var onGenerate: (@Sendable () throws -> Void)?
    var onRead: (@Sendable () throws -> Void)?
    var onSign: (@Sendable () throws -> Void)?
    func generate() throws -> TeamDeviceKeyMaterial {
        try onGenerate?()
        let key = P256.Signing.PrivateKey(), opaque = Data(UUID().uuidString.utf8)
        lock.withLock { values[opaque] = key; generated += 1 }
        return try .init(sealed: opaque, publicKey: TeamDeviceEnrollmentWire.publicKey(key.publicKey))
    }
    private func key(_ sealed: Data) throws -> P256.Signing.PrivateKey {
        try lock.withLock {
            guard let value = values[sealed] else { throw TeamDeviceCustodyError.keyUnavailable }; return value
        }
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        try onRead?()
        return try TeamDeviceEnrollmentWire.publicKey(key(sealed).publicKey)
    }
    func sign(sealed: Data, message: Data) throws -> Data {
        try onSign?()
        lock.withLock { signed += 1 }
        return try key(sealed).signature(for: message).rawRepresentation
    }
    func loseKeys() { lock.withLock { values.removeAll() } }
    func replaceKeys() { lock.withLock { values = values.mapValues { _ in P256.Signing.PrivateKey() } } }
    var generationCount: Int { lock.withLock { generated } }
    var signingCount: Int { lock.withLock { signed } }
}
private final class DeviceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Int64 = 1_000
    func now() -> Int64 { lock.withLock { time } }
    func set(_ value: Int64) { lock.withLock { time = value } }
}
private struct DeviceFixture {
    let store = DeviceMemoryStore()
    let keys = DeviceFixtureKeys()
    let clock = DeviceClock()
    let scope: TeamDeviceScope
    init(account: String = "public-account") throws {
        scope = try .init(audience: "https://pinbook.example", accountID: account, authorityEpoch: "public-epoch")
    }
    func owner() -> TeamDeviceCustody { .init(storage: store, keys: keys, clock: { clock.now() }) }
    func prepared(_ snapshot: TeamDeviceSnapshot) throws -> (TeamPreparedDeviceChallenge, TeamDeviceEnrollmentWire.Binding) {
        let key = try #require(snapshot.publicKey)
        let binding = TeamDeviceEnrollmentWire.Binding(audience: scope.audience, authorityEpoch: scope.authorityEpoch,
            accountID: scope.accountID, sessionID: "public-session", deviceID: snapshot.deviceID,
            keyThumbprint: key.thumbprint, accessExpiresAt: 20_000)
        let wire = try JSONSerialization.data(withJSONObject: ["audience": binding.audience, "authorityEpoch": binding.authorityEpoch,
            "accountId": binding.accountID, "sessionId": binding.sessionID, "deviceId": binding.deviceID, "keyThumbprint": binding.keyThumbprint,
            "challengeId": String(repeating: "A", count: 43), "nonce": String(repeating: "B", count: 42) + "A", "expiresAt": 10_000])
        return (try .init(validating: wire, expected: binding, now: clock.now()), binding)
    }
    func registration(_ s: TeamDeviceSnapshot, account: String? = nil) throws -> TeamRegisteredDevice {
        try .init(enrollmentID: "public-enrollment", accountID: account ?? scope.accountID, deviceID: s.deviceID,
            keyThumbprint: #require(s.publicKey).thumbprint, authorityEpoch: scope.authorityEpoch)
    }
}

struct TeamDeviceCustodyTests {
    @Test func keychainAdapterUsesSeparatePasscodeOnlyIndexAndAtomicExpectedPayload() throws {
        let backend = SessionMemoryKeychain()
        let store = try KeychainTeamDeviceMetadata(testService: "pinbook.device-test.public", keychain: backend)
        let a = Data("public-first".utf8), b = Data("public-next".utf8)
        #expect(try store.load() == nil)
        try store.replace(expected: nil, next: a)
        #expect(backend.protection == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
        #expect(backend.synchronizes == false)
        #expect(try store.load() == a)
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try store.replace(expected: nil, next: b) }
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try store.replace(expected: b, next: a) }
        try store.replace(expected: a, next: b)
        #expect(try store.load() == b)
        #expect(throws: TeamDeviceCustodyError.invalidRecord) { try store.replace(expected: b, next: Data(repeating: 1, count: 65_537)) }
        backend.corrupt(kSecAttrGeneric as String, value: Data())
        #expect(throws: TeamDeviceCustodyError.invalidRecord) { try store.load() }
    }
    @Test func keychainAdapterDoesNotSilentlyDowngradeProtectionOrIgnoreUncertainUpdate() throws {
        let backend = SessionMemoryKeychain()
        let store = try KeychainTeamDeviceMetadata(testService: "pinbook.device-test.public", keychain: backend)
        let a = Data("public-first".utf8), b = Data("public-next".utf8)
        try store.replace(expected: nil, next: a)
        backend.failUpdate(afterCommit: true)
        #expect(throws: TeamDeviceCustodyError.unavailable(errSecNotAvailable)) { try store.replace(expected: a, next: b) }
        #expect(try store.load() == b)
        backend.corrupt(kSecAttrAccessible as String, value: kSecAttrAccessibleWhenUnlocked as String)
        #expect(throws: TeamDeviceCustodyError.invalidRecord) { try store.load() }
    }
    @Test func twoOwnersCannotReleaseTwoSignaturesForSameReadyRevision() async throws {
        let f = try DeviceFixture(), owner = f.owner()
        let ready = try owner.prepare(scope: f.scope, consent: true), (challenge, binding) = try f.prepared(ready)
        let barrier = DeviceWriteBarrier()
        f.store.beforeWrite = { write in if write == 3 || write == 4 { try barrier.arrive() } }
        let run: @Sendable () -> Bool = {
            do { _ = try f.owner().signForSubmission(ready, challenge: challenge, binding: binding); return true }
            catch { #expect(error as? TeamDeviceCustodyError == .staleOperation); return false }
        }
        async let first = onDeviceTestQueue(run)
        async let second = onDeviceTestQueue(run)
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1 && f.keys.signingCount == 1)
        #expect(try owner.load(scope: f.scope)?.phase == .submitPending)
    }
    @Test func twoReadyCandidatesHaveOnlyOneDurablyRetainedIdentity() async throws {
        let f = try DeviceFixture()
        f.store.afterWrite = { write in if write == 1 { throw TeamDeviceCustodyError.keyUnavailable } }
        #expect(throws: TeamDeviceCustodyError.keyUnavailable) { try f.owner().prepare(scope: f.scope, consent: true) }
        let reserved = try #require(try f.owner().load(scope: f.scope))
        f.store.afterWrite = nil
        let barrier = DeviceWriteBarrier()
        f.store.beforeWrite = { write in if write == 2 || write == 3 { try barrier.arrive() } }
        let run: @Sendable () -> Bool = {
            do { _ = try f.owner().prepare(scope: f.scope, consent: true); return true }
            catch { #expect(error as? TeamDeviceCustodyError == .staleOperation); return false }
        }
        async let first = onDeviceTestQueue(run)
        async let second = onDeviceTestQueue(run)
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        let stored = try #require(try f.owner().load(scope: f.scope))
        #expect(stored.phase == .ready && stored.deviceID == reserved.deviceID)
        #expect(try f.owner().prepare(scope: f.scope, consent: true).generation == stored.generation)
        #expect(f.keys.generationCount == 2 && f.keys.signingCount == 0)
    }
    @Test func explicitConsentAndBoundedReservationPrecedeKeyCreation() throws {
        let f = try DeviceFixture(), owner = f.owner()
        #expect(throws: TeamDeviceCustodyError.consentRequired) { try owner.prepare(scope: f.scope, consent: false) }
        #expect(f.store.writeCount == 0 && f.keys.generationCount == 0)
        f.keys.onGenerate = { let data = try f.store.load(); #expect(data != nil) }
        for i in 0..<8 {
            let scope = try TeamDeviceScope(audience: f.scope.audience, accountID: "account-\(i)", authorityEpoch: f.scope.authorityEpoch)
            #expect(try owner.prepare(scope: scope, consent: true).phase == .ready)
        }
        #expect(throws: TeamDeviceCustodyError.capacity) { try owner.prepare(scope: f.scope, consent: true) }
        #expect(f.keys.generationCount == 8)
    }
    @Test func stableIdentityReopensAndReturnedValuesDoNotRevealSealedKey() throws {
        let f = try DeviceFixture(), owner = f.owner()
        let first = try owner.prepare(scope: f.scope, consent: true)
        let second = try f.owner().prepare(scope: f.scope, consent: true)
        #expect(first.generation == second.generation && first.deviceID == second.deviceID)
        #expect(first.publicKey?.thumbprint == second.publicKey?.thumbprint && f.keys.generationCount == 1)
        #expect(!String(reflecting: first).contains(first.deviceID))
        #expect(Mirror(reflecting: first).children.isEmpty)
        let bytes = try #require(try f.store.load())
        #expect(!String(decoding: bytes, as: UTF8.self).contains("refreshToken"))
    }
    @Test func failedReservationCannotGenerateAndAmbiguousReadyCommitKeepsSameKey() throws {
        let f = try DeviceFixture()
        f.store.beforeWrite = { _ in throw TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed) }
        #expect(throws: TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed)) { try f.owner().prepare(scope: f.scope, consent: true) }
        #expect(f.keys.generationCount == 0)
        let absent = try f.store.load(); #expect(absent == nil)
        f.store.beforeWrite = nil
        f.store.afterWrite = { write in if write == 3 { throw TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed) } }
        #expect(throws: TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed)) { try f.owner().prepare(scope: f.scope, consent: true) }
        let ready = try #require(try f.owner().load(scope: f.scope))
        #expect(ready.phase == .ready && f.keys.generationCount == 1)
        #expect(try f.owner().prepare(scope: f.scope, consent: true).generation == ready.generation)
    }
    @Test func ambiguousReservationAndUncommittedCandidateDoNotExposeDeviceProof() throws {
        let f = try DeviceFixture()
        f.store.afterWrite = { write in if write == 1 { throw TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed) } }
        #expect(throws: TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed)) { try f.owner().prepare(scope: f.scope, consent: true) }
        let reserved = try #require(try f.owner().load(scope: f.scope))
        #expect(reserved.phase == .reserved && f.keys.generationCount == 0)
        f.store.afterWrite = nil
        f.store.beforeWrite = { write in if write == 2 { throw TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed) } }
        #expect(throws: TeamDeviceCustodyError.unavailable(errSecInteractionNotAllowed)) { try f.owner().prepare(scope: f.scope, consent: true) }
        #expect(try f.owner().load(scope: f.scope)?.deviceID == reserved.deviceID)
        #expect(try f.owner().load(scope: f.scope)?.phase == .reserved)
        #expect(f.keys.signingCount == 0)
        f.store.beforeWrite = nil
        let ready = try f.owner().prepare(scope: f.scope, consent: true)
        #expect(ready.deviceID == reserved.deviceID && ready.phase == .ready)
    }
    @Test func pendingCommitsBeforeSigningAndOnlyOneProofEscapes() throws {
        let f = try DeviceFixture(), owner = f.owner()
        let ready = try owner.prepare(scope: f.scope, consent: true), (challenge, binding) = try f.prepared(ready)
        f.keys.onSign = { let snapshot = try f.owner().load(scope: f.scope); #expect(snapshot?.phase == .submitPending) }
        let proof = try owner.signForSubmission(ready, challenge: challenge, binding: binding)
        #expect(proof.signature.count == 64 && proof.pending.phase == .submitPending && f.keys.signingCount == 1)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: proof.signature)
        let publicKey = try #require(ready.publicKey), message = try challenge.message(expected: binding, now: 1_000)
        #expect(publicKey.key.isValidSignature(parsed, for: message))
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try owner.signForSubmission(ready, challenge: challenge, binding: binding) }
        #expect(throws: TeamDeviceCustodyError.invalidPhase) { try owner.signForSubmission(proof.pending, challenge: challenge, binding: binding) }
        #expect(f.keys.signingCount == 1)
    }
    @Test func lostPendingWriteAndSigningFailureRequireRecoveryNotRetry() throws {
        for failSigning in [false, true] {
            let f = try DeviceFixture(), owner = f.owner()
            let ready = try owner.prepare(scope: f.scope, consent: true), (challenge, binding) = try f.prepared(ready)
            if failSigning { f.keys.onSign = { throw TeamDeviceCustodyError.keyUnavailable } }
            else { f.store.afterWrite = { write in if write == 3 { throw TeamDeviceCustodyError.keyUnavailable } } }
            #expect(throws: TeamDeviceCustodyError.keyUnavailable) { try owner.signForSubmission(ready, challenge: challenge, binding: binding) }
            let pending = try #require(try f.owner().load(scope: f.scope))
            #expect(pending.phase == .submitPending && f.keys.signingCount == 0)
            #expect(throws: TeamDeviceCustodyError.recoveryWait) { try owner.beginRecovery(pending) }
            #expect(throws: TeamDeviceCustodyError.invalidPhase) { try owner.signForSubmission(pending, challenge: challenge, binding: binding) }
        }
    }
    @Test func recoveryUsesFreshGenerationAndNullKeepsExactIdentity() throws {
        let f = try DeviceFixture(), owner = f.owner()
        let ready = try owner.prepare(scope: f.scope, consent: true), (challenge, binding) = try f.prepared(ready)
        let pending = try owner.signForSubmission(ready, challenge: challenge, binding: binding).pending
        f.clock.set(10_000)
        let recovery = try owner.beginRecovery(pending)
        #expect(recovery.generation != pending.generation && recovery.phase == .recovering)
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try owner.recordRegistration(pending, registration: f.registration(pending)) }
        let fresh = try f.owner().beginRecovery(recovery)
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try owner.recordRecoveryAbsence(recovery) }
        let next = try owner.recordRecoveryAbsence(fresh)
        #expect(next.phase == .ready && next.deviceID == ready.deviceID && next.publicKey?.thumbprint == ready.publicKey?.thumbprint)
        #expect(f.keys.generationCount == 1 && f.keys.signingCount == 1)
    }
    @Test func exactRegistrationSurvivesLostCommitAndCannotBeReplacedOrTreatedAsNull() throws {
        let f = try DeviceFixture(), owner = f.owner(), ready = try owner.prepare(scope: f.scope, consent: true)
        #expect(throws: TeamDeviceCustodyError.bindingMismatch) { try owner.recordRegistration(ready, registration: f.registration(ready, account: "wrong-account")) }
        f.store.afterWrite = { write in if write == 3 { throw TeamDeviceCustodyError.keyUnavailable } }
        #expect(throws: TeamDeviceCustodyError.keyUnavailable) { try owner.recordRegistration(ready, registration: f.registration(ready)) }
        let registered = try #require(try f.owner().load(scope: f.scope))
        #expect(registered.phase == .registered && registered.enrollmentID == "public-enrollment")
        #expect(throws: TeamDeviceCustodyError.invalidPhase) { try owner.recordRecoveryAbsence(registered) }
        #expect(throws: TeamDeviceCustodyError.invalidPhase) { try owner.beginRecovery(registered) }
        let wrong = try TeamRegisteredDevice(enrollmentID: "other-enrollment", accountID: f.scope.accountID, deviceID: ready.deviceID,
            keyThumbprint: #require(ready.publicKey).thumbprint, authorityEpoch: f.scope.authorityEpoch)
        #expect(throws: TeamDeviceCustodyError.bindingMismatch) { try owner.recordRegistration(registered, registration: wrong) }
    }
    @Test func keyLossReplacementCorruptionAndClockRollbackNeverRegenerate() throws {
        for replace in [false, true] {
            let f = try DeviceFixture(), owner = f.owner()
            _ = try owner.prepare(scope: f.scope, consent: true)
            if replace { f.keys.replaceKeys() } else { f.keys.loseKeys() }
            #expect(throws: TeamDeviceCustodyError.keyUnavailable) { try owner.prepare(scope: f.scope, consent: true) }
            #expect(f.keys.generationCount == 1)
        }
        let f = try DeviceFixture(), owner = f.owner()
        _ = try owner.prepare(scope: f.scope, consent: true)
        f.clock.set(999)
        #expect(throws: TeamDeviceCustodyError.invalidTime) { try owner.load(scope: f.scope) }
        f.clock.set(1_000)
        try f.store.corrupt { _ in Data(#"{"version":1,"version":1}"#.utf8) }
        #expect(throws: TeamDeviceCustodyError.invalidRecord) { try owner.prepare(scope: f.scope, consent: true) }
        #expect(f.keys.generationCount == 1)
    }
    @Test func expiryOrRecoveryDuringSlowSigningCannotReturnLateProof() throws {
        let f = try DeviceFixture(), owner = f.owner()
        let ready = try owner.prepare(scope: f.scope, consent: true), (challenge, binding) = try f.prepared(ready)
        f.keys.onSign = {
            f.clock.set(10_000)
            let pending = try #require(try f.owner().load(scope: f.scope))
            _ = try f.owner().beginRecovery(pending)
        }
        #expect(throws: TeamDeviceCustodyError.staleOperation) { try owner.signForSubmission(ready, challenge: challenge, binding: binding) }
        #expect(try owner.load(scope: f.scope)?.phase == .recovering)
        #expect(f.keys.signingCount == 1)
    }
    @Test func alreadyCancelledOperationCannotCreateIdentity() async throws {
        let f = try DeviceFixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try f.owner().prepare(scope: f.scope, consent: true) }
        }
        await task.value
        #expect(f.store.writeCount == 0 && f.keys.generationCount == 0)
    }
}
