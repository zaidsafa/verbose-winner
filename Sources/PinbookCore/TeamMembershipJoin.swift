import Foundation

enum TeamMembershipJoinError: Error, Equatable {
    case busy, invalidated, invalidIntent, consentRequired, staleConsent, expired
    case registrationUnavailable, transportFailure, recoveryRequired, missingRecord
}
struct TeamMembershipJoinPreview: TeamOnboardingDiagnostic {
    fileprivate let id: UUID
    let accountID: String
    let teamID: String
    let role: TeamInvitationRole
}
protocol TeamMembershipTransport: Sendable {
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice?
    func acceptInvitation(token: String, teamID: String, enrollmentID: String, role: TeamInvitationRole, ticket: TeamAccountAccessTicket) async throws -> TeamMembership
    func currentTeam(teamID: String, enrollmentID: String, ticket: TeamAccountAccessTicket) async throws -> TeamMembership
}
extension TeamAuthHTTPClient: TeamMembershipTransport {}
protocol TeamMembershipDevices: Sendable {
    func load(scope: TeamDeviceScope) async throws -> TeamDeviceSnapshot?
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws
}
protocol TeamMembershipMetadata: Sendable {
    func load(scope: TeamDeviceScope, teamID: String) async throws -> TeamJoinSnapshot?
    func requireCurrent(_ expected: TeamJoinSnapshot) async throws
    func begin(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole,
               expiresAt: Int64, registration: TeamRegisteredDevice, consent: Bool) async throws -> TeamJoinSnapshot
    func beginRecovery(_ expected: TeamJoinSnapshot) async throws -> TeamJoinSnapshot
    func confirm(_ expected: TeamJoinSnapshot, result: TeamMembership) async throws -> TeamJoinSnapshot
}
private func membershipIO<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached { try Task.checkCancellation(); return try action() }
    return try await withTaskCancellationHandler {
        let result = try await task.value; try Task.checkCancellation(); return result
    } onCancel: { task.cancel() }
}
/// Await actual native completion off the UI/owner executor, even after cancellation.
struct TeamMembershipDeviceDriver: TeamMembershipDevices {
    let custody: TeamDeviceCustody
    func load(scope: TeamDeviceScope) async throws -> TeamDeviceSnapshot? {
        try await membershipIO { try custody.load(scope: scope) }
    }
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws {
        try await membershipIO { try custody.requireCurrent(expected) }
    }
}
struct TeamMembershipMetadataDriver: TeamMembershipMetadata {
    let store: TeamJoinStore
    func load(scope: TeamDeviceScope, teamID: String) async throws -> TeamJoinSnapshot? {
        try await membershipIO { try store.load(scope: scope, teamID: teamID) }
    }
    func requireCurrent(_ expected: TeamJoinSnapshot) async throws {
        try await membershipIO { try store.requireCurrent(expected) }
    }
    func begin(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole,
               expiresAt: Int64, registration: TeamRegisteredDevice, consent: Bool) async throws -> TeamJoinSnapshot {
        try await membershipIO { try store.begin(scope: scope, token: token, teamID: teamID, role: role,
            expiresAt: expiresAt, registration: registration, consent: consent) }
    }
    func beginRecovery(_ expected: TeamJoinSnapshot) async throws -> TeamJoinSnapshot {
        try await membershipIO { try store.beginRecovery(expected) }
    }
    func confirm(_ expected: TeamJoinSnapshot, result: TeamMembership) async throws -> TeamJoinSnapshot {
        try await membershipIO { try store.confirm(expected, result: result) }
    }
}

