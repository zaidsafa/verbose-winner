import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor WorkflowGate {
    private(set) var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async { started = true; await withCheckedContinuation { waiter = $0 } }
    func release() { let saved = waiter; waiter = nil; saved?.resume() }
}
private actor WorkflowAccount: TeamInvitationAccountScreenService {
    private(set) var calls = [String]()
    private var closed = false
    let failCleanup: Bool
    init(failCleanup: Bool = false) { self.failCleanup = failCleanup }
    func review() -> TeamInvitationAccountReview {
        calls.append("review"); return .init(teamID: "team", role: .member, expiresAt: 20_000, accountID: nil)
    }
    func access(_ review: TeamInvitationAccountReview, consent: Bool) throws -> TeamInvitationAccountReceipt {
        guard consent else { throw TeamInvitationAccountError.consentRequired }
        calls.append("access"); return .init(teamID: review.teamID, role: review.role, accountID: "account")
    }
    func close() throws {
        guard !closed else { return }; closed = true; calls.append("close")
        if failCleanup { throw TeamInvitationAccountError.accountUnavailable }
    }
}
private actor WorkflowMembership: TeamMembershipScreenService {
    nonisolated let context: TeamMembershipScreenContext
    private(set) var calls = [String]()
    private var closed = false
    init(mismatch: String? = nil) {
        context = .init(accountID: mismatch == "account" ? "other" : "account", teamID: mismatch == "team" ? "other" : "team",
            invitedRole: mismatch == "role" ? .reviewer : .member, isRetry: mismatch == "retry")
    }
    func review() -> TeamMembershipRetryPreparation {
        calls.append("review"); return .ready(.init(accountID: context.accountID, teamID: context.teamID, role: .member))
    }
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) throws -> TeamJoinSnapshot {
        guard consent else { throw TeamMembershipJoinError.consentRequired }; calls.append("join")
        return try .init(scope: .init(audience: "https://pinbook.example", accountID: "account", authorityEpoch: "epoch"),
            teamID: "team", enrollmentID: "enrollment", role: .member, invitationHash: String(repeating: "a", count: 64),
            generation: UUID(), phase: .confirmed, checkedAt: 1_000, membershipRevision: 1)
    }
    func recover() throws -> TeamJoinSnapshot { throw TeamMembershipJoinError.transportFailure }
    func close() { if !closed { closed = true; calls.append("close") } }
}
private actor WorkflowDevice: TeamDeviceRegistrationScreenService {
    nonisolated let context: TeamInvitationDeviceContext
    let child: WorkflowMembership
    private let gate: WorkflowGate?
    private let gateRegistration: Bool
    private var results: [TeamDeviceRegistrationScreenResult]
    private var failOnce: Bool
    private var closed = false
    private(set) var calls = [String]()
    init(results: [TeamDeviceRegistrationScreenResult] = [.registered], failOnce: Bool = false,
         mismatch: String? = nil, membershipMismatch: String? = nil, gate: WorkflowGate? = nil, gateRegistration: Bool = false) {
        context = .init(accountID: mismatch == "account" ? "other" : "account", teamID: mismatch == "team" ? "other" : "team",
            role: mismatch == "role" ? .reviewer : .member)
        self.results = results; self.failOnce = failOnce; self.gate = gate; self.gateRegistration = gateRegistration
        child = WorkflowMembership(mismatch: membershipMismatch)
    }
    func register(consent: Bool) async throws -> TeamDeviceRegistrationScreenResult {
        guard consent else { throw TeamDeviceCustodyError.consentRequired }
        calls.append("register")
        if gateRegistration { await gate?.wait() }
        if failOnce { failOnce = false; throw TeamDeviceRegistrationError.transportFailure }
        return results.isEmpty ? .registered : results.removeFirst()
    }
    func membership() async -> any TeamMembershipScreenService {
        calls.append("membership"); if !gateRegistration { await gate?.wait() }; return child
    }
    func close() { if !closed { closed = true; calls.append("close") } }
}

