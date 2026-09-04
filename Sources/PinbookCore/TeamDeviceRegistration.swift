import Foundation

enum TeamDeviceRegistrationError: Error, Equatable { case busy, invalidated, expired, transportFailure, registrationUnavailable }
enum TeamDeviceRegistrationResult: TeamOnboardingDiagnostic {
    case registered(TeamDeviceSnapshot)
    case recoveryWait(until: Int64)
    case retryReady(TeamDeviceSnapshot)
}
protocol TeamDeviceRegistering: Sendable {
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice?
    func deviceChallenge(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceChallenge
    func completeDevice(challenge: TeamPreparedDeviceChallenge, signature: Data, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice
}
extension TeamAuthHTTPClient: TeamDeviceRegistering {}

protocol TeamRegistrationCustody: Sendable {
    func prepare(scope: TeamDeviceScope, consent: Bool) async throws -> TeamDeviceSnapshot
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws
    func signForSubmission(_ expected: TeamDeviceSnapshot, challenge: TeamPreparedDeviceChallenge, binding: TeamDeviceEnrollmentWire.Binding) async throws -> TeamDeviceSubmission
    func beginRecovery(_ expected: TeamDeviceSnapshot) async throws -> TeamDeviceSnapshot
    func recordRegistration(_ expected: TeamDeviceSnapshot, registration: TeamRegisteredDevice) async throws -> TeamDeviceSnapshot
    func recordRecoveryAbsence(_ expected: TeamDeviceSnapshot) async throws -> TeamDeviceSnapshot
}
private func deviceCustodyIO<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
    try Task.checkCancellation()
    let task = Task.detached { try Task.checkCancellation(); return try action() }
    return try await withTaskCancellationHandler {
        let result = try await task.value
        try Task.checkCancellation()
        return result
    } onCancel: { task.cancel() }
}
/// Protected storage/key use stays off the registration actor and UI executor.
/// A canceled caller still waits for native work to settle; a write may have committed.
struct TeamRegistrationCustodyDriver: TeamRegistrationCustody {
    let custody: TeamDeviceCustody
    func prepare(scope: TeamDeviceScope, consent: Bool) async throws -> TeamDeviceSnapshot {
        try await deviceCustodyIO { try custody.prepare(scope: scope, consent: consent) }
    }
    func requireCurrent(_ expected: TeamDeviceSnapshot) async throws {
        try await deviceCustodyIO { try custody.requireCurrent(expected) }
    }
    func signForSubmission(_ expected: TeamDeviceSnapshot, challenge: TeamPreparedDeviceChallenge, binding: TeamDeviceEnrollmentWire.Binding) async throws -> TeamDeviceSubmission {
        try await deviceCustodyIO { try custody.signForSubmission(expected, challenge: challenge, binding: binding) }
    }
    func beginRecovery(_ expected: TeamDeviceSnapshot) async throws -> TeamDeviceSnapshot {
        try await deviceCustodyIO { try custody.beginRecovery(expected) }
    }
    func recordRegistration(_ expected: TeamDeviceSnapshot, registration: TeamRegisteredDevice) async throws -> TeamDeviceSnapshot {
        try await deviceCustodyIO { try custody.recordRegistration(expected, registration: registration) }
    }
    func recordRecoveryAbsence(_ expected: TeamDeviceSnapshot) async throws -> TeamDeviceSnapshot {
        try await deviceCustodyIO { try custody.recordRecoveryAbsence(expected) }
    }
}

/// Retained for ONE exact reviewed account generation. A new account/session
/// requires a new owner and new UI consent. Use the SAME retained HTTP client as
/// ordinary auth. No automatic sign-in, refresh, team join, key rotation or retry.
actor TeamDeviceRegistration {
    private struct Pending {
        let id: UUID
        let task: Task<TeamDeviceRegistrationResult, Error>
        var invalidated = false
    }
    private let account: TeamAccountAccessTicket
    private let scope: TeamAccountSessionScope
    private let audience: String
    private let authorityEpoch: String
    private let sessions: TeamAccountSessionStore
    private let devices: any TeamRegistrationCustody
    private let transport: any TeamDeviceRegistering
    private let clock: @Sendable () -> TeamSignInMoment
    private var pending: Pending?
    private var lastMoment: TeamSignInMoment?

    init(account: TeamAccountAccessTicket, authorityEpoch: String, sessions: TeamAccountSessionStore,
         devices: any TeamRegistrationCustody, transport: any TeamDeviceRegistering,
         clock: @escaping @Sendable () -> TeamSignInMoment = { .current() }) throws {
        let raw = account.scope.origin.absoluteString
        let audience = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        _ = try TeamDeviceScope(audience: audience, accountID: account.accountID, authorityEpoch: authorityEpoch)
        self.account = account; self.scope = account.scope; self.audience = audience; self.authorityEpoch = authorityEpoch
        self.sessions = sessions; self.devices = devices; self.transport = transport; self.clock = clock
    }
    func register(consent: Bool) async throws -> TeamDeviceRegistrationResult {
        try Task.checkCancellation()
        guard consent else { throw TeamDeviceCustodyError.consentRequired }
        guard pending == nil else { throw TeamDeviceRegistrationError.busy }
        let start = try moment(), id = UUID()
        let task = Task { try await self.perform(id, start: start) }
        pending = .init(id: id, task: task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    /// Lifecycle/account change: invalidate, but retain busy ownership until the
    /// actual custody/network operation settles, even if it ignores cancellation.
    func cancelPendingRegistration() {
        guard var operation = pending else { return }
        operation.invalidated = true; pending = operation; operation.task.cancel()
    }
    private func perform(_ id: UUID, start: TeamSignInMoment) async throws -> TeamDeviceRegistrationResult {
        _ = try checkpoint(id, start: start)
        let ticket = account // Never substitute whichever account is current now.
        _ = try checkpoint(id, start: start, ticket: ticket)
        let deviceScope = try TeamDeviceScope(audience: audience, accountID: ticket.accountID, authorityEpoch: authorityEpoch)
        let device = try await devices.prepare(scope: deviceScope, consent: true)
        let current = try await checkpoint(id, start: start, ticket: ticket, device: device)
        guard device.scope == deviceScope, let key = device.publicKey else { throw TeamDeviceCustodyError.bindingMismatch }
        let binding = TeamDeviceEnrollmentWire.Binding(audience: audience, authorityEpoch: authorityEpoch, accountID: ticket.accountID,
            sessionID: ticket.sessionID, deviceID: device.deviceID, keyThumbprint: key.thumbprint, accessExpiresAt: ticket.accessExpiresAt)

        if device.phase == .submitPending || device.phase == .recovering {
            guard let deadline = device.proofExpiresAt else { throw TeamDeviceCustodyError.invalidRecord }
            if current.wallTime < deadline { return .recoveryWait(until: deadline) }
            let recovery = try await devices.beginRecovery(device)
            _ = try await checkpoint(id, start: start, ticket: ticket, device: recovery)
            let remote = try await lookup(id, start: start, ticket: ticket, key: key, binding: binding)
            _ = try await checkpoint(id, start: start, ticket: ticket, device: recovery)
            let saved: TeamDeviceSnapshot
            if let remote { saved = try await devices.recordRegistration(recovery, registration: remote) }
            else { saved = try await devices.recordRecoveryAbsence(recovery) }
            _ = try await checkpoint(id, start: start, ticket: ticket, device: saved)
            return remote == nil ? .retryReady(saved) : .registered(saved)
        }
        guard device.phase == .ready || device.phase == .registered else { throw TeamDeviceCustodyError.invalidPhase }
        // Local REGISTERED is metadata, never lasting authority. Reconcile a late
        // server commit before issuing any new challenge for an existing identity.
        let remote = try await lookup(id, start: start, ticket: ticket, key: key, binding: binding)
        _ = try await checkpoint(id, start: start, ticket: ticket, device: device)
        if let remote {
            let saved = try await devices.recordRegistration(device, registration: remote)
            _ = try await checkpoint(id, start: start, ticket: ticket, device: saved)
            return .registered(saved)
        }
        guard device.phase == .ready else { throw TeamDeviceRegistrationError.registrationUnavailable }
        let challenge: TeamPreparedDeviceChallenge
        do { challenge = try await transport.deviceChallenge(key: key, expected: binding, ticket: ticket) }
        catch { _ = try checkpoint(id, start: start, ticket: ticket); throw TeamDeviceRegistrationError.transportFailure }
        let received = try await checkpoint(id, start: start, ticket: ticket, device: device)
        _ = try challenge.message(expected: binding, now: received.wallTime)
        let proofDeadline = received.instant.advanced(by: .milliseconds(challenge.expiresAt - received.wallTime))
        try checkProof(challenge, deadline: proofDeadline, now: received)
        let proof = try await devices.signForSubmission(device, challenge: challenge, binding: binding)
        let beforeDispatch = try await checkpoint(id, start: start, ticket: ticket, device: proof.pending)
        try checkProof(challenge, deadline: proofDeadline, now: beforeDispatch)
        let result: TeamRegisteredDevice
        do { result = try await transport.completeDevice(challenge: challenge, signature: proof.signature, expected: binding, ticket: ticket) }
        catch { _ = try checkpoint(id, start: start, ticket: ticket); throw TeamDeviceRegistrationError.transportFailure }
        let returned = try await checkpoint(id, start: start, ticket: ticket, device: proof.pending)
        try checkProof(challenge, deadline: proofDeadline, now: returned)
        let saved = try await devices.recordRegistration(proof.pending, registration: result)
        let finished = try await checkpoint(id, start: start, ticket: ticket, device: saved)
        try checkProof(challenge, deadline: proofDeadline, now: finished)
        return .registered(saved)
    }
    private func lookup(_ id: UUID, start: TeamSignInMoment, ticket: TeamAccountAccessTicket,
                        key: TeamDeviceEnrollmentWire.PublicKey, binding: TeamDeviceEnrollmentWire.Binding) async throws -> TeamRegisteredDevice? {
        do { return try await transport.lookupDevice(key: key, expected: binding, ticket: ticket) }
        catch { _ = try checkpoint(id, start: start, ticket: ticket); throw TeamDeviceRegistrationError.transportFailure }
    }
    private func checkpoint(_ id: UUID, start: TeamSignInMoment, ticket: TeamAccountAccessTicket,
                            device: TeamDeviceSnapshot) async throws -> TeamSignInMoment {
        _ = try checkpoint(id, start: start, ticket: ticket)
        try await devices.requireCurrent(device)
        // Account validation MUST follow potentially slow device reads. Separate
        // records are not a cross-store transaction; post-write checks are mandatory.
        return try checkpoint(id, start: start, ticket: ticket)
    }
    private func checkpoint(_ id: UUID, start: TeamSignInMoment, ticket: TeamAccountAccessTicket? = nil) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard pending?.id == id, pending?.invalidated == false else { throw TeamDeviceRegistrationError.invalidated }
        let before = try moment()
        try checkLifetime(start, before)
        if let ticket {
            guard ticket.scope == scope else { throw TeamAccountSessionError.scopeMismatch }
            try sessions.requireCurrentAccess(ticket, now: before.wallTime)
        }
        let after = try moment()
        try Task.checkCancellation(); try checkLifetime(start, after)
        if let ticket { _ = try ticket.usableToken(now: after.wallTime) }
        return after
    }
    private func checkLifetime(_ start: TeamSignInMoment, _ now: TeamSignInMoment) throws {
        guard now.wallTime - start.wallTime < 125_000, start.instant.duration(to: now.instant) < .seconds(125) else { throw TeamDeviceRegistrationError.expired }
    }
    private func checkProof(_ proof: TeamPreparedDeviceChallenge, deadline: ContinuousClock.Instant, now: TeamSignInMoment) throws {
        guard now.wallTime < proof.expiresAt, now.instant < deadline else { throw TeamDeviceRegistrationError.expired }
    }
    private func moment() throws -> TeamSignInMoment {
        let now = clock()
        try TeamAccountSessionCodec.checkClock(now.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ now.instant >= $0.instant }) ?? true else { throw TeamDeviceRegistrationError.expired }
        lastMoment = now; return now
    }
}
