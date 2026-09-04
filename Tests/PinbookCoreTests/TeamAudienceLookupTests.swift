import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class AudienceSession: TeamAudienceSessionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func invalidate() { lock.withLock { active = false } }
    func requireCurrentAccess(_ ticket: TeamAccountAccessTicket, now: Int64) throws {
        try lock.withLock {
            guard active, now < ticket.accessExpiresAt else { throw TeamAccountSessionError.staleOperation }
        }
    }
}
private actor AudienceGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { waiter = $0 } }
    func release() { let value = waiter; waiter = nil; value?.resume() }
    func hasEntered() -> Bool { entered }
}
private actor AudienceDevices: TeamAudienceDevices {
    private var value: TeamDeviceSnapshot?
    private let signer: P256.Signing.PrivateKey
    private(set) var signatures = 0
    init(_ value: TeamDeviceSnapshot, signer: P256.Signing.PrivateKey) { self.value = value; self.signer = signer }
    func load(scope: TeamDeviceScope) -> TeamDeviceSnapshot? { value?.scope == scope ? value : nil }
    func requireCurrent(_ expected: TeamDeviceSnapshot) throws {
        guard value?.generation == expected.generation else { throw TeamDeviceCustodyError.staleOperation }
    }
    func signRequest<Request: TeamDeviceRequestPayload>(_ expected: TeamDeviceSnapshot,
                     challenge: TeamPreparedDeviceRequestChallenge,
                     binding: TeamDeviceRequestWire.Binding, request: Request,
                     checkAuthority: @escaping @Sendable () throws -> Void) throws -> Data {
        try requireCurrent(expected); try checkAuthority(); signatures += 1
        let message = try challenge.message(expected: binding, publicKey: signerPublic(), request: request, now: 1_000)
        let result = try signer.signature(for: message).rawRepresentation
        try checkAuthority(); try requireCurrent(expected); return result
    }
    func invalidate() {
        guard let old = value else { return }
        value = .init(scope: old.scope, deviceID: old.deviceID, generation: UUID(), phase: old.phase,
            observedAt: old.observedAt, publicKey: old.publicKey, proofExpiresAt: old.proofExpiresAt,
            enrollmentID: old.enrollmentID)
    }
    func snapshot() -> TeamDeviceSnapshot? { value }
    private func signerPublic() throws -> TeamDeviceEnrollmentWire.PublicKey {
        try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
    }
}
private actor AudienceTransport: TeamAudienceTransport {
    enum Hook: Equatable { case none, invalidateSession, invalidateDevice }
    private let session: AudienceSession
    private let devices: AudienceDevices
    private let account: TeamAccountAccessTicket
    private let local: TeamDeviceSnapshot
    private let key: TeamDeviceEnrollmentWire.PublicKey
    private let targetKey: TeamDeviceEnrollmentWire.PublicKey
    private let targetAgreementKey: TeamDeviceEnrollmentWire.PublicKey
    private var lookupHook = Hook.none, membershipHook = Hook.none, challengeHook = Hook.none, executeHook = Hook.none
    private var gate: AudienceGate?
    private var wrongTeam = false, badTarget = false
    private(set) var calls = [String]()
    init(session: AudienceSession, devices: AudienceDevices, account: TeamAccountAccessTicket,
         local: TeamDeviceSnapshot, key: TeamDeviceEnrollmentWire.PublicKey,
         targetKey: TeamDeviceEnrollmentWire.PublicKey,
         targetAgreementKey: TeamDeviceEnrollmentWire.PublicKey) {
        self.session = session; self.devices = devices; self.account = account
        self.local = local; self.key = key; self.targetKey = targetKey
        self.targetAgreementKey = targetAgreementKey
    }
    func configure(lookup: Hook = .none, membership: Hook = .none, challenge: Hook = .none,
                   execute: Hook = .none, gate: AudienceGate? = nil,
                   wrongTeam: Bool = false, badTarget: Bool = false) {
        lookupHook = lookup; membershipHook = membership; challengeHook = challenge
        executeHook = execute; self.gate = gate; self.wrongTeam = wrongTeam; self.badTarget = badTarget
    }
    func apply(_ hook: Hook) async {
        if hook == .invalidateSession { session.invalidate() }
        if hook == .invalidateDevice { await devices.invalidate() }
    }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                      ticket: TeamAccountAccessTicket) async -> TeamRegisteredDevice? {
        calls.append("device"); await apply(lookupHook)
        return .init(enrollmentID: local.enrollmentID!, accountID: account.accountID,
            deviceID: local.deviceID, keyThumbprint: key.thumbprint, authorityEpoch: local.scope.authorityEpoch)
    }
    func currentTeam(teamID: String, enrollmentID: String,
                     ticket: TeamAccountAccessTicket) async -> TeamMembership {
        calls.append("membership"); await apply(membershipHook)
        return .init(teamID: teamID, accountID: account.accountID, enrollmentID: enrollmentID,
            role: .member, revision: 7)
    }
    func deviceRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                request: TeamAudienceRevisionRequest,
                                ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        calls.append("challenge")
        let body = Data("{\"membershipRevision\":\(request.membershipRevision)}".utf8)
        let object: [String: Any] = ["audience": expected.audience, "authorityEpoch": expected.authorityEpoch,
            "accountId": expected.accountID, "sessionId": expected.sessionID, "deviceId": expected.deviceID,
            "enrollmentId": expected.enrollmentID, "keyThumbprint": expected.keyThumbprint,
            "operation": expected.operation.rawValue, "teamId": expected.teamID, "requestId": expected.requestID,
            "bodySha256": try TeamDeviceRequestWire.bodySHA256(body),
            "challengeId": String(repeating: "A", count: 43),
            "nonce": String(repeating: "B", count: 42) + "A", "expiresAt": 9_000]
        let result = try TeamPreparedDeviceRequestChallenge(validating:
            JSONSerialization.data(withJSONObject: object), expected: expected,
            publicKey: publicKey, request: request, now: 1_000)
        await apply(challengeHook); return result
    }
    func executeDeviceRequest(challenge: TeamPreparedDeviceRequestChallenge,
                              signature: Data, expected: TeamDeviceRequestWire.Binding,
                              publicKey: TeamDeviceEnrollmentWire.PublicKey,
                              request: TeamAudienceRevisionRequest,
                              ticket: TeamAccountAccessTicket) async throws -> TeamAudience {
        calls.append("execute")
        let message = try challenge.message(expected: expected, publicKey: publicKey, request: request, now: 1_000)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        guard key.key.isValidSignature(parsed, for: message) else { throw TeamAudienceLookupError.invalidResponse }
        if let gate { await gate.wait() }
        await apply(executeHook)
        let target = TeamAudienceTarget(accountID: "peer-account", deviceID: "peer-device",
            enrollmentID: "peer-enrollment", keyThumbprint: badTarget ? key.thumbprint : targetKey.thumbprint,
            publicKey: targetKey, agreementKeyThumbprint: targetAgreementKey.thumbprint,
            agreementPublicKey: targetAgreementKey)
        return .init(teamID: wrongTeam ? "other-team" : expected.teamID,
            membershipRevision: request.membershipRevision, targets: [target])
    }
}

