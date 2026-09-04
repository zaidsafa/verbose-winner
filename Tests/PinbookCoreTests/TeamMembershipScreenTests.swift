import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor MembershipScreenService: TeamMembershipScreenService {
    nonisolated let context: TeamMembershipScreenContext
    private(set) var calls = [String]()
    private var failure: String?
    private var mismatch: String?
    private let gate: String?
    private var waiter: CheckedContinuation<Void, Never>?
    init(recovery: Bool = false, failure: String? = nil, mismatch: String? = nil, gate: String? = nil) {
        context = .init(accountID: "public-account", teamID: "public-team", invitedRole: recovery ? nil : .member)
        self.failure = failure; self.mismatch = mismatch; self.gate = gate
    }
    func configure(failure: String? = nil, mismatch: String? = nil) { self.failure = failure; self.mismatch = mismatch }
    private func step(_ name: String) async throws {
        calls.append(name)
        if gate == name { await withCheckedContinuation { waiter = $0 } }
        if failure == name { throw TeamMembershipJoinError.transportFailure }
    }
    func review() async throws -> TeamMembershipJoinPreview {
        try await step("review")
        if failure == "existing" { throw TeamMembershipJoinError.recoveryRequired }
        return .init(accountID: mismatch == "account" ? "foreign" : context.accountID,
            teamID: mismatch == "team" ? "foreign" : context.teamID, role: mismatch == "role" ? .reviewer : .member)
    }
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot {
        #expect(consent && preview.teamID == context.teamID)
        try await step("join"); return try result()
    }
    func recover() async throws -> TeamJoinSnapshot { try await step("recover"); return try result() }
    private func result() throws -> TeamJoinSnapshot {
        try .init(scope: .init(audience: "https://pinbook.example", accountID: mismatch == "account" ? "foreign" : context.accountID,
            authorityEpoch: "public-epoch"), teamID: mismatch == "team" ? "foreign" : context.teamID,
            enrollmentID: "public-enrollment", role: mismatch == "role" ? .reviewer : .member,
            invitationHash: String(repeating: "a", count: 64), generation: UUID(),
            phase: mismatch == "pending" ? .pending : .confirmed, checkedAt: 1_000,
            membershipRevision: mismatch == "pending" ? nil : 1)
    }
    func close() { calls.append("close") }
    func finish() { let saved = waiter; waiter = nil; saved?.resume() }
}