/// One retained owner for ONE exact account generation. Refresh/sign-out/re-login
/// requires a new owner and fresh UI consent. Inactive; never automatically registers
/// a key, signs in, refreshes, retries accept, deletes metadata or shares notes.
actor TeamMembershipJoin {
    private struct Resources {
        let device: TeamDeviceSnapshot
        let binding: TeamDeviceEnrollmentWire.Binding
    }
    private struct Prepared {
        let display: TeamMembershipJoinPreview
        let intent: TeamInviteJoinIntent
        let resources: Resources
        let received: TeamSignInMoment
        let deadline: ContinuousClock.Instant
    }
    private struct Pending {
        let id: UUID
        let cancel: @Sendable () -> Void
        let settle: @Sendable () async -> Void
        var invalidated = false
    }
    private let account: TeamAccountAccessTicket
    private let deviceScope: TeamDeviceScope
    private let sessions: TeamAccountSessionStore
    private let devices: any TeamMembershipDevices
    private let metadata: any TeamMembershipMetadata
    private let transport: any TeamMembershipTransport
    private let clock: @Sendable () -> TeamSignInMoment
    private var lastMoment: TeamSignInMoment?
    private var accessDeadline: ContinuousClock.Instant?
    private var prepared: Prepared?
    private var pending: Pending?
    private var closed = false

    init(account: TeamAccountAccessTicket, authorityEpoch: String, sessions: TeamAccountSessionStore,
         devices: any TeamMembershipDevices, metadata: any TeamMembershipMetadata,
         transport: any TeamMembershipTransport,
         clock: @escaping @Sendable () -> TeamSignInMoment = { .current() }) throws {
        let raw = account.scope.origin.absoluteString
        deviceScope = try .init(audience: raw.hasSuffix("/") ? String(raw.dropLast()) : raw,
            accountID: account.accountID, authorityEpoch: authorityEpoch)
        self.account = account; self.sessions = sessions; self.devices = devices
        self.metadata = metadata; self.transport = transport; self.clock = clock
    }
    func prepare(_ intent: TeamInviteJoinIntent) async throws -> TeamMembershipJoinPreview {
        try available(); prepared = nil
        return try await run { id, start in try await self.performPrepare(intent, id: id, start: start) }
    }
    func join(_ display: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot {
        try available()
        guard consent else { throw TeamMembershipJoinError.consentRequired }
        guard let value = prepared, value.display.id == display.id else { throw TeamMembershipJoinError.staleConsent }
        prepared = nil // Consumed before any attempt; no automatic rearming.
        return try await run { id, start in try await self.performJoin(value, id: id, start: start) }
    }
    func recover(teamID: String) async throws -> TeamJoinSnapshot {
        try available(); prepared = nil
        guard TeamAuthWire.identifier(teamID) else { throw TeamMembershipJoinError.invalidIntent }
        return try await run { id, start in try await self.performRecovery(teamID, id: id, start: start) }
    }
    func cancelPendingMembership() {
        prepared = nil
        guard var value = pending else { return }
        value.invalidated = true; pending = value; value.cancel()
    }
    /// Permanent teardown waits for actual child/native/network completion.
    func close() async {
        closed = true; cancelPendingMembership()
        if let value = pending { await value.settle() }
    }
    private func available() throws {
        try Task.checkCancellation()
        guard !closed else { throw TeamMembershipJoinError.invalidated }
        guard pending == nil else { throw TeamMembershipJoinError.busy }
    }
    private func run<T: Sendable>(_ action: @escaping @Sendable (UUID, TeamSignInMoment) async throws -> T) async throws -> T {
        try available()
        let id = UUID(), start = try moment()
        let task = Task { try await action(id, start) }
        pending = .init(id: id, cancel: { task.cancel() }, settle: { _ = await task.result })
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            // Parent handoff can resume after a close/account change. Refuse that
            // stale success; a committed membership record is NOT rolled back.
            _ = try checkpoint(id, start)
            return result
        } onCancel: { task.cancel() }
    }
    private func performPrepare(_ intent: TeamInviteJoinIntent, id: UUID, start: TeamSignInMoment) async throws -> TeamMembershipJoinPreview {
        let now = try checkpoint(id, start)
        guard intent.account == account, TeamAuthWire.credential(intent.token), TeamAuthWire.identifier(intent.teamID),
              intent.expiresAt > now.wallTime, intent.expiresAt <= TeamAuthWire.maximumSafeTime,
              intent.expiresAt - now.wallTime <= 604_805_000 else { throw TeamMembershipJoinError.invalidIntent }
        let resources = try await resources(id, start)
        _ = try await lookup(resources, id, start)
        let saved = try await metadata.load(scope: deviceScope, teamID: intent.teamID)
        let finished = try await checkpoint(id, start, resources)
        guard saved == nil else { throw TeamMembershipJoinError.recoveryRequired }
        let expiry = min(intent.expiresAt, account.accessExpiresAt, account.sessionExpiresAt)
        guard finished.wallTime < expiry else { throw TeamMembershipJoinError.expired }
        let display = TeamMembershipJoinPreview(id: UUID(), accountID: account.accountID, teamID: intent.teamID, role: intent.role)
        prepared = .init(display: display, intent: intent, resources: resources, received: finished,
            deadline: finished.instant.advanced(by: .milliseconds(min(300_000, expiry - finished.wallTime))))
        return display
    }
    private func performJoin(_ value: Prepared, id: UUID, start: TeamSignInMoment) async throws -> TeamJoinSnapshot {
        try validate(value, now: checkpoint(id, start))
        let registration = try await lookup(value.resources, id, start)
        try validate(value, now: checkpoint(id, start))
        let marker = try await metadata.begin(scope: deviceScope, token: value.intent.token, teamID: value.intent.teamID,
            role: value.intent.role, expiresAt: value.intent.expiresAt, registration: registration, consent: true)
        try validate(value, now: await checkpoint(id, start, value.resources))
        try bound(marker, teamID: value.intent.teamID, resources: value.resources)
        guard marker.phase == .pending, marker.role == value.intent.role,
              marker.invitationHash == TeamJoinStore.invitationHash(value.intent.token) else { throw TeamJoinError.bindingMismatch }
        try await metadata.requireCurrent(marker)
        try validate(value, now: await checkpoint(id, start, value.resources))
        let response: TeamMembership
        do {
            response = try await transport.acceptInvitation(token: value.intent.token, teamID: marker.teamID,
                enrollmentID: marker.enrollmentID, role: marker.role, ticket: account)
        } catch { _ = try await checkpoint(id, start, value.resources); throw TeamMembershipJoinError.transportFailure }
        try validate(value, now: await checkpoint(id, start, value.resources))
        let result = try await metadata.confirm(marker, result: response)
        try bound(result, teamID: marker.teamID, resources: value.resources)
        guard result.phase == .confirmed, result.role == marker.role else { throw TeamJoinError.bindingMismatch }
        try await metadata.requireCurrent(result)
        try validate(value, now: await checkpoint(id, start, value.resources))
        return result
    }
    private func performRecovery(_ teamID: String, id: UUID, start: TeamSignInMoment) async throws -> TeamJoinSnapshot {
        _ = try checkpoint(id, start)
        let resources = try await resources(id, start)
        let loaded = try await metadata.load(scope: deviceScope, teamID: teamID)
        _ = try await checkpoint(id, start, resources)
        guard let saved = loaded else { throw TeamMembershipJoinError.missingRecord }
        try bound(saved, teamID: teamID, resources: resources)
        _ = try await lookup(resources, id, start)
        let marker = try await metadata.beginRecovery(saved)
        _ = try await checkpoint(id, start, resources)
        try bound(marker, teamID: teamID, resources: resources)
        guard marker.generation != saved.generation, marker.role == saved.role,
              marker.invitationHash == saved.invitationHash else { throw TeamJoinError.bindingMismatch }
        try await metadata.requireCurrent(marker)
        _ = try await checkpoint(id, start, resources)
        let response: TeamMembership
        do { response = try await transport.currentTeam(teamID: marker.teamID, enrollmentID: marker.enrollmentID, ticket: account) }
        catch { _ = try await checkpoint(id, start, resources); throw TeamMembershipJoinError.transportFailure }
        _ = try await checkpoint(id, start, resources)
        let result = try await metadata.confirm(marker, result: response)
        try bound(result, teamID: teamID, resources: resources)
        guard result.phase == .confirmed, result.role == marker.role else { throw TeamJoinError.bindingMismatch }
        try await metadata.requireCurrent(result)
        _ = try await checkpoint(id, start, resources)
        return result
    }
    private func resources(_ id: UUID, _ start: TeamSignInMoment) async throws -> Resources {
        _ = try checkpoint(id, start)
        let device = try await devices.load(scope: deviceScope)
        let now = try checkpoint(id, start)
        guard let device, device.scope == deviceScope, device.phase == .registered,
              let key = device.publicKey, let enrollment = device.enrollmentID,
              TeamAuthWire.identifier(device.deviceID), TeamAuthWire.identifier(enrollment),
              device.proofExpiresAt == nil, now.wallTime >= device.observedAt else { throw TeamMembershipJoinError.registrationUnavailable }
        let result = Resources(device: device, binding: .init(audience: deviceScope.audience, authorityEpoch: deviceScope.authorityEpoch,
            accountID: account.accountID, sessionID: account.sessionID, deviceID: device.deviceID,
            keyThumbprint: key.thumbprint, accessExpiresAt: account.accessExpiresAt))
        _ = try await checkpoint(id, start, result); return result
    }
    private func lookup(_ resources: Resources, _ id: UUID, _ start: TeamSignInMoment) async throws -> TeamRegisteredDevice {
        _ = try await checkpoint(id, start, resources)
        guard let key = resources.device.publicKey else { throw TeamMembershipJoinError.registrationUnavailable }
        let reply: TeamRegisteredDevice?
        do { reply = try await transport.lookupDevice(key: key, expected: resources.binding, ticket: account) }
        catch { _ = try await checkpoint(id, start, resources); throw TeamMembershipJoinError.transportFailure }
        _ = try await checkpoint(id, start, resources)
        guard let reply, reply.accountID == account.accountID, reply.authorityEpoch == deviceScope.authorityEpoch,
              reply.deviceID == resources.device.deviceID, reply.keyThumbprint == key.thumbprint,
              reply.enrollmentID == resources.device.enrollmentID else { throw TeamMembershipJoinError.registrationUnavailable }
        return reply
    }
    private func bound(_ value: TeamJoinSnapshot, teamID: String, resources: Resources) throws {
        guard value.scope == deviceScope, value.teamID == teamID, value.enrollmentID == resources.device.enrollmentID else { throw TeamJoinError.bindingMismatch }
    }
    private func validate(_ value: Prepared, now: TeamSignInMoment) throws {
        guard now.wallTime >= value.received.wallTime, now.wallTime < value.intent.expiresAt,
              now.wallTime - value.received.wallTime < 300_000, now.instant < value.deadline else { throw TeamMembershipJoinError.expired }
    }
    private func checkpoint(_ id: UUID, _ start: TeamSignInMoment, _ resources: Resources) async throws -> TeamSignInMoment {
        _ = try checkpoint(id, start)
        try await devices.requireCurrent(resources.device)
        return try checkpoint(id, start) // Account/time AFTER slow device reads.
    }
    private func checkpoint(_ id: UUID, _ start: TeamSignInMoment) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard !closed, pending?.id == id, pending?.invalidated == false else { throw TeamMembershipJoinError.invalidated }
        let before = try moment()
        if accessDeadline == nil {
            _ = try account.usableToken(now: before.wallTime)
            // Anchor BEFORE the first potentially slow account-store read. A
            // stalled wall clock must not add that read's duration to access life.
            accessDeadline = before.instant.advanced(by: .milliseconds(min(account.accessExpiresAt, account.sessionExpiresAt) - before.wallTime))
        }
        try sessions.requireCurrentAccess(account, now: before.wallTime)
        let after = try moment(); try Task.checkCancellation()
        _ = try account.usableToken(now: after.wallTime)
        guard after.wallTime - start.wallTime < 125_000, start.instant.duration(to: after.instant) < .seconds(125),
              let accessDeadline, after.instant < accessDeadline else { throw TeamMembershipJoinError.expired }
        return after
    }
    private func moment() throws -> TeamSignInMoment {
        let now = clock()
        try TeamAccountSessionCodec.checkClock(now.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ now.instant >= $0.instant }) ?? true else { throw TeamMembershipJoinError.expired }
        lastMoment = now; return now
    }
}