@Suite(.serialized)
struct TeamAudienceLookupTests {
    private struct Fixture {
        let account: TeamAccountAccessTicket
        let session: AudienceSession
        let devices: AudienceDevices
        let transport: AudienceTransport
        let owner: TeamAudienceLookup
        let local: TeamDeviceSnapshot
    }
    private func make(expiry: Int64 = 10_000, wall: Int64 = 1_000) throws -> Fixture {
        let scope = try TeamAccountSessionScope(origin: URL(string: "https://audience.invalid")!, providerID: "public-ios")
        let pair = TeamAuthSessionPair(accountID: "account", sessionID: "session",
            accessToken: String(repeating: "C", count: 42) + "A",
            refreshToken: String(repeating: "D", count: 42) + "A",
            accessExpiresAt: expiry, sessionExpiresAt: 30_000)
        let account = try TeamAccountAccessTicket(snapshot: TeamAccountSessionCodec.active(pair: pair, scope: scope, now: 1_000))
        let signer = P256.Signing.PrivateKey(), key = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let deviceScope = try TeamDeviceScope(audience: "https://audience.invalid", accountID: "account", authorityEpoch: "epoch")
        let local = TeamDeviceSnapshot(scope: deviceScope, deviceID: "device", generation: UUID(), phase: .registered,
            observedAt: 1_000, publicKey: key, proofExpiresAt: nil, enrollmentID: "enrollment")
        let sessions = AudienceSession(), devices = AudienceDevices(local, signer: signer)
        let target = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let targetAgreement = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let transport = AudienceTransport(session: sessions, devices: devices, account: account,
            local: local, key: key, targetKey: target, targetAgreementKey: targetAgreement)
        let owner = try TeamAudienceLookup(account: account, authorityEpoch: "epoch", sessions: sessions,
            devices: devices, transport: transport, clock: { .init(wallTime: wall, instant: .now) },
            requestID: { String(repeating: "E", count: 42) + "A" })
        return .init(account: account, session: sessions, devices: devices, transport: transport, owner: owner, local: local)
    }
    private func wait(_ gate: AudienceGate) async throws {
        for _ in 0..<200 { if await gate.hasEntered() { return }; try await Task.sleep(for: .milliseconds(5)) }
        Issue.record("Audience operation did not enter gate")
    }
    @Test func exactCurrentAccountDeviceMembershipProofAndAudienceRunOnce() async throws {
        let value = try make(), result = try await value.owner.audience(teamID: "team", enrollmentID: "enrollment")
        #expect(result.teamID == "team" && result.membershipRevision == 7 && result.targets.map(\.accountID) == ["peer-account"])
        #expect(await value.transport.calls == ["device", "membership", "challenge", "execute"])
        #expect(await value.devices.signatures == 1)
        #expect(await value.devices.snapshot()?.phase == .registered)
    }
    @Test func accountLossAtEachRemoteBoundaryStopsTheFollowingStage() async throws {
        for stage in ["device", "membership", "challenge"] {
            let value = try make()
            await value.transport.configure(lookup: stage == "device" ? .invalidateSession : .none,
                membership: stage == "membership" ? .invalidateSession : .none,
                challenge: stage == "challenge" ? .invalidateSession : .none)
            await #expect(throws: (any Error).self) { try await value.owner.audience(teamID: "team", enrollmentID: "enrollment") }
            let calls = await value.transport.calls
            #expect(calls.count == (stage == "device" ? 1 : stage == "membership" ? 2 : 3))
        }
    }
    @Test func deviceChangeWrongAudienceAndMalformedTargetNeverReturnAuthority() async throws {
        let changed = try make()
        await changed.transport.configure(execute: .invalidateDevice)
        await #expect(throws: (any Error).self) { try await changed.owner.audience(teamID: "team", enrollmentID: "enrollment") }
        let wrong = try make(); await wrong.transport.configure(wrongTeam: true)
        await #expect(throws: TeamAudienceLookupError.invalidResponse) { try await wrong.owner.audience(teamID: "team", enrollmentID: "enrollment") }
        let malformed = try make(); await malformed.transport.configure(badTarget: true)
        await #expect(throws: TeamAudienceLookupError.invalidResponse) { try await malformed.owner.audience(teamID: "team", enrollmentID: "enrollment") }
    }
    @Test func wrongEnrollmentAndExpiredAccessStopBeforeRemoteWork() async throws {
        let wrong = try make()
        await #expect(throws: TeamAudienceLookupError.deviceUnavailable) {
            try await wrong.owner.audience(teamID: "team", enrollmentID: "other")
        }
        #expect(await wrong.transport.calls.isEmpty)
        let expired = try make(expiry: 1_001, wall: 1_001)
        await #expect(throws: TeamAudienceLookupError.expired) {
            try await expired.owner.audience(teamID: "team", enrollmentID: "enrollment")
        }
        #expect(await expired.transport.calls.isEmpty)
    }
    @Test func cancellationRetainsBusyOwnershipUntilUncooperativeExecuteSettles() async throws {
        let value = try make(), gate = AudienceGate()
        await value.transport.configure(gate: gate)
        let work = Task { try await value.owner.audience(teamID: "team", enrollmentID: "enrollment") }
        try await wait(gate); await value.owner.cancelPendingLookup()
        await #expect(throws: TeamAudienceLookupError.busy) {
            try await value.owner.audience(teamID: "team", enrollmentID: "enrollment")
        }
        await gate.release()
        await #expect(throws: (any Error).self) { try await work.value }
        #expect(await value.transport.calls == ["device", "membership", "challenge", "execute"])
    }
}
