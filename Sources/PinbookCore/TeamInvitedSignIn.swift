import Foundation

enum TeamInvitationAccountError: Error, Equatable {
    case busy, invalidCode, invalidPreview, consentRequired, staleConsent, expired
    case previewUnavailable, accountUnavailable, existingAccountRequired, newAccountRequired
}
struct TeamInvitationAccountPreview: TeamOnboardingDiagnostic {
    fileprivate let id: UUID
    let teamID: String
    let role: TeamInvitationRole
    let expiresAt: Int64
    let accountID: String?
}
struct TeamInvitationAccountConsent: TeamOnboardingDiagnostic {
    fileprivate let ownerID: UUID
    fileprivate let previewID: UUID
    fileprivate let id: UUID
}
/// Memory-only handoff, NOT permission to join. Membership requires separate
/// confirmation, current session/device checks and durable intent before accept.
struct TeamInviteJoinIntent: TeamOnboardingDiagnostic {
    let token: String
    let teamID: String
    let role: TeamInvitationRole
    let expiresAt: Int64
    let account: TeamAccountAccessTicket
    fileprivate init(token: String, preview: TeamInvitationAccountPreview, account: TeamAccountAccessTicket) {
        self.token = token; teamID = preview.teamID; role = preview.role
        expiresAt = preview.expiresAt; self.account = account
    }
}
protocol TeamInvitationAccountTransport: Sendable {
    func previewInvitation(token: String) async throws -> TeamInvitationPreview
    func invitedChallenge(providerID: String, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthChallenge
    func invitedExchange(_ submission: TeamNativeLoginSubmission, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthSessionPair
}
extension TeamAuthHTTPClient: TeamInvitationAccountTransport {}

private struct InvitationBoundAuth: TeamAccountSigningIn, TeamOnboardingDiagnostic {
    let transport: any TeamInvitationAccountTransport
    let token: String
    let teamID: String
    let role: TeamInvitationRole
    let validate: @Sendable () async throws -> Void
    func challenge(providerID: String) async throws -> TeamAuthChallenge {
        try await validate()
        let result = try await transport.invitedChallenge(providerID: providerID, token: token, teamID: teamID, role: role)
        try await validate(); return result
    }
    func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair {
        try await validate()
        let result = try await transport.invitedExchange(submission, token: token, teamID: teamID, role: role)
        try await validate(); return result
    }
}
private struct InvitationBoundIdentity: TeamNativeIdentityAuthorizing {
    let identity: any TeamNativeIdentityAuthorizing
    let validate: @Sendable () async throws -> Void
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        try await validate()
        let result = try await identity.authorize(context)
        try Task.checkCancellation(); try await validate()
        return result
    }
}

/// Retain one flow per visible invitation screen. No saved UI state/clipboard,
/// token logging, automatic membership, provider exchange retry or session overwrite.
actor TeamInvitedSignIn {
    private struct Prepared {
        let token: String
        let display: TeamInvitationAccountPreview
        let account: TeamAccountAccessTicket?
        let received: TeamSignInMoment
        let deadline: ContinuousClock.Instant
        var consentID: UUID?
    }
    private struct Pending {
        let id: UUID
        let cancel: @Sendable () -> Void
        let native: TeamAccountSignInCoordinator?
        var invalidated = false
    }
    private let ownerID = UUID()
    private let provider: TeamNativeSignInProvider
    private let scope: TeamAccountSessionScope
    private let sessions: TeamAccountSessionStore
    private let identity: any TeamNativeIdentityAuthorizing
    private let transport: any TeamInvitationAccountTransport
    private let clock: @Sendable () -> TeamSignInMoment
    private var lastMoment: TeamSignInMoment?
    private var prepared: Prepared?
    private var pending: Pending?

    init(provider: TeamNativeSignInProvider, scope: TeamAccountSessionScope, sessions: TeamAccountSessionStore,
         identity: any TeamNativeIdentityAuthorizing, transport: any TeamInvitationAccountTransport,
         clock: @escaping @Sendable () -> TeamSignInMoment = { .current() }) {
        self.provider = provider; self.scope = scope; self.sessions = sessions
        self.identity = identity; self.transport = transport; self.clock = clock
    }
    func preview(code: String) async throws -> TeamInvitationAccountPreview {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamInvitationAccountError.busy }
        prepared = nil
        guard TeamAuthWire.credential(code) else { throw TeamInvitationAccountError.invalidCode }
        let start = try moment(), id = UUID()
        let task = Task { try await self.performPreview(code: code, id: id, start: start) }
        pending = .init(id: id, cancel: { task.cancel() }, native: nil)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func performPreview(code: String, id: UUID, start: TeamSignInMoment) async throws -> TeamInvitationAccountPreview {
        _ = try checkpoint(id, start: start)
        let reply: TeamInvitationPreview
        do { reply = try await transport.previewInvitation(token: code) }
        catch { _ = try checkpoint(id, start: start); throw TeamInvitationAccountError.previewUnavailable }
        let now = try checkpoint(id, start: start)
        guard TeamAuthWire.identifier(reply.inviteID), TeamAuthWire.identifier(reply.teamID),
              reply.expiresAt > now.wallTime, reply.expiresAt <= TeamAuthWire.maximumSafeTime,
              reply.expiresAt - now.wallTime <= 604_805_000 else { throw TeamInvitationAccountError.invalidPreview }
        let account: TeamAccountAccessTicket?
        do {
            if let snapshot = try sessions.load(scope: scope) {
                account = try TeamAccountAccessTicket(snapshot: snapshot)
                _ = try account?.usableToken(now: moment().wallTime)
            } else { account = nil }
        } catch { _ = try checkpoint(id, start: start); throw TeamInvitationAccountError.accountUnavailable }
        let finished = try checkpoint(id, start: start)
        guard finished.wallTime < reply.expiresAt else { throw TeamInvitationAccountError.expired }
        if let account { try sessions.requireCurrentAccess(account, now: finished.wallTime) }
        let checked = try checkpoint(id, start: start)
        guard checked.wallTime < reply.expiresAt else { throw TeamInvitationAccountError.expired }
        if let account { _ = try account.usableToken(now: checked.wallTime) }
        let display = TeamInvitationAccountPreview(id: UUID(), teamID: reply.teamID, role: reply.role,
            expiresAt: reply.expiresAt, accountID: account?.accountID)
        prepared = .init(token: code, display: display, account: account, received: checked,
            deadline: checked.instant.advanced(by: .milliseconds(min(300_000, reply.expiresAt - checked.wallTime))))
        return display
    }
    func confirmAccountAccess(_ display: TeamInvitationAccountPreview, agreed: Bool) throws -> TeamInvitationAccountConsent {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamInvitationAccountError.busy }
        guard agreed else { throw TeamInvitationAccountError.consentRequired }
        guard var value = prepared, value.display.id == display.id else { throw TeamInvitationAccountError.staleConsent }
        try validate(value, now: moment())
        guard value.account == nil else { throw TeamInvitationAccountError.existingAccountRequired }
        let id = UUID(); value.consentID = id; prepared = value
        return .init(ownerID: ownerID, previewID: display.id, id: id)
    }
    func signIn(_ consent: TeamInvitationAccountConsent) async throws -> TeamInviteJoinIntent {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamInvitationAccountError.busy }
        guard let value = prepared, consent.ownerID == ownerID, consent.previewID == value.display.id,
              consent.id == value.consentID else { throw TeamInvitationAccountError.staleConsent }
        try validate(value, now: moment())
        guard value.account == nil else { throw TeamInvitationAccountError.existingAccountRequired }
        prepared = nil // One attempt consumes consent; failure never rearms it.
        let start = try moment(), id = UUID()
        let validate: @Sendable () async throws -> Void = { [self] in
            try await self.validatePending(value, id: id, start: start)
        }
        let bound = InvitationBoundAuth(transport: transport, token: value.token, teamID: value.display.teamID,
            role: value.display.role, validate: validate)
        let native = TeamAccountSignInCoordinator(provider: provider, scope: scope, store: sessions,
            identity: InvitationBoundIdentity(identity: identity, validate: validate), transport: bound, clock: clock)
        let task = Task { try await self.performSignIn(value, native: native, id: id, start: start) }
        pending = .init(id: id, cancel: { task.cancel() }, native: native)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func performSignIn(_ value: Prepared, native: TeamAccountSignInCoordinator, id: UUID,
                               start: TeamSignInMoment) async throws -> TeamInviteJoinIntent {
        try validate(value, now: checkpoint(id, start: start))
        let account = try await native.signInAccess(consent: true)
        try validate(value, now: checkpoint(id, start: start))
        guard account.scope == scope else { throw TeamAccountSessionError.scopeMismatch }
        try sessions.requireCurrentAccess(account, now: moment().wallTime)
        let finished = try checkpoint(id, start: start)
        try validate(value, now: finished)
        _ = try account.usableToken(now: finished.wallTime)
        return .init(token: value.token, preview: value.display, account: account)
    }
    /// Separate existing-account button. It reuses the EXACT account displayed by
    /// preview, never whichever account happens to be signed in after a UI race.
    func existingAccountIntent(_ display: TeamInvitationAccountPreview) throws -> TeamInviteJoinIntent {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamInvitationAccountError.busy }
        guard let value = prepared, value.display.id == display.id else { throw TeamInvitationAccountError.staleConsent }
        try validate(value, now: moment())
        guard let account = value.account else { throw TeamInvitationAccountError.newAccountRequired }
        prepared = nil
        try sessions.requireCurrentAccess(account, now: moment().wallTime)
        let now = try moment(); try Task.checkCancellation()
        try validate(value, now: now); _ = try account.usableToken(now: now.wallTime)
        return .init(token: value.token, preview: display, account: account)
    }
    /// Revalidate a memory-only handoff when its screen transfers ownership.
    /// This is not membership authority; subsequent owners recheck their scope.
    func requireCurrentHandoff(_ intent: TeamInviteJoinIntent) throws {
        try Task.checkCancellation()
        guard intent.account.scope == scope else { throw TeamAccountSessionError.scopeMismatch }
        let now = try moment()
        guard now.wallTime < intent.expiresAt else { throw TeamInvitationAccountError.expired }
        try sessions.requireCurrentAccess(intent.account, now: now.wallTime)
        // Keychain can block. The timestamp sampled before that read is not a
        // fresh expiry/cancellation check for the value we are about to return.
        let finished = try moment()
        try Task.checkCancellation()
        guard finished.wallTime < intent.expiresAt else { throw TeamInvitationAccountError.expired }
        _ = try intent.account.usableToken(now: finished.wallTime)
    }
    /// Editing/dismissal/background clears references and cancels only this
    /// flow's native reservation. It NEVER deletes an already-active account.
    func clear() async throws {
        prepared = nil
        guard var value = pending else { return }
        value.invalidated = true; pending = value; value.cancel()
        if let native = value.native { try await native.cancelPendingSignIn() }
    }
    private func validate(_ value: Prepared, now: TeamSignInMoment) throws {
        guard now.wallTime >= value.received.wallTime, now.wallTime < value.display.expiresAt,
              now.instant >= value.received.instant, now.instant < value.deadline,
              now.wallTime - value.received.wallTime < 300_000 else { throw TeamInvitationAccountError.expired }
    }
    private func validatePending(_ value: Prepared, id: UUID, start: TeamSignInMoment) throws {
        try validate(value, now: checkpoint(id, start: start))
    }
    private func checkpoint(_ id: UUID, start: TeamSignInMoment) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard pending?.id == id, pending?.invalidated == false else { throw TeamInvitationAccountError.staleConsent }
        let now = try moment()
        guard now.wallTime - start.wallTime < 125_000, start.instant.duration(to: now.instant) < .seconds(125) else { throw TeamInvitationAccountError.expired }
        return now
    }
    private func moment() throws -> TeamSignInMoment {
        let now = clock()
        try TeamAccountSessionCodec.checkClock(now.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ now.instant >= $0.instant }) ?? true else { throw TeamInvitationAccountError.expired }
        lastMoment = now; return now
    }
}
