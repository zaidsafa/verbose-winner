import Foundation

struct TeamInvitationDeviceContext: Sendable {
    let accountID: String
    let teamID: String
    let role: TeamInvitationRole
}

/// Retained device step between account access and membership consent. The UI
/// receives only context; the invitation and account ticket stay private here.
/// Creation/transition does not create a key, register a device or join a team.
actor TeamInvitationDeviceFlow {
    nonisolated let context: TeamInvitationDeviceContext
    private var invitation: TeamInviteJoinIntent?
    private let registration: TeamDeviceRegistration
    private let authorityEpoch: String
    private let sessions: TeamAccountSessionStore
    private let custody: TeamDeviceCustody
    private let joins: TeamJoinStore
    private let transport: any TeamDeviceRegistering & TeamMembershipTransport
    private let clock: @Sendable () -> TeamSignInMoment
    private var lastMoment: TeamSignInMoment?
    private var pending: Task<TeamDeviceRegistrationResult, Error>?
    private var cleanup: Task<Void, Never>?
    private var registered = false
    private var closed = false

    /// Explicit parent action after account completion. Consume the exact receipt
    /// BEFORE closing its source screen. Cleanup uncertainty prevents progression.
    static func begin(accountScreen: TeamInvitationAccountScreenBridge, receipt: TeamInvitationAccountReceipt,
                      authorityEpoch: String, sessions: TeamAccountSessionStore,
                      custody: TeamDeviceCustody, joins: TeamJoinStore,
                      transport: any TeamDeviceRegistering & TeamMembershipTransport,
                      clock: @escaping @Sendable () -> TeamSignInMoment = { .current() }) async throws -> TeamInvitationDeviceFlow {
        let intent = try await accountScreen.takeIntent(receipt)
        try await accountScreen.close()
        try Task.checkCancellation()
        return try .init(invitation: intent, authorityEpoch: authorityEpoch, sessions: sessions,
            custody: custody, joins: joins, transport: transport, clock: clock)
    }
    private init(invitation: TeamInviteJoinIntent, authorityEpoch: String, sessions: TeamAccountSessionStore,
                 custody: TeamDeviceCustody, joins: TeamJoinStore,
                 transport: any TeamDeviceRegistering & TeamMembershipTransport,
                 clock: @escaping @Sendable () -> TeamSignInMoment) throws {
        self.invitation = invitation; self.authorityEpoch = authorityEpoch; self.sessions = sessions
        self.custody = custody; self.joins = joins; self.transport = transport; self.clock = clock
        context = .init(accountID: invitation.account.accountID, teamID: invitation.teamID, role: invitation.role)
        registration = try .init(account: invitation.account, authorityEpoch: authorityEpoch, sessions: sessions,
            devices: TeamRegistrationCustodyDriver(custody: custody), transport: transport, clock: clock)
    }
    /// Every call needs fresh UI consent. A wait or recovered-null result is NOT
    /// registration and cannot advance; neither this layer nor its owner retries.
    func register(consent: Bool) async throws -> TeamDeviceRegistrationResult {
        try requireIdle()
        guard consent else { throw TeamDeviceCustodyError.consentRequired }
        _ = try currentInvitation()
        registered = false
        let owner = registration
        let task = Task { try Task.checkCancellation(); return try await owner.register(consent: true) }
        pending = task
        defer { pending = nil }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try requireOpen()
        let intent = try currentInvitation()
        switch result {
        case .registered(let device):
            guard device.scope.accountID == intent.account.accountID, device.scope.authorityEpoch == authorityEpoch,
                  device.phase == .registered, device.enrollmentID != nil else { throw TeamDeviceCustodyError.bindingMismatch }
            registered = true
        case .retryReady, .recoveryWait: break
        }
        return result
    }
    /// Explicit one-use transition, not a team-join request. The returned child
    /// still requires Review and a NEW membership consent. It owns the intent
    /// after this handoff; closing this completed parent does not close that child.
    func takeMembershipScreen() throws -> TeamMembershipScreenBridge {
        try requireIdle()
        guard registered else { throw TeamDeviceRegistrationError.registrationUnavailable }
        let intent = try currentInvitation()
        let owner = try TeamMembershipJoin(account: intent.account, authorityEpoch: authorityEpoch, sessions: sessions,
            devices: TeamMembershipDeviceDriver(custody: custody), metadata: TeamMembershipMetadataDriver(store: joins),
            transport: transport, clock: clock)
        let screen = TeamMembershipScreenBridge(owner: owner, invitation: intent)
        invitation = nil; registered = false
        return screen
    }
    func close() async {
        if let cleanup { return await cleanup.value }
        closed = true; invitation = nil; registered = false
        let pending = pending, owner = registration
        pending?.cancel()
        let task = Task {
            await owner.cancelPendingRegistration()
            _ = await pending?.result
        }
        cleanup = task
        await task.value
    }
    private func requireOpen() throws {
        try Task.checkCancellation()
        guard !closed, invitation != nil else { throw TeamDeviceRegistrationError.invalidated }
    }
    private func requireIdle() throws {
        try requireOpen()
        guard pending == nil else { throw TeamDeviceRegistrationError.busy }
    }
    private func currentInvitation() throws -> TeamInviteJoinIntent {
        try requireOpen()
        guard let intent = invitation else { throw TeamDeviceRegistrationError.invalidated }
        let before = try moment()
        guard before.wallTime < intent.expiresAt else { throw TeamInvitationAccountError.expired }
        try sessions.requireCurrentAccess(intent.account, now: before.wallTime)
        let after = try moment()
        try Task.checkCancellation()
        guard after.wallTime < intent.expiresAt else { throw TeamInvitationAccountError.expired }
        _ = try intent.account.usableToken(now: after.wallTime)
        return intent
    }
    private func moment() throws -> TeamSignInMoment {
        let now = clock()
        try TeamAccountSessionCodec.checkClock(now.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ now.instant >= $0.instant }) ?? true else { throw TeamDeviceRegistrationError.expired }
        lastMoment = now
        return now
    }
}
