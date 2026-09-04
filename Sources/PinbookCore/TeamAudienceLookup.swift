import Foundation
import Security

enum TeamAudienceLookupError: Error, Equatable {
    case busy, invalidated, expired, deviceUnavailable, transportFailure, invalidResponse
}

protocol TeamAudienceSessionChecking: Sendable {
    func requireCurrentAccess(_ ticket: TeamAccountAccessTicket, now: Int64) throws
}
extension TeamAccountSessionStore: TeamAudienceSessionChecking {}

protocol TeamAudienceDevices: Sendable {
    func load(scope: TeamDeviceScope) async throws -> TeamDeviceSnapshot?
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws
    func signRequest(_ expected: TeamDeviceSnapshot, challenge: TeamPreparedDeviceRequestChallenge,
                     binding: TeamDeviceRequestWire.Binding, request: TeamAudienceRevisionRequest,
                     checkAuthority: @escaping @Sendable () throws -> Void) async throws -> Data
}

private func teamAudienceIO<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached { try Task.checkCancellation(); return try action() }
    return try await withTaskCancellationHandler {
        let value = try await task.value; try Task.checkCancellation(); return value
    } onCancel: { task.cancel() }
}

struct TeamAudienceDeviceDriver: TeamAudienceDevices {
    let custody: TeamDeviceCustody
    func load(scope: TeamDeviceScope) async throws -> TeamDeviceSnapshot? {
        try await teamAudienceIO { try custody.load(scope: scope) }
    }
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws {
        try await teamAudienceIO { try custody.requireCurrent(expected) }
    }
    func signRequest(_ expected: TeamDeviceSnapshot, challenge: TeamPreparedDeviceRequestChallenge,
                     binding: TeamDeviceRequestWire.Binding, request: TeamAudienceRevisionRequest,
                     checkAuthority: @escaping @Sendable () throws -> Void) async throws -> Data {
        try await teamAudienceIO {
            try custody.signRequest(expected, challenge: challenge, binding: binding,
                request: request, checkAuthority: checkAuthority)
        }
    }
}

protocol TeamAudienceTransport: Sendable {
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                      ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice?
    func currentTeam(teamID: String, enrollmentID: String,
                     ticket: TeamAccountAccessTicket) async throws -> TeamMembership
    func deviceRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                request: TeamAudienceRevisionRequest,
                                ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge
    func executeDeviceRequest(challenge: TeamPreparedDeviceRequestChallenge,
                              signature: Data, expected: TeamDeviceRequestWire.Binding,
                              publicKey: TeamDeviceEnrollmentWire.PublicKey,
                              request: TeamAudienceRevisionRequest,
                              ticket: TeamAccountAccessTicket) async throws -> TeamAudience
}
extension TeamAuthHTTPClient: TeamAudienceTransport {}

