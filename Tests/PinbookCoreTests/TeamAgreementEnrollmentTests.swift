import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class EnrollmentSession: TeamAudienceSessionChecking, @unchecked Sendable {
    private let lock = NSLock(); private var active = true
    func invalidate() { lock.withLock { active = false } }
    func requireCurrentAccess(_ ticket: TeamAccountAccessTicket, now: Int64) throws {
        guard lock.withLock({ active }), now < ticket.accessExpiresAt else {
            throw TeamAccountSessionError.staleOperation
        }
    }
}
private actor EnrollmentGate {
    private var entered = false; private var waiter: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { waiter = $0 } }
    func release() { let value = waiter; waiter = nil; value?.resume() }
    func hasEntered() -> Bool { entered }
}
private actor EnrollmentDevices: TeamAudienceDevices {
    private var value: TeamDeviceSnapshot?
    private let signer: P256.Signing.PrivateKey
    private(set) var signatures = 0
    init(_ value: TeamDeviceSnapshot, signer: P256.Signing.PrivateKey) {
        self.value = value; self.signer = signer
    }
    func load(scope: TeamDeviceScope) -> TeamDeviceSnapshot? { value?.scope == scope ? value : nil }
    func requireCurrent(_ expected: TeamDeviceSnapshot) throws {
        guard value?.generation == expected.generation else { throw TeamDeviceCustodyError.staleOperation }
    }
    func signRequest<Request: TeamDeviceRequestPayload>(_ expected: TeamDeviceSnapshot,
                     challenge: TeamPreparedDeviceRequestChallenge,
                     binding: TeamDeviceRequestWire.Binding, request: Request,
                     checkAuthority: @escaping @Sendable () throws -> Void) throws -> Data {
        try requireCurrent(expected); try checkAuthority(); signatures += 1
        let message = try challenge.message(expected: binding,
            publicKey: TeamDeviceEnrollmentWire.publicKey(signer.publicKey), request: request, now: 1_000)
        let signature = try signer.signature(for: message).rawRepresentation
        try checkAuthority(); try requireCurrent(expected); return signature
    }
    func invalidate() {
        guard let old = value else { return }
        value = .init(scope: old.scope, deviceID: old.deviceID, generation: UUID(), phase: old.phase,
            observedAt: old.observedAt, publicKey: old.publicKey,
            proofExpiresAt: old.proofExpiresAt, enrollmentID: old.enrollmentID)
    }
}
private final class EnrollmentAgreement: TeamAgreementIdentity, @unchecked Sendable {
    let scope: TeamAgreementScope
    private let lock = NSLock()
    private var value: TeamAgreementPublic
    private(set) var prepares = 0
    init(scope: TeamAgreementScope, publicKey: TeamDeviceEnrollmentWire.PublicKey) {
        self.scope = scope; value = .init(keyThumbprint: publicKey.thumbprint, publicKey: publicKey)
    }
    func prepare() -> TeamAgreementPublic { lock.withLock { prepares += 1; return value } }
    func current() -> TeamAgreementPublic { lock.withLock { value } }
}
private actor EnrollmentTransport: TeamAgreementEnrollmentTransport {
    enum Hook { case none, session, device }
    private let session: EnrollmentSession
    private let devices: EnrollmentDevices
    private let account: TeamAccountAccessTicket
    private let local: TeamDeviceSnapshot
    private let signingKey: TeamDeviceEnrollmentWire.PublicKey
    private var lookupHook = Hook.none, executeHook = Hook.none
    private var wrongResult = false
    private var gate: EnrollmentGate?
    private(set) var calls = [String]()
    init(session: EnrollmentSession, devices: EnrollmentDevices,
         account: TeamAccountAccessTicket, local: TeamDeviceSnapshot,
         signingKey: TeamDeviceEnrollmentWire.PublicKey) {
        self.session = session; self.devices = devices; self.account = account
        self.local = local; self.signingKey = signingKey
    }
    func configure(lookup: Hook = .none, execute: Hook = .none,
                   wrongResult: Bool = false, gate: EnrollmentGate? = nil) {
        lookupHook = lookup; executeHook = execute; self.wrongResult = wrongResult; self.gate = gate
    }
    private func apply(_ hook: Hook) async {
        if hook == .session { session.invalidate() }
        if hook == .device { await devices.invalidate() }
    }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey,
                      expected: TeamDeviceEnrollmentWire.Binding,
                      ticket: TeamAccountAccessTicket) async -> TeamRegisteredDevice? {
        calls.append("device"); await apply(lookupHook)
        return .init(enrollmentID: local.enrollmentID!, accountID: account.accountID,
            deviceID: local.deviceID, keyThumbprint: key.thumbprint,
            authorityEpoch: local.scope.authorityEpoch)
    }
    func currentTeam(teamID: String, enrollmentID: String,
                     ticket: TeamAccountAccessTicket) -> TeamMembership {
        calls.append("membership")
        return .init(teamID: teamID, accountID: account.accountID,
            enrollmentID: enrollmentID, role: .member, revision: 7)
    }
    func agreementRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                   publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                   request: TeamAgreementEnrollmentRequest,
                                   ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        calls.append("challenge")
        let object: [String: Any] = ["audience": expected.audience,
            "authorityEpoch": expected.authorityEpoch, "accountId": expected.accountID,
            "sessionId": expected.sessionID, "deviceId": expected.deviceID,
            "enrollmentId": expected.enrollmentID, "keyThumbprint": expected.keyThumbprint,
            "operation": expected.operation.rawValue, "teamId": expected.teamID,
            "requestId": expected.requestID,
            "bodySha256": try TeamDeviceRequestWire.bodySHA256(request.body),
            "challengeId": String(repeating: "A", count: 43),
            "nonce": String(repeating: "B", count: 42) + "A", "expiresAt": 9_000]
        return try .init(validating: JSONSerialization.data(withJSONObject: object),
            expected: expected, publicKey: publicKey, request: request, now: 1_000)
    }
    func executeAgreementRequest(challenge: TeamPreparedDeviceRequestChallenge,
                                 signature: Data, expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamAgreementEnrollmentRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamAgreementRegistration {
        calls.append("execute")
        let message = try challenge.message(expected: expected, publicKey: publicKey,
            request: request, now: 1_000)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        guard signingKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAgreementEnrollmentError.invalidResponse
        }
        if let gate { await gate.wait() }
        await apply(executeHook)
        return .init(teamID: wrongResult ? "other-team" : expected.teamID,
            membershipRevision: request.membershipRevision, enrollmentID: expected.enrollmentID,
            agreementKeyThumbprint: request.agreement.keyThumbprint,
            agreementPublicKey: request.agreement.publicKey)
    }
}

