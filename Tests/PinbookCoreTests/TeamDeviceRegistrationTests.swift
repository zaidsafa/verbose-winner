import CryptoKit
import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class RegistrationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TeamSignInMoment(wallTime: 1_000, instant: .now)
    func now() -> TeamSignInMoment { lock.withLock { value } }
    func advance(wall: Int64 = 0, elapsed: Duration = .zero) {
        lock.withLock { value = .init(wallTime: value.wallTime + wall, instant: value.instant.advanced(by: elapsed)) }
    }
}
private final class RegistrationOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func run(_ action: () throws -> Void) rethrows {
        let first = lock.withLock { if used { return false }; used = true; return true }
        if first { try action() }
    }
}
private final class RegistrationMetadata: TeamDeviceMetadataStore, @unchecked Sendable {
    let backend = SessionMemoryKeychain()
    let store: KeychainTeamDeviceMetadata
    var afterWrite: (@Sendable (Int) throws -> Void)?
    init() throws { store = try .init(testService: "pinbook.device-test.registration", keychain: backend) }
    func load() throws -> Data? { try store.load() }
    func replace(expected: Data?, next: Data) throws {
        try store.replace(expected: expected, next: next)
        try afterWrite?(backend.writes)
    }
}
private actor RegistrationTransport: TeamDeviceRegistering {
    private var registered = false
    private let initiallyRegistered: Bool
    private let wrongAccount: Bool
    private let gateCompletion: Bool
    private var failCompletion: Bool
    private var completion: CheckedContinuation<Void, Never>?
    private var lastKey: TeamDeviceEnrollmentWire.PublicKey?
    private var lastChallenge: TeamPreparedDeviceChallenge?
    private let hook: @Sendable (String) async throws -> Void
    private(set) var paths = [String]()
    init(registered: Bool = false, wrongAccount: Bool = false, gateCompletion: Bool = false,
         failCompletion: Bool = false, hook: @escaping @Sendable (String) async throws -> Void = { _ in }) {
        initiallyRegistered = registered; self.wrongAccount = wrongAccount; self.gateCompletion = gateCompletion
        self.failCompletion = failCompletion; self.hook = hook
    }
    private func result(_ binding: TeamDeviceEnrollmentWire.Binding) -> TeamRegisteredDevice {
        .init(enrollmentID: "public-enrollment", accountID: wrongAccount ? "foreign-account" : binding.accountID,
            deviceID: binding.deviceID, keyThumbprint: binding.keyThumbprint, authorityEpoch: binding.authorityEpoch)
    }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice? {
        paths.append("lookup"); lastKey = key
        try await hook("lookup")
        return registered || initiallyRegistered ? result(expected) : nil
    }
    func deviceChallenge(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceChallenge {
        paths.append("challenge"); lastKey = key
        let data = try JSONSerialization.data(withJSONObject: ["audience": expected.audience, "accountId": expected.accountID,
            "authorityEpoch": expected.authorityEpoch, "sessionId": expected.sessionID, "deviceId": expected.deviceID,
            "keyThumbprint": expected.keyThumbprint, "expiresAt": 9_000,
            "challengeId": String(repeating: "A", count: 43), "nonce": String(repeating: "B", count: 42) + "A"])
        let challenge = try TeamPreparedDeviceChallenge(validating: data, expected: expected, now: 1_000)
        lastChallenge = challenge
        try await hook("challenge")
        return challenge
    }
    func completeDevice(challenge: TeamPreparedDeviceChallenge, signature: Data, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice {
        paths.append("complete")
        let key = try #require(lastKey), message = try #require(lastChallenge).message(expected: expected, now: 1_000)
        #expect(try key.key.isValidSignature(P256.Signing.ECDSASignature(rawRepresentation: signature), for: message))
        registered = true // Simulate a server commit even if its response is lost.
        if gateCompletion { await withCheckedContinuation { completion = $0 } }
        try await hook("complete")
        if failCompletion { failCompletion = false; throw TeamAuthHTTPError.transport }
        return result(expected)
    }
    func finish() { let saved = completion; completion = nil; saved?.resume() }
}
private struct RegistrationFixture {
    let scope: TeamAccountSessionScope
    let clock = RegistrationClock()
    let metadata: RegistrationMetadata
    let keys = DeviceFixtureKeys()
    let sessionBackend = SessionMemoryKeychain()
    let sessions: TeamAccountSessionStore
    let custody: TeamDeviceCustody
    let pair = TeamAuthSessionPair(accountID: "public-account", sessionID: "public-session", accessToken: String(repeating: "C", count: 42) + "A",
        refreshToken: String(repeating: "D", count: 42) + "A", accessExpiresAt: 20_000, sessionExpiresAt: 30_000)
    init() throws {
        scope = try .init(origin: URL(string: "https://pinbook.example")!, providerID: "public-ios")
        sessions = .init(testService: "registration-account", keychain: sessionBackend)
        metadata = try RegistrationMetadata()
        let time = clock
        custody = .init(storage: metadata, keys: keys, clock: { time.now().wallTime })
        _ = try sessions.saveInitial(pair, scope: scope, now: 1_000, consent: true)
    }
    var deviceScope: TeamDeviceScope { get throws { try .init(audience: "https://pinbook.example", accountID: pair.accountID, authorityEpoch: "public-epoch") } }
    func owner(_ transport: RegistrationTransport) throws -> TeamDeviceRegistration {
        try .init(scope: scope, authorityEpoch: "public-epoch", sessions: sessions,
            devices: TeamRegistrationCustodyDriver(custody: custody), transport: transport, clock: { clock.now() })
    }
    func signOut() throws { try sessions.removeCurrent(scope: scope, consent: true) }
    func state() throws -> TeamDeviceSnapshot? { try custody.load(scope: deviceScope) }
}

struct TeamDeviceRegistrationTests {
    @Test func ticketContainsOnlyAccessAndExactGenerationDoesNotSurviveSignOutOrRefresh() throws {
        let f = try RegistrationFixture()
        let ticket = try f.sessions.accessTicket(scope: f.scope, now: 1_000)
        #expect(try ticket.usableToken(now: 1_000) == f.pair.accessToken)
        #expect(Mirror(reflecting: ticket).children.isEmpty && !String(reflecting: ticket).contains(f.pair.accessToken))
        try f.sessions.requireCurrentAccess(ticket, now: 1_000)
        let snapshot = try #require(try f.sessions.load(scope: f.scope))
        let lease = try f.sessions.beginRefresh(snapshot, now: 1_000)
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try f.sessions.requireCurrentAccess(ticket, now: 1_000) }
        let next = TeamAuthSessionPair(accountID: f.pair.accountID, sessionID: f.pair.sessionID, accessToken: String(repeating: "E", count: 42) + "A",
            refreshToken: String(repeating: "F", count: 42) + "A", accessExpiresAt: 20_000, sessionExpiresAt: 30_000)
        _ = try f.sessions.completeRefresh(lease, next: next, now: 1_000)
        #expect(throws: TeamAccountSessionError.staleOperation) { try f.sessions.requireCurrentAccess(ticket, now: 1_000) }
        let fresh = try f.sessions.accessTicket(scope: f.scope, now: 1_000)
        try f.signOut()
        _ = try f.sessions.saveInitial(next, scope: f.scope, now: 1_000, consent: true)
        #expect(throws: TeamAccountSessionError.staleOperation) { try f.sessions.requireCurrentAccess(fresh, now: 1_000) }
    }
    @Test func forgedTicketIdentityAndExpiredAccessAreRefused() throws {
        let f = try RegistrationFixture(), s = try #require(try f.sessions.load(scope: f.scope))
        let forged = TeamAccountSessionSnapshot(scope: s.scope, phase: .active, accountID: "foreign-account", sessionID: s.sessionID,
            sessionExpiresAt: s.sessionExpiresAt, generation: s.generation, observedAt: s.observedAt, pair: s.pair)
        let ticket = try TeamAccountAccessTicket(snapshot: forged)
        #expect(throws: TeamAccountSessionError.staleOperation) { try f.sessions.requireCurrentAccess(ticket, now: 1_000) }
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try f.sessions.accessTicket(scope: f.scope, now: 20_000) }
    }
    @Test func registrationAndEveryLaterRunRequireFreshLookup() async throws {
        let f = try RegistrationFixture(), transport = RegistrationTransport(), owner = try f.owner(transport)
        guard case .registered(let saved) = try await owner.register(consent: true) else { Issue.record("Expected registration"); return }
        #expect(saved.enrollmentID == "public-enrollment" && f.keys.signingCount == 1)
        guard case .registered(let refreshed) = try await owner.register(consent: true) else { Issue.record("Expected fresh lookup"); return }
        #expect(refreshed.deviceID == saved.deviceID && f.keys.signingCount == 1)
        #expect(await transport.paths == ["lookup", "challenge", "complete", "lookup"])
    }
    @Test func readyIdentityAdoptsLateCommitWithoutAnotherProof() async throws {
        let f = try RegistrationFixture(), transport = RegistrationTransport(registered: true)
        guard case .registered = try await f.owner(transport).register(consent: true) else { Issue.record("Expected adoption"); return }
        #expect(await transport.paths == ["lookup"])
        #expect(f.keys.signingCount == 0)
    }
    @Test func lostCompletionWaitsThenReconcilesWithoutAutomaticRepeat() async throws {
        let f = try RegistrationFixture(), transport = RegistrationTransport(failCompletion: true), owner = try f.owner(transport)
        await #expect(throws: TeamDeviceRegistrationError.transportFailure) { try await owner.register(consent: true) }
        let pending = try #require(try f.state())
        guard case .recoveryWait(let until) = try await owner.register(consent: true) else { Issue.record("Expected recovery wait"); return }
        #expect(until == 9_000 && f.keys.signingCount == 1)
        f.clock.advance(wall: 8_000, elapsed: .seconds(8))
        guard case .registered(let saved) = try await owner.register(consent: true) else { Issue.record("Expected recovered registration"); return }
        #expect(saved.deviceID == pending.deviceID && saved.publicKey?.thumbprint == pending.publicKey?.thumbprint)
        #expect(await transport.paths == ["lookup", "challenge", "complete", "lookup"])
        #expect(f.keys.generationCount == 1 && f.keys.signingCount == 1)
    }
    @Test func explicitRecoveryNullReturnsRetryReadyNotAutomaticNewChallenge() async throws {
        let f = try RegistrationFixture(), first = RegistrationTransport(failCompletion: true)
        await #expect(throws: TeamDeviceRegistrationError.transportFailure) { try await f.owner(first).register(consent: true) }
        let pending = try #require(try f.state())
        f.clock.advance(wall: 8_000, elapsed: .seconds(8))
        let emptyServer = RegistrationTransport()
        guard case .retryReady(let ready) = try await f.owner(emptyServer).register(consent: true) else { Issue.record("Expected same-key retry state"); return }
        #expect(ready.deviceID == pending.deviceID && ready.publicKey?.thumbprint == pending.publicKey?.thumbprint)
        #expect(await emptyServer.paths == ["lookup"])
        #expect(f.keys.generationCount == 1 && f.keys.signingCount == 1)
    }
    @Test func registeredAbsenceAndForeignLookupNeverRotateIdentity() async throws {
        let f = try RegistrationFixture(), accepted = RegistrationTransport(registered: true)
        _ = try await f.owner(accepted).register(consent: true)
        let absent = RegistrationTransport()
        await #expect(throws: TeamDeviceRegistrationError.registrationUnavailable) { try await f.owner(absent).register(consent: true) }
        #expect(try f.state()?.phase == .registered)
        let foreign = RegistrationTransport(registered: true, wrongAccount: true)
        await #expect(throws: TeamDeviceCustodyError.bindingMismatch) { try await f.owner(foreign).register(consent: true) }
        #expect(f.keys.generationCount == 1 && f.keys.signingCount == 0)
    }
    @Test func signOutAtEveryNetworkStagePreventsSuccessfulFlow() async throws {
        for stage in ["lookup", "challenge", "complete"] {
            let f = try RegistrationFixture()
            let transport = RegistrationTransport(hook: { step in if step == stage { try f.signOut() } })
            await #expect(throws: TeamAccountSessionError.staleOperation) { try await f.owner(transport).register(consent: true) }
            let paths = await transport.paths
            #expect(paths.last == stage)
            #expect(try f.sessions.load(scope: f.scope) == nil)
        }
    }
    @Test func signOutDuringDeviceReadSigningOrMetadataCommitNeverReturnsAuthority() async throws {
        for stage in ["read", "sign", "commit"] {
            let f = try RegistrationFixture(), once = RegistrationOnce()
            if stage == "read" { f.keys.onRead = { try once.run { try f.signOut() } } }
            if stage == "sign" { f.keys.onSign = { try once.run { try f.signOut() } } }
            if stage == "commit" { f.metadata.afterWrite = { count in if count == 4 { try once.run { try f.signOut() } } } }
            let transport = RegistrationTransport()
            await #expect(throws: TeamAccountSessionError.staleOperation) { try await f.owner(transport).register(consent: true) }
            if stage == "commit" { #expect(try f.state()?.phase == .registered) }
            if stage == "read" { #expect(await transport.paths.isEmpty) }
            if stage == "sign" { #expect(await transport.paths == ["lookup", "challenge"]) }
        }
    }
    @Test func wallRollbackMonotonicLifetimeAndProofDeadlineAreChecked() async throws {
        for scenario in ["rollback", "lifetime", "proof", "signingDeadline"] {
            let f = try RegistrationFixture()
            if scenario == "signingDeadline" { f.keys.onSign = { f.clock.advance(elapsed: .seconds(9)) } }
            let transport = RegistrationTransport(hook: { stage in
                if scenario == "rollback", stage == "lookup" { f.clock.advance(wall: -1) }
                if scenario == "lifetime", stage == "lookup" { f.clock.advance(elapsed: .seconds(125)) }
                if scenario == "proof", stage == "complete" { f.clock.advance(elapsed: .seconds(9)) }
            })
            do { _ = try await f.owner(transport).register(consent: true); Issue.record("Accepted expired flow") }
            catch { #expect(error is TeamDeviceRegistrationError || error is TeamAccountSessionError || error is TeamDeviceCustodyError) }
            if scenario == "proof" || scenario == "signingDeadline" { #expect(try f.state()?.phase == .submitPending) }
            if scenario == "signingDeadline" { #expect(await transport.paths == ["lookup", "challenge"]) }
        }
    }
    @Test func changedDeviceGenerationAfterNetworkCannotContinueOldOperation() async throws {
        for stage in ["lookup", "challenge", "complete"] {
            let f = try RegistrationFixture()
            let transport = RegistrationTransport(hook: { step in
                guard step == stage else { return }
                let current = try #require(try f.state()), key = try #require(current.publicKey)
                let registration = TeamRegisteredDevice(enrollmentID: "public-enrollment", accountID: f.pair.accountID,
                    deviceID: current.deviceID, keyThumbprint: key.thumbprint, authorityEpoch: "public-epoch")
                _ = try f.custody.recordRegistration(current, registration: registration)
            })
            await #expect(throws: TeamDeviceCustodyError.staleOperation) { try await f.owner(transport).register(consent: true) }
            #expect(await transport.paths.last == stage)
        }
    }
    @Test func cancelledNonCooperativeCompletionRetainsBusySlotUntilSettlement() async throws {
        let f = try RegistrationFixture(), transport = RegistrationTransport(gateCompletion: true), owner = try f.owner(transport)
        let task = Task { try await owner.register(consent: true) }
        for _ in 0..<200 {
            if await transport.paths.contains("complete") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await transport.paths.contains("complete"))
        await owner.cancelPendingRegistration()
        await #expect(throws: TeamDeviceRegistrationError.busy) { try await owner.register(consent: true) }
        await transport.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try f.state()?.phase == .submitPending)
        guard case .recoveryWait = try await owner.register(consent: true) else { Issue.record("Expected unresolved-proof wait"); return }
    }
    @Test func absentExpiredOrAlreadyCancelledSessionCannotCreateDeviceKey() async throws {
        for condition in ["absent", "expired", "cancelled"] {
            let f = try RegistrationFixture(), transport = RegistrationTransport(), owner = try f.owner(transport)
            if condition == "absent" { try f.signOut() }
            if condition == "expired" { f.clock.advance(wall: 19_000) }
            let task = Task {
                if condition == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
                do { _ = try await owner.register(consent: true); Issue.record("Unexpected registration") } catch {}
            }
            await task.value
            #expect(f.keys.generationCount == 0 && f.metadata.backend.writes == 0)
            #expect(await transport.paths.isEmpty)
        }
    }
}