@MainActor struct TeamMembershipScreenTests {
    private func waitFor(_ call: String, in service: MembershipScreenService) async throws {
        for _ in 0..<200 {
            if await service.calls.contains(call) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic screen operation did not start")
    }
    @Test func explicitReviewAndUncheckedConsentPrecedeOneJoin() async throws {
        let service = MembershipScreenService(), model = try TeamMembershipScreenModel(service: service)
        #expect(model.stage == .ready && model.canReview && !model.canJoin && !model.agreed)
        #expect(await service.calls.isEmpty)
        await model.join(); #expect(await service.calls.isEmpty)
        await model.review()
        #expect(model.stage == .consent && !model.agreed && !model.canJoin)
        #expect(model.details?.teamID == "public-team")
        await model.join(); #expect(await service.calls == ["review"])
        model.setAgreement(true)
        #expect(model.canJoin)
        await model.join()
        #expect(model.stage == .confirmed && !model.agreed && !model.canJoin)
        await model.join(); await model.review(); await model.checkMembership()
        #expect(await service.calls == ["review", "join"])
        model.close(); await model.waitForCleanup()
    }
    @Test func unknownJoinOffersOnlyExplicitReadOnlyRecoveryAndKeepsUncertaintyOnError() async throws {
        let service = MembershipScreenService(failure: "join"), model = try TeamMembershipScreenModel(service: service)
        await model.review(); model.setAgreement(true); await model.join()
        #expect(model.stage == .uncertain && model.canCheck && !model.canReview && !model.canJoin)
        model.setAgreement(true); await model.join(); await model.review()
        #expect(await service.calls == ["review", "join"])
        await service.configure(failure: "recover"); await model.checkMembership()
        #expect(model.stage == .uncertain && model.canCheck)
        await service.configure(); await model.checkMembership()
        #expect(model.stage == .confirmed)
        #expect(await service.calls == ["review", "join", "recover", "recover"])
        model.close(); await model.waitForCleanup()
    }
    @Test func savedMembershipStartsWithCheckAndNeverAccountOrJoinActions() async throws {
        let service = MembershipScreenService(recovery: true), model = try TeamMembershipScreenModel(service: service)
        #expect(model.canCheck && !model.canReview && !model.canJoin)
        await model.review(); await model.join(); #expect(await service.calls.isEmpty)
        await model.checkMembership()
        #expect(model.stage == .confirmed)
        #expect(await service.calls == ["recover"])
        model.close(); await model.waitForCleanup()
    }
    @Test func reviewFailureCanOnlyRepeatReadOnlyReview() async throws {
        let service = MembershipScreenService(failure: "review"), model = try TeamMembershipScreenModel(service: service)
        await model.review()
        #expect(model.stage == .reviewFailed && model.canReview && !model.canCheck)
        await service.configure(); await model.review()
        #expect(model.stage == .consent && !model.agreed)
        #expect(await service.calls == ["review", "review"])
        model.close(); await model.waitForCleanup()
    }
    @Test func existingJoinOffersTokenlessCheckInsteadOfReviewLoop() async throws {
        let service = MembershipScreenService(failure: "existing"), model = try TeamMembershipScreenModel(service: service)
        await model.review()
        #expect(model.stage == .uncertain && model.canCheck && !model.canReview && !model.canJoin)
        await model.review(); model.setAgreement(true); await model.join()
        #expect(await service.calls == ["review"])
        await model.checkMembership()
        #expect(model.stage == .confirmed)
        #expect(await service.calls == ["review", "recover"])
        model.close(); await model.waitForCleanup()
    }
    @Test func mismatchedPreviewCannotEnableConsentAndMismatchedResultsStayUncertain() async throws {
        for field in ["account", "team", "role"] {
            let service = MembershipScreenService(mismatch: field), model = try TeamMembershipScreenModel(service: service)
            await model.review()
            #expect(model.stage == .reviewFailed && model.details == nil && !model.canJoin)
            model.close(); await model.waitForCleanup()
        }
        for field in ["account", "team", "role", "pending"] {
            let service = MembershipScreenService(), model = try TeamMembershipScreenModel(service: service)
            await model.review(); model.setAgreement(true)
            await service.configure(mismatch: field); await model.join()
            #expect(model.stage == .uncertain && !model.canJoin)
            model.close(); await model.waitForCleanup()
        }
    }
    @Test func closeImmediatelyClearsUIAndRejectsEveryLateOutcome() async throws {
        for step in ["review", "join", "recover"] {
            let service = MembershipScreenService(recovery: step == "recover", gate: step)
            let model = try TeamMembershipScreenModel(service: service)
            if step == "join" { await model.review(); model.setAgreement(true) }
            let work = Task {
                switch step { case "review": await model.review(); case "join": await model.join(); default: await model.checkMembership() }
            }
            try await waitFor(step, in: service)
            #expect(model.isWorking)
            model.close()
            #expect(model.stage == .closed && model.details == nil && !model.agreed)
            await service.finish(); await work.value; await model.waitForCleanup()
            #expect(model.stage == .closed && model.details == nil)
            await model.review(); await model.join(); await model.checkMembership()
            model.close(); await model.waitForCleanup()
            #expect((await service.calls).filter { $0 == "close" }.count == 1)
        }
    }
    @Test func cancelledCallerNeverShowsLateSuccess() async throws {
        let service = MembershipScreenService(gate: "review"), model = try TeamMembershipScreenModel(service: service)
        let work = Task { await model.review() }
        try await waitFor("review", in: service)
        work.cancel(); await service.finish(); await work.value
        #expect(model.stage == .reviewFailed && model.details == nil && !model.canJoin)
        model.close(); await model.waitForCleanup()
    }
    @Test func preCancelledCallerAndAgreementOutsideReviewMakeNoRequests() async throws {
        let service = MembershipScreenService(), model = try TeamMembershipScreenModel(service: service)
        model.setAgreement(true)
        #expect(!model.agreed)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.review()
        }
        await cancelled.value
        #expect(await service.calls.isEmpty)
        #expect(model.stage == .ready)
        model.close(); await model.waitForCleanup()
    }
}
