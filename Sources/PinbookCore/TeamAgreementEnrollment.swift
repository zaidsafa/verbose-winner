import Foundation
import Security

enum TeamAgreementEnrollmentError: Error, Equatable {
    case busy, invalidated, expired, deviceUnavailable, agreementUnavailable
    case transportFailure, invalidResponse
}

protocol TeamAgreementIdentity: Sendable {
    var scope: TeamAgreementScope { get }
    func prepare() throws -> TeamAgreementPublic
    func current() throws -> TeamAgreementPublic
    func derive(peer: TeamAgreementPublic, algorithm: String, partyU: Data,
                partyV: Data, bits: Int) throws -> Data
}
extension TeamAgreementKeyCustody: TeamAgreementIdentity {}

protocol TeamAgreementEnrollmentTransport: Sendable {
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                      ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice?
    func currentTeam(teamID: String, enrollmentID: String,
                     ticket: TeamAccountAccessTicket) async throws -> TeamMembership
    func agreementRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                   publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                   request: TeamAgreementEnrollmentRequest,
                                   ticket: TeamAccountAccessTicket) async throws -> TeamPreparedAgreementRequestChallenge
    func executeAgreementRequest(challenge: TeamPreparedAgreementRequestChallenge,
                                 signature: Data, confirmation: Data,
                                 expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamAgreementEnrollmentRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamAgreementRegistration
}
extension TeamAuthHTTPClient: TeamAgreementEnrollmentTransport {}

private func teamAgreementIdentityIO<T: Sendable>(
    _ action: @escaping @Sendable () throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached { try Task.checkCancellation(); return try action() }
    return try await withTaskCancellationHandler {
        let value = try await task.value; try Task.checkCancellation(); return value
    } onCancel: { task.cancel() }
}

