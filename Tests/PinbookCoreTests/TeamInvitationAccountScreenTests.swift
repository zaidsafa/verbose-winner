import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor InvitationScreenService: TeamInvitationAccountScreenService {
    private(set) var calls = [String]()
    private(set) var consents = [Bool]()
    private let existing: Bool
    private let gate: String?
    private var failure: String?
    private var mismatch: String?
    private var waiter: CheckedContinuation<Void, Never>?
    init(existing: Bool = false, gate: String? = nil, failure: String? = nil, mismatch: String? = nil) {
        self.existing = existing; self.gate = gate; self.failure = failure; self.mismatch = mismatch
    }
    func configure(failure: String? = nil, mismatch: String? = nil) { self.failure = failure; self.mismatch = mismatch }
    private func step(_ name: String) async throws {
        calls.append(name)
        if gate == name { await withCheckedContinuation { waiter = $0 } }
        if failure == name { throw TeamInvitationAccountError.accountUnavailable }
    }
    func review() async throws -> TeamInvitationAccountReview {
        try await step("review")
        return .init(teamID: mismatch == "team" ? "invalid team" : "public-team", role: .reviewer,
            expiresAt: mismatch == "expiry" ? 0 : 100_000,
            accountID: mismatch == "account" ? "invalid account" : existing ? "public-account" : nil)
    }
    func access(_ review: TeamInvitationAccountReview, consent: Bool) async throws -> TeamInvitationAccountReceipt {
        consents.append(consent); try await step("access")
        return .init(teamID: mismatch == "team" ? "different-team" : review.teamID,
            role: mismatch == "role" ? .member : review.role,
            accountID: mismatch == "invalid-account" ? "invalid account" : mismatch == "account" ? "different-account" : "public-account")
    }
    func close() async throws { try await step("close") }
    func finish() { let saved = waiter; waiter = nil; saved?.resume() }
}