@Suite(.serialized)
struct TeamAgreementEnrollmentTests {
    private struct Fixture {
        let account: TeamAccountAccessTicket
        let session: EnrollmentSession
        let devices: EnrollmentDevices
        let agreement: EnrollmentAgreement
        let transport: EnrollmentTransport
        let owner: TeamAgreementEnrollment
        let signingKey: TeamDeviceEnrollmentWire.PublicKey
    }
    private func make(expiry: Int64 = 10_000, wall: Int64 = 1_000,
                      reuseSigningKey: Bool = false) throws -> Fixture {
        let scope = try TeamAccountSessionScope(origin: URL(string: "https://agreement.invalid")!,
            providerID: "public-ios")
        let pair = TeamAuthSessionPair(accountID: "account", sessionID: "session",
            accessToken: String(repeating: "C", count: 42) + "A",
            refreshToken: String(repeating: "D", count: 42) + "A",
            accessExpiresAt: expiry, sessionExpiresAt: 30_000)
        let account = try TeamAccountAccessTicket(snapshot:
            TeamAccountSessionCodec.active(pair: pair, scope: scope, now: 1_000))
        let signer = P256.Signing.PrivateKey()
        let signingKey = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let deviceScope = try TeamDeviceScope(audience: "https://agreement.invalid",
            accountID: "account", authorityEpoch: "epoch")
        let local = TeamDeviceSnapshot(scope: deviceScope, deviceID: "device",
            generation: UUID(), phase: .registered, observedAt: 1_000,
            publicKey: signingKey, proofExpiresAt: nil, enrollmentID: "enrollment")
        let sessions = EnrollmentSession(), devices = EnrollmentDevices(local, signer: signer)
        let agreementKey = reuseSigningKey ? signingKey
            : try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let agreementScope = try TeamAgreementScope(origin: deviceScope.audience,
            accountID: "account", authorityEpoch: "epoch", enrollmentID: "enrollment")
        let agreement = EnrollmentAgreement(scope: agreementScope, publicKey: agreementKey)
        let transport = EnrollmentTransport(session: sessions, devices: devices,
            account: account, local: local, signingKey: signingKey)
        let owner = try TeamAgreementEnrollment(account: account, authorityEpoch: "epoch",
            enrollmentID: "enrollment", sessions: sessions, devices: devices,
            agreement: agreement, transport: transport,
            clock: { .init(wallTime: wall, instant: .now) },
            requestID: { String(repeating: "E", count: 42) + "A" })
        return .init(account: account, session: sessions, devices: devices,
            agreement: agreement, transport: transport, owner: owner, signingKey: signingKey)
    }
    private func wait(_ gate: EnrollmentGate) async throws {
        for _ in 0..<200 {
            if await gate.hasEntered() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Enrollment operation did not enter gate")
    }

    @Test func exactCurrentProofRegistersDistinctAgreementIdentityOnce() async throws {
        let value = try make(), result = try await value.owner.enroll(teamID: "team")
        #expect(result.keyThumbprint != value.signingKey.thumbprint)
        #expect(await value.transport.calls == ["device", "membership", "challenge", "execute"])
        #expect(await value.devices.signatures == 1 && value.agreement.prepares == 1)
    }
    @Test func sessionOrDeviceLossAndSigningKeyReuseNeverReturnAuthority() async throws {
        let sessionLoss = try make(); await sessionLoss.transport.configure(lookup: .session)
        await #expect(throws: (any Error).self) { try await sessionLoss.owner.enroll(teamID: "team") }
        #expect(await sessionLoss.transport.calls == ["device"])
        let deviceLoss = try make(); await deviceLoss.transport.configure(execute: .device)
        await #expect(throws: (any Error).self) { try await deviceLoss.owner.enroll(teamID: "team") }
        let collision = try make(reuseSigningKey: true)
        await #expect(throws: TeamAgreementEnrollmentError.invalidResponse) {
            try await collision.owner.enroll(teamID: "team")
        }
        #expect(await collision.transport.calls == ["device", "membership"])
    }
    @Test func changedResultAndExpiredAccessFailClosed() async throws {
        let changed = try make(); await changed.transport.configure(wrongResult: true)
        await #expect(throws: TeamAgreementEnrollmentError.invalidResponse) {
            try await changed.owner.enroll(teamID: "team")
        }
        let expired = try make(expiry: 1_001, wall: 1_001)
        await #expect(throws: TeamAgreementEnrollmentError.expired) {
            try await expired.owner.enroll(teamID: "team")
        }
        #expect(await expired.transport.calls.isEmpty)
    }
    @Test func cancellationRetainsBusyUntilNoncooperativeExecuteSettles() async throws {
        let value = try make(), gate = EnrollmentGate()
        await value.transport.configure(gate: gate)
        let work = Task { try await value.owner.enroll(teamID: "team") }
        try await wait(gate); await value.owner.cancelPendingEnrollment()
        await #expect(throws: TeamAgreementEnrollmentError.busy) {
            try await value.owner.enroll(teamID: "team")
        }
        await gate.release()
        await #expect(throws: (any Error).self) { try await work.value }
        #expect(await value.transport.calls == ["device", "membership", "challenge", "execute"])
    }
}