/// One explicit foreground registration of one exact enrollment-scoped agreement
/// identity. No UI, retry, replacement, background work or runtime activation.
actor TeamAgreementEnrollment {
    private struct Pending {
        let id: UUID
        let task: Task<TeamAgreementPublic, Error>
        var invalidated = false
    }
    private let account: TeamAccountAccessTicket
    private let deviceScope: TeamDeviceScope
    private let enrollmentID: String
    private let sessions: any TeamAudienceSessionChecking
    private let devices: any TeamAudienceDevices
    private let agreement: any TeamAgreementIdentity
    private let transport: any TeamAgreementEnrollmentTransport
    private let clock: @Sendable () -> TeamSignInMoment
    private let requestID: @Sendable () throws -> String
    private var lastMoment: TeamSignInMoment?
    private var pending: Pending?

    init(account: TeamAccountAccessTicket, authorityEpoch: String, enrollmentID: String,
         sessions: any TeamAudienceSessionChecking, devices: any TeamAudienceDevices,
         agreement: any TeamAgreementIdentity, transport: any TeamAgreementEnrollmentTransport,
         clock: @escaping @Sendable () -> TeamSignInMoment = { .current() },
         requestID: @escaping @Sendable () throws -> String = TeamAgreementEnrollment.randomRequestID) throws {
        let raw = account.scope.origin.absoluteString
        let audience = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard TeamAuthWire.identifier(enrollmentID),
              agreement.scope == (try TeamAgreementScope(origin: audience, accountID: account.accountID,
                authorityEpoch: authorityEpoch, enrollmentID: enrollmentID)) else {
            throw TeamAgreementEnrollmentError.invalidResponse
        }
        deviceScope = try .init(audience: audience, accountID: account.accountID,
            authorityEpoch: authorityEpoch)
        self.account = account; self.enrollmentID = enrollmentID; self.sessions = sessions
        self.devices = devices; self.agreement = agreement; self.transport = transport
        self.clock = clock; self.requestID = requestID
    }

    func enroll(teamID: String) async throws -> TeamAgreementPublic {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamAgreementEnrollmentError.busy }
        guard TeamAuthWire.identifier(teamID) else { throw TeamAgreementEnrollmentError.invalidResponse }
        let start = try moment(), id = UUID()
        guard account.accessExpiresAt > start.wallTime else { throw TeamAgreementEnrollmentError.expired }
        let accessDeadline = start.instant.advanced(by: .milliseconds(account.accessExpiresAt - start.wallTime))
        let task = Task { try await self.perform(id: id, start: start,
            accessDeadline: accessDeadline, teamID: teamID) }
        pending = .init(id: id, task: task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func cancelPendingEnrollment() {
        guard var operation = pending else { return }
        operation.invalidated = true; pending = operation; operation.task.cancel()
    }

    private func perform(id: UUID, start: TeamSignInMoment,
                         accessDeadline: ContinuousClock.Instant,
                         teamID: String) async throws -> TeamAgreementPublic {
        _ = try localCheckpoint(id, start: start, accessDeadline: accessDeadline)
        guard let device = try await devices.load(scope: deviceScope), device.phase == .registered,
              device.enrollmentID == enrollmentID, let signingKey = device.publicKey else {
            throw TeamAgreementEnrollmentError.deviceUnavailable
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        let enrollmentBinding = TeamDeviceEnrollmentWire.Binding(audience: deviceScope.audience,
            authorityEpoch: deviceScope.authorityEpoch, accountID: account.accountID,
            sessionID: account.sessionID, deviceID: device.deviceID,
            keyThumbprint: signingKey.thumbprint, accessExpiresAt: account.accessExpiresAt)
        let remote: TeamRegisteredDevice?
        do { remote = try await transport.lookupDevice(key: signingKey,
            expected: enrollmentBinding, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAgreementEnrollmentError.transportFailure
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        guard let remote, remote.accountID == account.accountID,
              remote.deviceID == device.deviceID, remote.enrollmentID == enrollmentID,
              remote.authorityEpoch == deviceScope.authorityEpoch,
              remote.keyThumbprint == signingKey.thumbprint else {
            throw TeamAgreementEnrollmentError.deviceUnavailable
        }

        let membership: TeamMembership
        do { membership = try await transport.currentTeam(teamID: teamID,
            enrollmentID: enrollmentID, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAgreementEnrollmentError.transportFailure
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        guard membership.teamID == teamID, membership.accountID == account.accountID,
              membership.enrollmentID == enrollmentID, membership.revision >= 0 else {
            throw TeamAgreementEnrollmentError.invalidResponse
        }

        let publicIdentity: TeamAgreementPublic
        let identity = agreement
        do { publicIdentity = try await teamAgreementIdentityIO { try identity.prepare() } }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAgreementEnrollmentError.agreementUnavailable
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
            device: device, agreement: publicIdentity)
        guard publicIdentity.keyThumbprint != signingKey.thumbprint else {
            throw TeamAgreementEnrollmentError.invalidResponse
        }
        let request = try TeamAgreementEnrollmentRequest(membershipRevision: membership.revision,
            agreement: publicIdentity)
        let stableID = try requestID()
        guard TeamAuthWire.credential(stableID) else { throw TeamAgreementEnrollmentError.invalidResponse }
        let binding = TeamDeviceRequestWire.Binding(audience: deviceScope.audience,
            authorityEpoch: deviceScope.authorityEpoch, accountID: account.accountID,
            sessionID: account.sessionID, deviceID: device.deviceID,
            enrollmentID: enrollmentID, keyThumbprint: signingKey.thumbprint,
            operation: .agreementEnroll, teamID: teamID, requestID: stableID,
            accessExpiresAt: account.accessExpiresAt)

        let challenge: TeamPreparedAgreementRequestChallenge
        do { challenge = try await transport.agreementRequestChallenge(expected: binding,
            publicKey: signingKey, request: request, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
                device: device, agreement: publicIdentity)
            throw TeamAgreementEnrollmentError.transportFailure
        }
        let received = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
            device: device, agreement: publicIdentity)
        _ = try challenge.message(expected: binding, publicKey: signingKey,
            request: request, now: received.wallTime)
        let proofDeadline = received.instant.advanced(by:
            .milliseconds(challenge.expiresAt - received.wallTime))
        try checkProof(challenge.request, deadline: proofDeadline, now: received)
        let authority: @Sendable () throws -> Void = { [account, sessions, clock] in
            try Task.checkCancellation()
            let current = clock()
            guard current.wallTime >= received.wallTime, current.instant >= received.instant,
                  current.wallTime < account.accessExpiresAt, current.wallTime < challenge.expiresAt,
                  current.instant < accessDeadline, current.instant < proofDeadline else {
                throw TeamAgreementEnrollmentError.expired
            }
            try sessions.requireCurrentAccess(account, now: current.wallTime)
            try Task.checkCancellation()
        }
        var signature = try await devices.signRequest(device, challenge: challenge.request,
            binding: binding, request: request, checkAuthority: authority)
        defer { signature.resetBytes(in: signature.startIndex..<signature.endIndex) }
        var requestMessage: Data
        do { requestMessage = try challenge.message(expected: binding,
            publicKey: signingKey, request: request, now: received.wallTime) }
        catch { throw TeamAgreementEnrollmentError.invalidResponse }
        defer { requestMessage.resetBytes(in: requestMessage.startIndex..<requestMessage.endIndex) }
        var confirmationKey: Data
        do {
            let identity = agreement
            let server = challenge.server
            let challengeIDString = challenge.challengeID
            let agreementThumbprintString = publicIdentity.keyThumbprint
            confirmationKey = try await teamAgreementIdentityIO {
                var challengeID = Data(challengeIDString.utf8)
                var agreementThumbprint = Data(agreementThumbprintString.utf8)
                defer {
                    challengeID.resetBytes(in: challengeID.startIndex..<challengeID.endIndex)
                    agreementThumbprint.resetBytes(in: agreementThumbprint.startIndex..<agreementThumbprint.endIndex)
                }
                return try identity.derive(peer: server,
                    algorithm: TeamAgreementPossession.algorithm,
                    partyU: challengeID, partyV: agreementThumbprint, bits: 256)
            }
        } catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
                device: device, agreement: publicIdentity)
            throw TeamAgreementEnrollmentError.agreementUnavailable
        }
        defer { confirmationKey.resetBytes(in: confirmationKey.startIndex..<confirmationKey.endIndex) }
        var confirmation: Data
        do { confirmation = try TeamAgreementPossession.confirmation(key: confirmationKey,
            requestMessage: requestMessage, agreementKeyThumbprint: publicIdentity.keyThumbprint,
            serverKeyThumbprint: challenge.server.keyThumbprint) }
        catch { throw TeamAgreementEnrollmentError.invalidResponse }
        defer { confirmation.resetBytes(in: confirmation.startIndex..<confirmation.endIndex) }
        let beforeExecute = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
            device: device, agreement: publicIdentity)
        try checkProof(challenge.request, deadline: proofDeadline, now: beforeExecute)
        let result: TeamAgreementRegistration
        do { result = try await transport.executeAgreementRequest(challenge: challenge,
            signature: signature, confirmation: confirmation, expected: binding, publicKey: signingKey,
            request: request, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
                device: device, agreement: publicIdentity)
            throw TeamAgreementEnrollmentError.transportFailure
        }
        let finished = try await checkpoint(id, start: start, accessDeadline: accessDeadline,
            device: device, agreement: publicIdentity)
        try checkProof(challenge.request, deadline: proofDeadline, now: finished)
        guard result.teamID == membership.teamID,
              result.membershipRevision == membership.revision,
              result.enrollmentID == enrollmentID,
              result.agreementKeyThumbprint == publicIdentity.keyThumbprint,
              result.agreementPublicKey.thumbprint == publicIdentity.keyThumbprint,
              result.agreementPublicKey.jwk == publicIdentity.publicKey.jwk else {
            throw TeamAgreementEnrollmentError.invalidResponse
        }
        return publicIdentity
    }

    private func checkpoint(_ id: UUID, start: TeamSignInMoment,
                            accessDeadline: ContinuousClock.Instant,
                            device: TeamDeviceSnapshot? = nil,
                            agreement expectedAgreement: TeamAgreementPublic? = nil) async throws -> TeamSignInMoment {
        let before = try localCheckpoint(id, start: start, accessDeadline: accessDeadline)
        if let device { try await devices.requireCurrent(device) }
        if let expectedAgreement {
            let current: TeamAgreementPublic
            let identity = agreement
            do { current = try await teamAgreementIdentityIO { try identity.current() } }
            catch { throw TeamAgreementEnrollmentError.agreementUnavailable }
            guard current.keyThumbprint == expectedAgreement.keyThumbprint,
                  current.publicKey.jwk == expectedAgreement.publicKey.jwk else {
                throw TeamAgreementEnrollmentError.agreementUnavailable
            }
        }
        return (device != nil || expectedAgreement != nil)
            ? try localCheckpoint(id, start: start, accessDeadline: accessDeadline) : before
    }

    private func localCheckpoint(_ id: UUID, start: TeamSignInMoment,
                                 accessDeadline: ContinuousClock.Instant) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard pending?.id == id, pending?.invalidated == false else {
            throw TeamAgreementEnrollmentError.invalidated
        }
        let value = try moment()
        guard value.wallTime - start.wallTime < 125_000,
              start.instant.duration(to: value.instant) < .seconds(125),
              value.wallTime < account.accessExpiresAt, value.instant < accessDeadline else {
            throw TeamAgreementEnrollmentError.expired
        }
        try sessions.requireCurrentAccess(account, now: value.wallTime)
        try Task.checkCancellation()
        return value
    }

    private func checkProof(_ proof: TeamPreparedDeviceRequestChallenge,
                            deadline: ContinuousClock.Instant, now: TeamSignInMoment) throws {
        guard now.wallTime < proof.expiresAt, now.instant < deadline else {
            throw TeamAgreementEnrollmentError.expired
        }
    }
    private func moment() throws -> TeamSignInMoment {
        let value = clock()
        try TeamAccountSessionCodec.checkClock(value.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ value.instant >= $0.instant }) ?? true else {
            throw TeamAgreementEnrollmentError.expired
        }
        lastMoment = value; return value
    }
    nonisolated private static func randomRequestID() throws -> String {
        var bytes = Data(repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw TeamAgreementEnrollmentError.invalidResponse }
        return TeamDeviceEnrollmentWire.encode(bytes)
    }
}
