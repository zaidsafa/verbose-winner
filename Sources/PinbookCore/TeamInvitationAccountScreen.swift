import Foundation
import Observation

/// Display-only capabilities: no invitation code, session token or account ticket.
struct TeamInvitationAccountReview: Equatable, TeamOnboardingDiagnostic {
    let id: UUID
    let teamID: String
    let role: TeamInvitationRole
    let expiresAt: Int64
    let accountID: String?
    init(teamID: String, role: TeamInvitationRole, expiresAt: Int64, accountID: String?) {
        id = UUID(); self.teamID = teamID; self.role = role
        self.expiresAt = expiresAt; self.accountID = accountID
    }
    func validate() throws {
        guard TeamAuthWire.identifier(teamID), accountID.map(TeamAuthWire.identifier) ?? true,
              expiresAt > 0, expiresAt <= TeamAuthWire.maximumSafeTime else {
            throw TeamInvitationAccountError.invalidPreview
        }
    }
}
struct TeamInvitationAccountReceipt: Equatable, TeamOnboardingDiagnostic {
    let id: UUID
    let teamID: String
    let role: TeamInvitationRole
    let accountID: String
    init(teamID: String, role: TeamInvitationRole, accountID: String) {
        id = UUID(); self.teamID = teamID; self.role = role; self.accountID = accountID
    }
}
protocol TeamInvitationAccountScreenService: Sendable {
    func review() async throws -> TeamInvitationAccountReview
    func access(_ review: TeamInvitationAccountReview, consent: Bool) async throws -> TeamInvitationAccountReceipt
    func close() async throws
}

/// One permanently closeable bridge per presentation. The host retains this
/// bridge, not the raw intent, while the UI sees only an opaque completion receipt.
/// No request on construction and no device registration or membership call here.
actor TeamInvitationAccountScreenBridge: TeamInvitationAccountScreenService {
    private enum Outcome: Sendable {
        case preview(TeamInvitationAccountPreview), account(TeamInviteJoinIntent)
    }
    private let owner: TeamInvitedSignIn
    private var code: String?
    private var prepared: (TeamInvitationAccountReview, TeamInvitationAccountPreview)?
    private var completed: (TeamInvitationAccountReceipt, TeamInviteJoinIntent)?
    private var pending: Task<Outcome, Error>?
    private var closed = false
    private var cleanup: Task<Void, Error>?
    init(owner: TeamInvitedSignIn, code: String) throws {
        guard TeamAuthWire.credential(code) else { throw TeamInvitationAccountError.invalidCode }
        self.owner = owner; self.code = code
    }
    func review() async throws -> TeamInvitationAccountReview {
        try requireIdle()
        defer { pending = nil }
        guard let code else { throw TeamInvitationAccountError.staleConsent }
        prepared = nil
        let owner = owner
        guard case .preview(let value) = try await run({ .preview(try await owner.preview(code: code)) }) else {
            throw TeamInvitationAccountError.invalidPreview
        }
        try requireOpen()
        let display = TeamInvitationAccountReview(teamID: value.teamID, role: value.role,
            expiresAt: value.expiresAt, accountID: value.accountID)
        try display.validate(); prepared = (display, value)
        return display
    }
    func access(_ review: TeamInvitationAccountReview, consent: Bool) async throws -> TeamInvitationAccountReceipt {
        try requireIdle()
        defer { pending = nil }
        guard let (display, preview) = prepared, display == review else { throw TeamInvitationAccountError.staleConsent }
        guard display.accountID != nil || consent else { throw TeamInvitationAccountError.consentRequired }
        prepared = nil; code = nil // One attempt, even if the provider/exchange fails.
        let owner = owner
        guard case .account(let intent) = try await run({
            if display.accountID != nil { return .account(try await owner.existingAccountIntent(preview)) }
            let confirmation = try await owner.confirmAccountAccess(preview, agreed: consent)
            return .account(try await owner.signIn(confirmation))
        }), intent.teamID == display.teamID, intent.role == display.role,
              display.accountID == nil || display.accountID == intent.account.accountID else {
            throw TeamInvitationAccountError.accountUnavailable
        }
        try requireOpen()
        let receipt = TeamInvitationAccountReceipt(teamID: intent.teamID, role: intent.role, accountID: intent.account.accountID)
        completed = (receipt, intent)
        return receipt
    }
    /// Host-only, one-use handoff. Rechecks exact current account and expiry, but
    /// grants no enrollment/join consent. The next owner must revalidate again.
    func takeIntent(_ receipt: TeamInvitationAccountReceipt) async throws -> TeamInviteJoinIntent {
        try requireIdle()
        defer { pending = nil }
        guard let (stored, intent) = completed, stored == receipt else { throw TeamInvitationAccountError.staleConsent }
        completed = nil // A failed current-generation check cannot be replayed.
        let owner = owner
        guard case .account(let checked) = try await run({
            try await owner.requireCurrentHandoff(intent)
            return .account(intent)
        }) else { throw TeamInvitationAccountError.accountUnavailable }
        try requireOpen()
        return checked
    }
    func close() async throws {
        if let cleanup { return try await cleanup.value }
        closed = true; code = nil; prepared = nil; completed = nil
        let pending = pending, owner = owner
        pending?.cancel()
        let task = Task {
            let result: Result<Void, Error>
            do { try await owner.clear(); result = .success(()) }
            catch { result = .failure(error) }
            _ = await pending?.result // Drain non-cooperative work before reporting cleanup.
            try result.get()
        }
        cleanup = task
        try await task.value
    }
    private func requireIdle() throws {
        try requireOpen()
        guard pending == nil else { throw TeamInvitationAccountError.busy }
    }
    private func requireOpen() throws {
        try Task.checkCancellation()
        guard !closed else { throw TeamInvitationAccountError.staleConsent }
    }
    private func run(_ action: @escaping @Sendable () async throws -> Outcome) async throws -> Outcome {
        let task = Task { try Task.checkCancellation(); return try await action() }
        pending = task
        // The public operation retains busy ownership through its final state
        // commit, not just until this nested async helper has returned.
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try requireOpen()
        return result
    }
}

