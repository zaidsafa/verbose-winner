import Foundation
import Observation

struct TeamMembershipScreenContext: Sendable {
    let accountID: String
    let teamID: String
    /// Nil means a saved-team recovery entry, not a new invitation.
    let invitedRole: TeamInvitationRole?
    let isRetry: Bool
    init(accountID: String, teamID: String, invitedRole: TeamInvitationRole?, isRetry: Bool = false) {
        self.accountID = accountID; self.teamID = teamID
        self.invitedRole = invitedRole; self.isRetry = isRetry
    }
    func validate() throws {
        guard TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(teamID),
              !isRetry || invitedRole != nil else { throw TeamMembershipJoinError.invalidIntent }
    }
}
protocol TeamMembershipScreenService: Sendable {
    var context: TeamMembershipScreenContext { get }
    func review() async throws -> TeamMembershipRetryPreparation
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot
    func recover() async throws -> TeamJoinSnapshot
    func close() async
}
/// Holds the raw invitation only in memory behind the already-account-bound owner.
/// No automatic request on construction. One bridge per screen, never shared hosts.
actor TeamMembershipScreenBridge: TeamMembershipScreenService {
    nonisolated let context: TeamMembershipScreenContext
    private let owner: TeamMembershipJoin
    private var invitation: TeamInviteJoinIntent?
    private var retryToken: String?
    private var closed = false
    init(owner: TeamMembershipJoin, invitation: TeamInviteJoinIntent) {
        self.owner = owner; self.invitation = invitation
        context = .init(accountID: invitation.account.accountID, teamID: invitation.teamID, invitedRole: invitation.role)
    }
    init(owner: TeamMembershipJoin, accountID: String, savedTeamID: String) throws {
        self.owner = owner
        context = .init(accountID: accountID, teamID: savedTeamID, invitedRole: nil)
        try context.validate()
    }
    /// Reopening the original link is explicit. The raw token is memory-only;
    /// this entry does not require a fresh preview of an expired/consumed link.
    init(owner: TeamMembershipJoin, accountID: String, teamID: String,
         originalInvitationToken: String, role: TeamInvitationRole) throws {
        guard TeamAuthWire.credential(originalInvitationToken) else { throw TeamMembershipJoinError.invalidIntent }
        self.owner = owner; retryToken = originalInvitationToken
        context = .init(accountID: accountID, teamID: teamID, invitedRole: role, isRetry: true)
        try context.validate()
    }
    func review() async throws -> TeamMembershipRetryPreparation {
        guard !closed else { throw TeamMembershipJoinError.invalidated }
        let result: TeamMembershipRetryPreparation
        if let retryToken, let role = context.invitedRole {
            result = try await owner.prepareRetry(token: retryToken, teamID: context.teamID, role: role)
        } else if let invitation {
            result = .ready(try await owner.prepare(invitation))
        } else { throw TeamMembershipJoinError.invalidated }
        guard !closed else { throw TeamMembershipJoinError.invalidated }
        if case .joined = result { invitation = nil; retryToken = nil }
        return result
    }
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot {
        guard !closed, consent, invitation != nil || retryToken != nil,
              preview.teamID == context.teamID, preview.accountID == context.accountID,
              preview.role == context.invitedRole else { throw TeamMembershipJoinError.staleConsent }
        invitation = nil; retryToken = nil
        return try await owner.join(preview, consent: consent)
    }
    func recover() async throws -> TeamJoinSnapshot {
        guard !closed else { throw TeamMembershipJoinError.invalidated }
        invitation = nil; retryToken = nil
        return try await owner.recover(teamID: context.teamID)
    }
    func close() async { closed = true; invitation = nil; retryToken = nil; await owner.close() }
}

enum TeamMembershipScreenStage: Sendable, Equatable {
    case ready, reviewing, consent, joining, checking, reviewFailed, uncertain, confirmed, closed
}
struct TeamMembershipScreenDetails: Sendable {
    let accountID: String
    let teamID: String
    let role: TeamInvitationRole
}