@MainActor struct TeamInvitationWorkflowTests {
    private func wait(_ gate: WorkflowGate) async throws {
        for _ in 0..<200 { if await gate.started { return }; try await Task.sleep(for: .milliseconds(5)) }
        Issue.record("Synthetic transition did not start")
    }
    private func model(account: WorkflowAccount = WorkflowAccount(), device: WorkflowDevice, gate: WorkflowGate? = nil) -> TeamInvitationWorkflowModel {
        .init(source: .init(account: account, device: { _ in await gate?.wait(); return device }))
    }
    private func completeAccount(_ model: TeamInvitationWorkflowModel) async {
        await model.account.review(); model.account.setAgreement(true); await model.account.access()
    }
    private func completeDevice(_ model: TeamInvitationWorkflowModel) async throws {
        await model.continueFromAccount()
        let device = try #require(model.device); device.setAgreement(true); await device.register()
    }
    @Test func deviceWaitRetryAndSuccessEachRequireFreshUncheckedConsent() async throws {
        let service = WorkflowDevice(results: [.waiting(until: 2_000), .retryReady, .registered])
        let device = try TeamDeviceRegistrationScreenModel(service: service)
        await device.register(); #expect(await service.calls.isEmpty)
        for expected in [TeamDeviceRegistrationScreenStage.waiting, .retryReady, .registered] {
            device.setAgreement(true); await device.register()
            #expect(device.stage == expected && !device.agreed && !device.canRegister)
            if expected != .registered { #expect(!device.canContinue) }
        }
        #expect(device.canContinue && device.waitUntil == nil)
        #expect(await service.calls == ["register", "register", "register"])
        device.close(); await device.waitForCleanup()
    }
    @Test func deviceErrorsAndMalformedWaitNeverAdvanceOrAutomaticallyRetry() async throws {
        for malformed in [false, true] {
            let service = WorkflowDevice(results: malformed ? [.waiting(until: 0)] : [.registered], failOnce: !malformed)
            let device = try TeamDeviceRegistrationScreenModel(service: service)
            device.setAgreement(true); await device.register()
            #expect(device.stage == .uncertain && !device.agreed && !device.canContinue)
            await device.register(); #expect(await service.calls == ["register"])
            device.setAgreement(true); await device.register(); #expect(device.canContinue)
            device.close(); await device.waitForCleanup()
        }
    }
    @Test func deviceCloseAndCancellationRejectLateResultsAndDuplicateActions() async throws {
        for close in [false, true] {
            let gate = WorkflowGate(), service = WorkflowDevice(gate: gate, gateRegistration: true)
            let device = try TeamDeviceRegistrationScreenModel(service: service)
            device.setAgreement(true); let work = Task { await device.register() }; try await wait(gate)
            device.setAgreement(true); await device.register()
            #expect(await service.calls == ["register"])
            if close { device.close() } else { work.cancel() }
            await gate.release(); await work.value
            #expect(device.stage == (close ? .closed : .uncertain) && !device.agreed && !device.canContinue)
            device.close(); await device.waitForCleanup()
        }
    }
    @Test func completeWorkflowRequiresThreeSeparateActionsAndNeverJoinsOnNavigation() async throws {
        let account = WorkflowAccount(), service = WorkflowDevice(), parent = model(account: account, device: service)
        await parent.continueFromAccount(); await parent.continueFromDevice()
        #expect(await account.calls.isEmpty)
        await completeAccount(parent)
        #expect(parent.step == .account && parent.device == nil)
        await parent.continueFromAccount()
        let device = try #require(parent.device)
        #expect(parent.step == .device && !device.agreed && !device.canContinue && parent.account.stage == .closed)
        await parent.continueFromDevice(); #expect(await service.calls.isEmpty)
        device.setAgreement(true); await device.register()
        #expect(parent.step == .device && parent.membership == nil)
        await parent.continueFromDevice()
        let member = try #require(parent.membership)
        #expect(parent.step == .membership && parent.device == nil && member.stage == .ready)
        #expect(await service.child.calls.isEmpty)
        await member.review(); #expect(!member.agreed && !member.canJoin)
        member.setAgreement(true); await member.join(); #expect(member.stage == .confirmed)
        parent.close(); await parent.waitForCleanup()
        #expect(parent.step == .closed && parent.membership == nil && !parent.cleanupFailed)
    }
    @Test func parentCloseDrainsAndClosesLateChildrenAtBothTransitionBoundaries() async throws {
        for toDevice in [true, false] {
            let gate = WorkflowGate(), service = WorkflowDevice(gate: toDevice ? nil : gate)
            let parent = model(device: service, gate: toDevice ? gate : nil)
            await completeAccount(parent)
            if !toDevice { try await completeDevice(parent) }
            let work = Task { if toDevice { await parent.continueFromAccount() } else { await parent.continueFromDevice() } }
            try await wait(gate)
            await parent.continueFromAccount(); await parent.continueFromDevice()
            parent.close(); #expect(parent.step == .closed && !parent.isTransitioning)
            await gate.release(); await work.value; await parent.waitForCleanup()
            #expect(parent.device == nil && parent.membership == nil)
            if toDevice { #expect(await service.calls == ["close"]) }
            else { #expect(await service.child.calls == ["close"]) }
        }
    }
    @Test func cancelledTransitionsCloseLateProductsInsteadOfMountingThem() async throws {
        for toDevice in [true, false] {
            let gate = WorkflowGate(), service = WorkflowDevice(gate: toDevice ? nil : gate)
            let parent = model(device: service, gate: toDevice ? gate : nil)
            await completeAccount(parent)
            if !toDevice { try await completeDevice(parent) }
            let work = Task { if toDevice { await parent.continueFromAccount() } else { await parent.continueFromDevice() } }
            try await wait(gate); work.cancel(); await gate.release(); await work.value
            #expect(parent.step == .failed && parent.device == nil && parent.membership == nil)
            if toDevice { #expect(await service.calls == ["close"]) }
            else { #expect(await service.child.calls == ["close"]) }
            parent.close(); await parent.waitForCleanup()
        }
    }
    @Test func mismatchedAccountTeamRoleOrRetryChildCannotEnterWorkflow() async throws {
        for mismatch in ["account", "team", "role", "retry"] {
            for toDevice in [true, false] where !toDevice || mismatch != "retry" {
                let service = WorkflowDevice(mismatch: toDevice ? mismatch : nil, membershipMismatch: toDevice ? nil : mismatch)
                let parent = model(device: service)
                await completeAccount(parent)
                if toDevice { await parent.continueFromAccount() }
                else { try await completeDevice(parent); await parent.continueFromDevice() }
                #expect(parent.step == .failed && parent.device == nil && parent.membership == nil)
                if toDevice { #expect(await service.calls == ["close"]) }
                else { #expect(await service.child.calls == ["close"]) }
                parent.close(); await parent.waitForCleanup()
            }
        }
    }
    @Test func accountCleanupUncertaintyPreventsDeviceScreenPublication() async {
        let service = WorkflowDevice(), parent = model(account: WorkflowAccount(failCleanup: true), device: service)
        await completeAccount(parent); await parent.continueFromAccount()
        #expect(parent.step == .failed && parent.cleanupFailed && parent.device == nil)
        #expect(await service.calls == ["close"])
        parent.close(); await parent.waitForCleanup()
    }
    @Test func externalLifecycleInvalidationClearsEveryMountedStep() async throws {
        for step in [TeamInvitationWorkflowStep.account, .device, .membership] {
            let service = WorkflowDevice(), parent = model(device: service)
            if step != .account { await completeAccount(parent); try await completeDevice(parent) }
            if step == .membership { await parent.continueFromDevice(); await parent.membership?.review(); parent.membership?.setAgreement(true) }
            parent.close(); await parent.waitForCleanup()
            await parent.continueFromAccount(); await parent.continueFromDevice()
            #expect(parent.step == .closed && parent.device == nil && parent.membership == nil && parent.account.stage == .closed)
            #expect(await !service.child.calls.contains("join"))
        }
    }
}