@MainActor struct TeamInvitationAccountScreenTests {
    @Test func newAccountRequiresReviewAndNewUncheckedConsentBeforeOneAccess() async {
        let service = InvitationScreenService(), model = TeamInvitationAccountScreenModel(service: service)
        #expect(model.canReview && !model.canAccess && !model.agreed && model.receipt == nil)
        model.setAgreement(true); await model.access()
        #expect(await service.calls.isEmpty)
        await model.review()
        #expect(model.stage == .reviewed && !model.agreed && !model.canAccess)
        #expect(model.reviewDetails?.teamID == "public-team" && model.reviewDetails?.accountID == nil)
        await model.access(); #expect(await service.calls == ["review"])
        model.setAgreement(true); await model.access()
        #expect(model.stage == .complete && !model.agreed && !model.canAccess)
        #expect(model.receipt?.accountID == "public-account")
        model.setAgreement(true); await model.access(); await model.review()
        #expect(await service.calls == ["review", "access"])
        #expect(await service.consents == [true])
        model.close(); await model.waitForCleanup()
    }
    @Test func existingAccountRequiresExplicitActionWithoutNewAccountConsent() async {
        let service = InvitationScreenService(existing: true), model = TeamInvitationAccountScreenModel(service: service)
        await model.review()
        #expect(model.canAccess && model.reviewDetails?.accountID == "public-account")
        #expect(await service.calls == ["review"])
        model.setAgreement(true); #expect(!model.agreed)
        await model.access()
        #expect(model.stage == .complete)
        #expect(await service.consents == [false])
        model.close(); await model.waitForCleanup()
    }
    @Test func previewFailureOffersOnlyExplicitReadOnlyReview() async {
        let service = InvitationScreenService(failure: "review"), model = TeamInvitationAccountScreenModel(service: service)
        await model.review()
        #expect(model.stage == .reviewFailed && model.canReview && !model.canAccess)
        await service.configure(); await model.review()
        #expect(model.stage == .reviewed && !model.agreed)
        #expect(await service.calls == ["review", "review"])
        model.close(); await model.waitForCleanup()
    }
    @Test func uncertainAccessCannotReplayProviderOrReviewOriginalCode() async {
        for existing in [false, true] {
            let service = InvitationScreenService(existing: existing, failure: "access")
            let model = TeamInvitationAccountScreenModel(service: service)
            await model.review(); model.setAgreement(true); await model.access()
            #expect(model.stage == .uncertain && !model.canReview && !model.canAccess && !model.agreed)
            #expect(model.receipt == nil && model.reviewDetails == nil)
            await service.configure(); model.setAgreement(true); await model.review(); await model.access()
            #expect(await service.calls == ["review", "access"])
            model.close(); await model.waitForCleanup()
        }
    }
    @Test func malformedReviewAndMismatchedAccessCannotBecomeCompletion() async {
        for mismatch in ["team", "account", "expiry"] {
            let service = InvitationScreenService(mismatch: mismatch), model = TeamInvitationAccountScreenModel(service: service)
            await model.review()
            #expect(model.stage == .reviewFailed && model.reviewDetails == nil && !model.canAccess)
            model.close(); await model.waitForCleanup()
        }
        for mismatch in ["team", "account", "invalid-account", "role"] {
            let service = InvitationScreenService(existing: true), model = TeamInvitationAccountScreenModel(service: service)
            await model.review(); await service.configure(mismatch: mismatch); await model.access()
            #expect(model.stage == .uncertain && model.receipt == nil)
            model.close(); await model.waitForCleanup()
        }
    }
    @Test func closeClearsSynchronouslyAndRejectsAllLateResults() async throws {
        for step in ["review", "access"] {
            let service = InvitationScreenService(gate: step), model = TeamInvitationAccountScreenModel(service: service)
            if step == "access" { await model.review(); model.setAgreement(true) }
            let work = Task { if step == "review" { await model.review() } else { await model.access() } }
            try await waitFor(step, in: service)
            model.close()
            #expect(model.stage == .closed && !model.agreed && model.reviewDetails == nil && model.receipt == nil)
            await model.review(); await model.access(); model.close()
            await service.finish(); await work.value; await model.waitForCleanup()
            #expect(model.stage == .closed && model.receipt == nil && !model.cleanupFailed)
            #expect(await service.calls.filter { $0 == "close" }.count == 1)
        }
    }
    @Test func callerCancellationRejectsLateReviewAndAccess() async throws {
        for step in ["review", "access"] {
            let service = InvitationScreenService(gate: step), model = TeamInvitationAccountScreenModel(service: service)
            if step == "access" { await model.review(); model.setAgreement(true) }
            let work = Task { if step == "review" { await model.review() } else { await model.access() } }
            try await waitFor(step, in: service); work.cancel()
            await service.finish(); await work.value
            #expect(model.stage == (step == "review" ? .reviewFailed : .uncertain))
            #expect(!model.agreed && model.receipt == nil && model.reviewDetails == nil)
            model.close(); await model.waitForCleanup()
        }
    }
    @Test func duplicateActionsCannotStartParallelReviewOrAccess() async throws {
        for step in ["review", "access"] {
            let service = InvitationScreenService(gate: step), model = TeamInvitationAccountScreenModel(service: service)
            if step == "access" { await model.review(); model.setAgreement(true) }
            let work = Task { if step == "review" { await model.review() } else { await model.access() } }
            try await waitFor(step, in: service)
            await model.review(); model.setAgreement(true); await model.access()
            #expect(await service.calls.filter { $0 == step }.count == 1)
            await service.finish(); await work.value
            model.close(); await model.waitForCleanup()
        }
    }
    @Test func cleanupFailureRemainsVisibleWithoutRestoringConsentOrReceipt() async {
        let service = InvitationScreenService(failure: "close"), model = TeamInvitationAccountScreenModel(service: service)
        await model.review(); model.setAgreement(true); await model.access()
        model.close(); await model.waitForCleanup()
        #expect(model.cleanupFailed && model.stage == .closed && model.receipt == nil && model.reviewDetails == nil)
        #expect(!model.canAccess && !model.canReview)
    }
    private func waitFor(_ call: String, in service: InvitationScreenService) async throws {
        for _ in 0..<200 {
            if await service.calls.contains(call) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic invitation screen operation did not start")
    }
}