/// UI-only state. No invitation/session credentials, persistence or raw errors.
/// Host must close and recreate when its account/session changes.
@MainActor @Observable
final class TeamMembershipScreenModel {
    let context: TeamMembershipScreenContext
    private(set) var stage = TeamMembershipScreenStage.ready
    private(set) var agreed = false
    private(set) var details: TeamMembershipScreenDetails?
    @ObservationIgnored private let service: any TeamMembershipScreenService
    @ObservationIgnored private var preview: TeamMembershipJoinPreview?
    @ObservationIgnored private var operation: Task<Outcome, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    private enum Outcome: Sendable { case preview(TeamMembershipJoinPreview), membership(TeamJoinSnapshot) }
    init(service: any TeamMembershipScreenService) throws {
        context = service.context; try context.validate(); self.service = service
    }
    var isWorking: Bool { stage == .reviewing || stage == .joining || stage == .checking }
    var canReview: Bool { context.invitedRole != nil && (stage == .ready || stage == .reviewFailed) }
    var canJoin: Bool { stage == .consent && agreed && preview != nil }
    var canCheck: Bool { stage == .uncertain || (stage == .ready && context.invitedRole == nil) }
    func setAgreement(_ value: Bool) { if stage == .consent { agreed = value } }
    func review() async {
        guard canReview, !Task.isCancelled else { return }
        preview = nil; agreed = false; details = nil
        let service = service
        let isRetry = context.isRetry
        await run(stage: .reviewing) {
            switch try await service.review() {
            case .ready(let value): return .preview(value)
            case .joined(let value):
                guard isRetry else { throw TeamMembershipJoinError.invalidIntent }
                return .membership(value)
            }
        }
    }
    func join() async {
        guard canJoin, let selected = preview, !Task.isCancelled else { return }
        preview = nil; agreed = false // Drop before sending; no second submit path.
        let service = service
        await run(stage: .joining) { .membership(try await service.join(selected, consent: true)) }
    }
    func checkMembership() async {
        guard canCheck, !Task.isCancelled else { return }
        let service = service
        await run(stage: .checking) { .membership(try await service.recover()) }
    }
    /// Synchronously clears UI before asynchronous owner cleanup starts. This
    /// separate task survives cancellation of the view's presentation task.
    func close() {
        guard stage != .closed else { return }
        generation = UUID(); stage = .closed; preview = nil; details = nil; agreed = false
        let pending = operation
        pending?.cancel(); operation = nil
        let service = service
        cleanup = Task { await service.close(); _ = await pending?.result }
    }
    func waitForCleanup() async { await cleanup?.value }
    private func run(stage next: TeamMembershipScreenStage, action: @escaping @Sendable () async throws -> Outcome) async {
        guard operation == nil, stage != .closed else { return }
        let id = UUID(); generation = id; stage = next
        let task = Task { try Task.checkCancellation(); return try await action() }
        operation = task
        defer { if generation == id { operation = nil } }
        do {
            let outcome = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == id, stage != .closed else { return }
            switch outcome {
            case .preview(let value):
                guard value.accountID == context.accountID, value.teamID == context.teamID,
                      value.role == context.invitedRole else { throw TeamMembershipJoinError.invalidIntent }
                preview = value; details = .init(accountID: value.accountID, teamID: value.teamID, role: value.role)
                stage = .consent
            case .membership(let value):
                guard value.scope.accountID == context.accountID, value.teamID == context.teamID,
                      value.phase == .confirmed, value.membershipRevision != nil,
                      context.invitedRole == nil || context.invitedRole == value.role else { throw TeamJoinError.bindingMismatch }
                details = .init(accountID: value.scope.accountID, teamID: value.teamID, role: value.role)
                stage = .confirmed
            }
        } catch {
            guard generation == id, stage != .closed else { return }
            preview = nil; agreed = false
            // Reopening an invitation with durable join metadata must offer
            // tokenless reconciliation, not a futile new preparation loop.
            stage = next == .reviewing && (error as? TeamMembershipJoinError) != .recoveryRequired ? .reviewFailed : .uncertain
        }
    }
}