/// One explicit foreground lookup for one exact reviewed account generation.
/// No retry, cache, timer, background poll, note delivery or retained authority.
actor TeamAudienceLookup {
    private struct Pending {
        let id: UUID
        let task: Task<TeamAudience, Error>
        var invalidated = false
    }
    private let account: TeamAccountAccessTicket
    private let deviceScope: TeamDeviceScope
    private let sessions: any TeamAudienceSessionChecking
    private let devices: any TeamAudienceDevices
    private let transport: any TeamAudienceTransport
    private let clock: @Sendable () -> TeamSignInMoment
    private let requestID: @Sendable () throws -> String
    private var lastMoment: TeamSignInMoment?
    private var pending: Pending?

    init(account: TeamAccountAccessTicket, authorityEpoch: String,
         sessions: any TeamAudienceSessionChecking, devices: any TeamAudienceDevices,
         transport: any TeamAudienceTransport,
         clock: @escaping @Sendable () -> TeamSignInMoment = { .current() },
         requestID: @escaping @Sendable () throws -> String = TeamAudienceLookup.randomRequestID) throws {
        let raw = account.scope.origin.absoluteString
        deviceScope = try .init(audience: raw.hasSuffix("/") ? String(raw.dropLast()) : raw,
            accountID: account.accountID, authorityEpoch: authorityEpoch)
        self.account = account; self.sessions = sessions; self.devices = devices
        self.transport = transport; self.clock = clock; self.requestID = requestID
    }

    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamAudienceLookupError.busy }
        guard TeamAuthWire.identifier(teamID), TeamAuthWire.identifier(enrollmentID) else {
            throw TeamAudienceLookupError.invalidResponse
        }
        let start = try moment(), id = UUID()
        guard account.accessExpiresAt > start.wallTime else { throw TeamAudienceLookupError.expired }
        let accessDeadline = start.instant.advanced(by: .milliseconds(account.accessExpiresAt - start.wallTime))
        let task = Task { try await self.perform(id: id, start: start, accessDeadline: accessDeadline,
            teamID: teamID, enrollmentID: enrollmentID) }
        pending = .init(id: id, task: task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func cancelPendingLookup() {
        guard var operation = pending else { return }
        operation.invalidated = true; pending = operation; operation.task.cancel()
    }

    private func perform(id: UUID, start: TeamSignInMoment, accessDeadline: ContinuousClock.Instant,
                         teamID: String, enrollmentID: String) async throws -> TeamAudience {
        _ = try checkpoint(id, start: start, accessDeadline: accessDeadline)
        guard let device = try await devices.load(scope: deviceScope), device.phase == .registered,
              device.enrollmentID == enrollmentID, let key = device.publicKey else {
            throw TeamAudienceLookupError.deviceUnavailable
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        let enrollmentBinding = TeamDeviceEnrollmentWire.Binding(audience: deviceScope.audience,
            authorityEpoch: deviceScope.authorityEpoch, accountID: account.accountID,
            sessionID: account.sessionID, deviceID: device.deviceID,
            keyThumbprint: key.thumbprint, accessExpiresAt: account.accessExpiresAt)
        let remote: TeamRegisteredDevice?
        do { remote = try await transport.lookupDevice(key: key, expected: enrollmentBinding, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAudienceLookupError.transportFailure
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        guard let remote, remote.accountID == account.accountID, remote.deviceID == device.deviceID,
              remote.enrollmentID == enrollmentID, remote.authorityEpoch == deviceScope.authorityEpoch,
              remote.keyThumbprint == key.thumbprint else { throw TeamAudienceLookupError.deviceUnavailable }

        let membership: TeamMembership
        do { membership = try await transport.currentTeam(teamID: teamID, enrollmentID: enrollmentID, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAudienceLookupError.transportFailure
        }
        _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        guard membership.teamID == teamID, membership.accountID == account.accountID,
              membership.enrollmentID == enrollmentID, membership.revision >= 0 else {
            throw TeamAudienceLookupError.invalidResponse
        }
        let request = try TeamAudienceRevisionRequest(membershipRevision: membership.revision)
        let stableID = try requestID()
        guard TeamAuthWire.credential(stableID) else { throw TeamAudienceLookupError.invalidResponse }
        let binding = TeamDeviceRequestWire.Binding(audience: deviceScope.audience,
            authorityEpoch: deviceScope.authorityEpoch, accountID: account.accountID,
            sessionID: account.sessionID, deviceID: device.deviceID,
            enrollmentID: enrollmentID, keyThumbprint: key.thumbprint, operation: .teamAudience,
            teamID: teamID, requestID: stableID, accessExpiresAt: account.accessExpiresAt)
        let challenge: TeamPreparedDeviceRequestChallenge
        do { challenge = try await transport.deviceRequestChallenge(expected: binding,
            publicKey: key, request: request, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAudienceLookupError.transportFailure
        }
        let received = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        _ = try challenge.message(expected: binding, publicKey: key, request: request, now: received.wallTime)
        let proofDeadline = received.instant.advanced(by: .milliseconds(challenge.expiresAt - received.wallTime))
        try checkProof(challenge, deadline: proofDeadline, now: received)
        let authority: @Sendable () throws -> Void = { [account, sessions, clock] in
            try Task.checkCancellation()
            let current = clock()
            guard current.wallTime >= received.wallTime, current.instant >= received.instant,
                  current.wallTime < account.accessExpiresAt, current.wallTime < challenge.expiresAt,
                  current.instant < accessDeadline, current.instant < proofDeadline else {
                throw TeamAudienceLookupError.expired
            }
            try sessions.requireCurrentAccess(account, now: current.wallTime)
            try Task.checkCancellation()
        }
        var signature = try await devices.signRequest(device, challenge: challenge,
            binding: binding, request: request, checkAuthority: authority)
        defer { signature.resetBytes(in: signature.startIndex..<signature.endIndex) }
        let beforeExecute = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        try checkProof(challenge, deadline: proofDeadline, now: beforeExecute)
        let result: TeamAudience
        do { result = try await transport.executeDeviceRequest(challenge: challenge, signature: signature,
            expected: binding, publicKey: key, request: request, ticket: account) }
        catch {
            _ = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
            throw TeamAudienceLookupError.transportFailure
        }
        let finished = try await checkpoint(id, start: start, accessDeadline: accessDeadline, device: device)
        try checkProof(challenge, deadline: proofDeadline, now: finished)
        try validate(result, membership: membership)
        return result
    }

    private func validate(_ audience: TeamAudience, membership: TeamMembership) throws {
        guard audience.teamID == membership.teamID,
              audience.membershipRevision == membership.revision, audience.targets.count <= 9 else {
            throw TeamAudienceLookupError.invalidResponse
        }
        var accounts = Set<String>(), devices = Set<String>(), enrollments = Set<String>()
        for target in audience.targets {
            guard TeamAuthWire.identifier(target.accountID), TeamAuthWire.identifier(target.deviceID),
                  TeamAuthWire.identifier(target.enrollmentID), target.accountID != account.accountID,
                  TeamAuthWire.credential(target.keyThumbprint),
                  target.publicKey.thumbprint == target.keyThumbprint,
                  accounts.insert(target.accountID).inserted,
                  devices.insert(target.deviceID).inserted,
                  enrollments.insert(target.enrollmentID).inserted else {
                throw TeamAudienceLookupError.invalidResponse
            }
        }
    }

    private func checkpoint(_ id: UUID, start: TeamSignInMoment,
                            accessDeadline: ContinuousClock.Instant,
                            device: TeamDeviceSnapshot?) async throws -> TeamSignInMoment {
        let before = try checkpoint(id, start: start, accessDeadline: accessDeadline)
        if let device {
            try await devices.requireCurrent(device)
            return try checkpoint(id, start: start, accessDeadline: accessDeadline)
        }
        return before
    }
    private func checkpoint(_ id: UUID, start: TeamSignInMoment,
                            accessDeadline: ContinuousClock.Instant) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard pending?.id == id, pending?.invalidated == false else {
            throw TeamAudienceLookupError.invalidated
        }
        let value = try moment()
        guard value.wallTime - start.wallTime < 125_000,
              start.instant.duration(to: value.instant) < .seconds(125),
              value.wallTime < account.accessExpiresAt, value.instant < accessDeadline else {
            throw TeamAudienceLookupError.expired
        }
        try sessions.requireCurrentAccess(account, now: value.wallTime)
        try Task.checkCancellation()
        return value
    }
    private func checkProof(_ proof: TeamPreparedDeviceRequestChallenge,
                            deadline: ContinuousClock.Instant, now: TeamSignInMoment) throws {
        guard now.wallTime < proof.expiresAt, now.instant < deadline else {
            throw TeamAudienceLookupError.expired
        }
    }
    private func moment() throws -> TeamSignInMoment {
        let value = clock()
        try TeamAccountSessionCodec.checkClock(value.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ value.instant >= $0.instant }) ?? true else {
            throw TeamAudienceLookupError.expired
        }
        lastMoment = value; return value
    }
    nonisolated private static func randomRequestID() throws -> String {
        var bytes = Data(repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, 32, pointer.baseAddress!)
        }
        guard status == errSecSuccess else { throw TeamAudienceLookupError.invalidResponse }
        return TeamDeviceEnrollmentWire.encode(bytes)
    }
}