enum TeamInvitationAccountScreenStage: Equatable, Sendable {
    case ready, reviewing, reviewed, accessing, reviewFailed, uncertain, complete, closed
}
/// UI-only state. Closing clears it synchronously; cleanup remains observable.
/// Host must close/recreate on edit, dismissal, background or session replacement.
@MainActor @Observable
final class TeamInvitationAccountScreenModel {
    private(set) var stage = TeamInvitationAccountScreenStage.ready
    private(set) var agreed = false
    private(set) var reviewDetails: TeamInvitationAccountReview?
    private(set) var receipt: TeamInvitationAccountReceipt?
    private(set) var cleanupFailed = false
    @ObservationIgnored private let service: any TeamInvitationAccountScreenService
    @ObservationIgnored private var operation: Task<Outcome, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    private enum Outcome: Sendable {
        case review(TeamInvitationAccountReview), account(TeamInvitationAccountReceipt)
    }
    init(service: any TeamInvitationAccountScreenService) { self.service = service }
    var isWorking: Bool { stage == .reviewing || stage == .accessing }
    var canReview: Bool { stage == .ready || stage == .reviewFailed }
    var canAccess: Bool { stage == .reviewed && (reviewDetails?.accountID != nil || agreed) && reviewDetails != nil }
    func setAgreement(_ value: Bool) {
        if stage == .reviewed && reviewDetails?.accountID == nil { agreed = value }
    }
    func review() async {
        guard canReview, !Task.isCancelled else { return }
        reviewDetails = nil; agreed = false; receipt = nil
        let service = service
        await run(stage: .reviewing) { .review(try await service.review()) }
    }
    func access() async {
        guard canAccess, let selected = reviewDetails, !Task.isCancelled else { return }
        let consent = agreed
        agreed = false
        let service = service
        await run(stage: .accessing) { .account(try await service.access(selected, consent: consent)) }
    }
    func close() {
        guard stage != .closed else { return }
        generation = UUID(); stage = .closed; agreed = false; reviewDetails = nil; receipt = nil
        let pending = operation, service = service
        operation = nil; pending?.cancel()
        cleanup = Task {
            do { try await service.close() }
            catch { cleanupFailed = true }
            _ = await pending?.result
        }
    }
    func waitForCleanup() async { await cleanup?.value }
    private func run(stage next: TeamInvitationAccountScreenStage,
                     action: @escaping @Sendable () async throws -> Outcome) async {
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
            case .review(let value):
                try value.validate(); reviewDetails = value; stage = .reviewed
            case .account(let value):
                guard let expected = reviewDetails, value.teamID == expected.teamID, value.role == expected.role,
                      TeamAuthWire.identifier(value.accountID),
                      expected.accountID == nil || expected.accountID == value.accountID else {
                    throw TeamInvitationAccountError.accountUnavailable
                }
                receipt = value; stage = .complete
            }
        } catch {
            guard generation == id, stage != .closed else { return }
            agreed = false; receipt = nil; reviewDetails = nil
            stage = next == .reviewing ? .reviewFailed : .uncertain
        }
    }
}
