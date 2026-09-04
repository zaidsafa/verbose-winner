import CryptoKit
import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private let membershipCode = String(repeating: "E", count: 42) + "A"
private final class MembershipClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TeamSignInMoment(wallTime: 1_000, instant: .now)
    func now() -> TeamSignInMoment { lock.withLock { value } }
    func advance(wall: Int64 = 0, elapsed: Duration = .zero) {
        lock.withLock { value = .init(wallTime: value.wallTime + wall, instant: value.instant.advanced(by: elapsed)) }
    }
}
private final class MembershipHooks: @unchecked Sendable {
    private let lock = NSLock()
    private var actions = [String: @Sendable () throws -> Void]()
    func once(_ stage: String, _ action: @escaping @Sendable () throws -> Void) { lock.withLock { actions[stage] = action } }
    func call(_ stage: String) throws { try lock.withLock { actions.removeValue(forKey: stage) }?() }
}
private actor MembershipDevices: TeamMembershipDevices {
    private var value: TeamDeviceSnapshot?
    let hooks: MembershipHooks
    private(set) var reads = 0
    init(_ value: TeamDeviceSnapshot, hooks: MembershipHooks) { self.value = value; self.hooks = hooks }
    func load(scope: TeamDeviceScope) throws -> TeamDeviceSnapshot? { reads += 1; try hooks.call("deviceLoad"); return value }
    func requireCurrent(_ expected: TeamDeviceSnapshot) throws {
        try hooks.call("deviceCheck")
        guard value?.scope == expected.scope, value?.generation == expected.generation else { throw TeamDeviceCustodyError.staleOperation }
    }
    func remove() { value = nil }
    func rotate() {
        guard let old = value else { return }
        value = .init(scope: old.scope, deviceID: old.deviceID, generation: UUID(), phase: old.phase,
            observedAt: old.observedAt, publicKey: old.publicKey, proofExpiresAt: old.proofExpiresAt, enrollmentID: old.enrollmentID)
    }
}
private struct MembershipMetadata: TeamMembershipMetadata {
    let store: TeamJoinStore
    let hooks: MembershipHooks
    func load(scope: TeamDeviceScope, teamID: String) throws -> TeamJoinSnapshot? {
        let value = try store.load(scope: scope, teamID: teamID); try hooks.call("metadataLoad"); return value
    }
    func requireCurrent(_ expected: TeamJoinSnapshot) throws { try store.requireCurrent(expected); try hooks.call("metadataCheck") }
    func begin(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole,
               expiresAt: Int64, registration: TeamRegisteredDevice, consent: Bool) throws -> TeamJoinSnapshot {
        try hooks.call("beforeBegin")
        let value = try store.begin(scope: scope, token: token, teamID: teamID, role: role, expiresAt: expiresAt, registration: registration, consent: consent)
        try hooks.call("afterBegin"); return value
    }
    func beginRecovery(_ expected: TeamJoinSnapshot) throws -> TeamJoinSnapshot {
        let value = try store.beginRecovery(expected); try hooks.call("afterRecovery"); return value
    }
    func retryCandidate(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole) throws -> TeamJoinSnapshot {
        let value = try store.retryCandidate(scope: scope, token: token, teamID: teamID, role: role)
        try hooks.call("retryCandidate"); return value
    }
    func beginExplicitRetry(_ expected: TeamJoinSnapshot, token: String, consentExpiresAt: Int64,
                            registration: TeamRegisteredDevice, consent: Bool) throws -> TeamJoinSnapshot {
        try hooks.call("beforeRetry")
        let value = try store.beginExplicitRetry(expected, token: token, consentExpiresAt: consentExpiresAt,
            registration: registration, consent: consent)
        try hooks.call("afterRetry"); return value
    }
    func confirm(_ expected: TeamJoinSnapshot, result: TeamMembership) throws -> TeamJoinSnapshot {
        let value = try store.confirm(expected, result: result); try hooks.call("afterConfirm"); return value
    }
}
private actor MembershipTransport: TeamMembershipTransport {
    let registration: TeamRegisteredDevice
    let hooks: MembershipHooks
    private(set) var calls = [String]()
    private var failure: String?
    private var absent = false
    private var foreign = false
    private var foreignCurrent = false
    private var accepted = false
    private var gate: String?
    private var waiter: CheckedContinuation<Void, Never>?
    init(registration: TeamRegisteredDevice, hooks: MembershipHooks) { self.registration = registration; self.hooks = hooks }
    func configure(failure: String? = nil, absent: Bool = false, foreign: Bool = false, foreignCurrent: Bool = false, accepted: Bool = false, gate: String? = nil) {
        self.failure = failure; self.absent = absent; self.foreign = foreign; self.foreignCurrent = foreignCurrent; self.gate = gate
        self.accepted = accepted
    }
    private func step(_ stage: String) async throws {
        calls.append(stage)
        if gate == stage { await withCheckedContinuation { waiter = $0 } }
        try hooks.call(stage)
        if failure == stage { throw TeamAuthHTTPError.server(.uncertain) }
    }
    func finish() { let saved = waiter; waiter = nil; saved?.resume() }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice? {
        try await step("lookup")
        #expect(expected.accountID == ticket.accountID && expected.keyThumbprint == key.thumbprint)
        if absent { return nil }
        if foreign { return .init(enrollmentID: "foreign", accountID: registration.accountID, deviceID: registration.deviceID,
            keyThumbprint: registration.keyThumbprint, authorityEpoch: registration.authorityEpoch) }
        return registration
    }
    func acceptInvitation(token: String, teamID: String, enrollmentID: String, role: TeamInvitationRole, ticket: TeamAccountAccessTicket) async throws -> TeamMembership {
        try await step("accept")
        #expect(token == membershipCode && role == .reviewer)
        return .init(teamID: teamID, accountID: ticket.accountID, enrollmentID: enrollmentID, role: .reviewer, revision: 1)
    }
    func currentTeam(teamID: String, enrollmentID: String, ticket: TeamAccountAccessTicket) async throws -> TeamMembership {
        try await step("current")
        return .init(teamID: teamID, accountID: ticket.accountID, enrollmentID: enrollmentID, role: foreignCurrent ? .owner : .reviewer, revision: 1)
    }
    func lookupInvitationAcceptance(token: String, teamID: String, enrollmentID: String, role: TeamInvitationRole,
                                    ticket: TeamAccountAccessTicket) async throws -> TeamMembership? {
        try await step("acceptance")
        #expect(token == membershipCode && role == .reviewer)
        guard accepted else { return nil }
        return .init(teamID: teamID, accountID: ticket.accountID, enrollmentID: enrollmentID, role: foreignCurrent ? .owner : .reviewer, revision: 1)
    }
}
private final class MembershipCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func finish() { lock.withLock { done = true } }
    var finished: Bool { lock.withLock { done } }
}
private struct MembershipInvitation: TeamInvitationAccountTransport {
    func previewInvitation(token: String) async throws -> TeamInvitationPreview {
        .init(inviteID: "public-invite", teamID: "public-team", role: .reviewer, expiresAt: 400_000)
    }
    func invitedChallenge(providerID: String, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthChallenge {
        Issue.record("Existing account must not request provider challenge"); throw TeamAuthHTTPError.invalidRequest
    }
    func invitedExchange(_ submission: TeamNativeLoginSubmission, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthSessionPair {
        Issue.record("Existing account must not exchange provider proof"); throw TeamAuthHTTPError.invalidRequest
    }
}
private struct MembershipSessionKeychain: TeamAccountSessionKeychain {
    let backing: SessionMemoryKeychain
    let hooks: MembershipHooks
    func add(_ attributes: [String: Any]) -> OSStatus { backing.add(attributes) }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus { backing.update(query, attributes) }
    func delete(_ query: [String: Any]) -> OSStatus { backing.delete(query) }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        do { try hooks.call("accountRead") }
        catch { Issue.record("Synthetic account read hook failed"); return (errSecNotAvailable, nil) }
        return backing.copy(query)
    }
}
private struct MembershipFixture {
    let clock = MembershipClock()
    let hooks = MembershipHooks()
    let scope: TeamAccountSessionScope
    let deviceScope: TeamDeviceScope
    let sessions: TeamAccountSessionStore
    let account: TeamAccountAccessTicket
    let devices: MembershipDevices
    let store: TeamJoinStore
    let metadata: MembershipMetadata
    let backend = SessionMemoryKeychain()
    let transport: MembershipTransport
    let pair: TeamAuthSessionPair
    init(accessExpiresAt: Int64 = 900_000) throws {
        pair = .init(accountID: "public-account", sessionID: "public-session",
            accessToken: String(repeating: "A", count: 43), refreshToken: String(repeating: "B", count: 42) + "A",
            accessExpiresAt: accessExpiresAt, sessionExpiresAt: 2_000_000)
        scope = try .init(origin: URL(string: "https://pinbook.example")!, providerID: "public-ios")
        sessions = .init(testService: "membership-session", keychain: MembershipSessionKeychain(backing: SessionMemoryKeychain(), hooks: hooks))
        account = try .init(snapshot: sessions.saveInitial(pair, scope: scope, now: 1_000, consent: true))
        deviceScope = try .init(audience: "https://pinbook.example", accountID: pair.accountID, authorityEpoch: "public-epoch")
        let key = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        devices = .init(.init(scope: deviceScope, deviceID: "public-device", generation: UUID(), phase: .registered,
            observedAt: 1_000, publicKey: key, proofExpiresAt: nil, enrollmentID: "public-enrollment"), hooks: hooks)
        store = .init(storage: try KeychainTeamJoinMetadata(testService: "pinbook.join-test.membership", keychain: backend), clock: { [clock] in clock.now().wallTime })
        metadata = .init(store: store, hooks: hooks)
        transport = .init(registration: .init(enrollmentID: "public-enrollment", accountID: pair.accountID,
            deviceID: "public-device", keyThumbprint: key.thumbprint, authorityEpoch: deviceScope.authorityEpoch), hooks: hooks)
    }
    func owner() throws -> TeamMembershipJoin {
        try .init(account: account, authorityEpoch: deviceScope.authorityEpoch, sessions: sessions, devices: devices,
            metadata: metadata, transport: transport, clock: { clock.now() })
    }
    func intent() async throws -> TeamInviteJoinIntent {
        let flow = TeamInvitedSignIn(provider: .apple, scope: scope, sessions: sessions, identity: SyntheticAppleIdentity(),
            transport: MembershipInvitation(), clock: { clock.now() })
        let display = try await flow.preview(code: membershipCode)
        return try await flow.existingAccountIntent(display)
    }
    func saved() throws -> TeamJoinSnapshot? { try store.load(scope: deviceScope, teamID: "public-team") }
    func seedPending() async throws -> TeamJoinSnapshot {
        try store.begin(scope: deviceScope, token: membershipCode, teamID: "public-team", role: .reviewer,
            expiresAt: 400_000, registration: transport.registration, consent: true)
    }
    func signOut() throws { try sessions.removeCurrent(scope: scope, consent: true) }
}

struct TeamMembershipJoinTests {
    @MainActor @Test func retryScreenBridgeUsesRealOwnerAndDurableSameIdentityConsent() async throws {
        for accepted in [false, true] {
            let f = try MembershipFixture(), original = try await f.seedPending()
            await f.transport.configure(accepted: accepted)
            let bridge = try TeamMembershipScreenBridge(owner: f.owner(), accountID: f.account.accountID,
                teamID: original.teamID, originalInvitationToken: membershipCode, role: original.role)
            let model = try TeamMembershipScreenModel(service: bridge)
            #expect(await f.transport.calls.isEmpty)
            #expect(f.backend.writes == 1 && model.context.isRetry)
            await model.review()
            #expect(await f.transport.calls == ["lookup", "acceptance"])
            if accepted {
                #expect(model.stage == .confirmed && !model.canJoin && f.backend.writes == 3)
                await #expect(throws: TeamMembershipJoinError.invalidated) { try await bridge.review() }
            } else {
                #expect(model.stage == .consent && !model.agreed && !model.canJoin && f.backend.writes == 2)
                await model.join()
                #expect(await f.transport.calls == ["lookup", "acceptance"])
                model.setAgreement(true); await model.join()
                #expect(model.stage == .confirmed && f.backend.writes == 4)
                #expect(await f.transport.calls == ["lookup", "acceptance", "lookup", "accept"])
            }
            let saved = try #require(try f.saved())
            #expect(saved.phase == .confirmed && saved.invitationHash == original.invitationHash)
            #expect(saved.enrollmentID == original.enrollmentID && saved.role == original.role)
            #expect(!String(decoding: try #require(f.backend.bytes), as: UTF8.self).contains(membershipCode))
            model.close(); await model.waitForCleanup()
            await #expect(throws: TeamMembershipJoinError.invalidated) { try await bridge.review() }
        }
    }
    @MainActor @Test func retryBridgeConsumesOriginalCodeBeforeUncertainAttemptAndPreservesRecovery() async throws {
        let f = try MembershipFixture(), original = try await f.seedPending()
        let bridge = try TeamMembershipScreenBridge(owner: f.owner(), accountID: f.account.accountID,
            teamID: original.teamID, originalInvitationToken: membershipCode, role: original.role)
        let model = try TeamMembershipScreenModel(service: bridge)
        await model.review(); model.setAgreement(true)
        await f.transport.configure(failure: "accept"); await model.join()
        #expect(model.stage == .uncertain && model.canCheck && !model.canJoin && !model.canReview)
        #expect(try f.saved()?.phase == .pending)
        await #expect(throws: TeamMembershipJoinError.invalidated) { try await bridge.review() }
        await f.transport.configure(); await model.checkMembership()
        #expect(model.stage == .confirmed)
        #expect((await f.transport.calls).filter { $0 == "accept" }.count == 1)
        model.close(); await model.waitForCleanup()
    }
    @MainActor @Test func retryScreenCannotTurnWrongOriginalCodeOrAccountIntoConsent() async throws {
        for mismatch in ["code", "account"] {
            let f = try MembershipFixture(), original = try await f.seedPending()
            let bridge = try TeamMembershipScreenBridge(owner: f.owner(),
                accountID: mismatch == "account" ? "foreign" : f.account.accountID, teamID: original.teamID,
                originalInvitationToken: mismatch == "code" ? String(repeating: "F", count: 42) + "A" : membershipCode,
                role: original.role)
            let model = try TeamMembershipScreenModel(service: bridge)
            await model.review()
            #expect(model.stage == .reviewFailed && !model.canJoin && model.details == nil)
            #expect(!(await f.transport.calls).contains("accept"))
            #expect(try f.saved()?.phase == .pending)
            model.close(); await model.waitForCleanup()
        }
    }

    private func retryPreview(_ f: MembershipFixture, _ owner: TeamMembershipJoin) async throws -> TeamMembershipJoinPreview {
        guard case .ready(let display) = try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) else {
            Issue.record("Expected synthetic eligible-pending consent"); throw TeamMembershipJoinError.invalidIntent
        }
        return display
    }
    @Test func eligiblePendingRequiresFreshConsentAndOneDurableSameIdentityRetry() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), original = try await f.seedPending()
        let display = try await retryPreview(f, owner), checked = try #require(try f.saved())
        #expect(checked.phase == .pending && checked.generation != original.generation && f.backend.writes == 2)
        #expect(await f.transport.calls == ["lookup", "acceptance"])
        await #expect(throws: TeamMembershipJoinError.consentRequired) { try await owner.join(display, consent: false) }
        #expect(f.backend.writes == 2)
        let result = try await owner.join(display, consent: true)
        #expect(result.phase == .confirmed && result.invitationHash == original.invitationHash)
        #expect(result.enrollmentID == original.enrollmentID && f.backend.writes == 4)
        #expect(await f.transport.calls == ["lookup", "acceptance", "lookup", "accept"])
        await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(display, consent: true) }
        #expect(!String(decoding: try #require(f.backend.bytes), as: UTF8.self).contains(membershipCode))
    }
    @Test func acceptedOriginalInvitationRecoversAfterExpiryWithoutAnotherAccept() async throws {
        let f = try MembershipFixture(), original = try await f.seedPending()
        f.clock.advance(wall: 500_000, elapsed: .seconds(500))
        let owner = try f.owner()
        await f.transport.configure(accepted: true)
        guard case .joined(let result) = try await owner.prepareRetry(token: membershipCode, teamID: original.teamID, role: original.role) else {
            Issue.record("Accepted original invitation must reconcile, not offer retry"); return
        }
        #expect(result.phase == .confirmed && result.enrollmentID == original.enrollmentID)
        #expect(await f.transport.calls == ["lookup", "acceptance"])
    }
    @Test func retryRejectsDifferentInvitationRoleMissingRecordAndForeignRegistration() async throws {
        for mode in ["token", "role", "missing", "registration", "account"] {
            let f = try MembershipFixture(), owner = try f.owner()
            if mode != "missing" { _ = try await f.seedPending() }
            if mode == "registration" { await f.transport.configure(foreign: true) }
            if mode == "account" { try f.signOut() }
            do {
                _ = try await owner.prepareRetry(token: mode == "token" ? String(repeating: "A", count: 43) : membershipCode,
                    teamID: "public-team", role: mode == "role" ? .member : .reviewer)
                Issue.record("Invalid retry binding accepted")
            } catch { #expect(error is TeamJoinError || error is TeamMembershipJoinError || error is TeamAccountSessionError) }
            #expect(!(await f.transport.calls).contains("acceptance"))
            #expect(!(await f.transport.calls).contains("accept"))
            #expect(f.backend.writes == (mode == "missing" ? 0 : 1))
        }
    }
    @Test func uncertainStatusOrMarkerWritePreservesPendingWithoutAccept() async throws {
        for afterWrite in [false, true] {
            let f = try MembershipFixture(), owner = try f.owner(), original = try await f.seedPending()
            if afterWrite { f.hooks.once("afterRecovery") { throw TeamJoinError.unavailable(errSecNotAvailable) } }
            else { await f.transport.configure(failure: "acceptance") }
            do { _ = try await retryPreview(f, owner); Issue.record("Unknown status cannot arm consent") }
            catch { #expect(error is TeamJoinError || error is TeamMembershipJoinError) }
            let saved = try #require(try f.saved())
            #expect(saved.phase == .pending && saved.generation != original.generation)
            #expect(!(await f.transport.calls).contains("accept"))
            #expect((await f.transport.calls).contains("acceptance") == !afterWrite)
        }
    }
    @Test func concurrentLocalRecoveryAndForeignStatusCannotArmRetryConsent() async throws {
        for accepted in [false, true] {
            let f = try MembershipFixture(), owner = try f.owner()
            _ = try await f.seedPending()
            await f.transport.configure(accepted: accepted)
            f.hooks.once("acceptance") { _ = try f.store.beginRecovery(#require(try f.saved())) }
            await #expect(throws: TeamJoinError.staleOperation) { try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) }
            #expect(try f.saved()?.phase == .pending)
            #expect(!(await f.transport.calls).contains("accept"))
        }
        let f = try MembershipFixture(), owner = try f.owner()
        _ = try await f.seedPending()
        await f.transport.configure(foreignCurrent: true, accepted: true)
        await #expect(throws: TeamJoinError.bindingMismatch) { try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) }
        #expect(try f.saved()?.phase == .pending)
    }
    @Test func retryChecksAccountAfterSlowCandidateRecoveryLookupAndCommit() async throws {
        for stage in ["retryCandidate", "afterRecovery", "acceptance", "beforeRetry", "afterRetry", "afterConfirm"] {
            let f = try MembershipFixture(), owner = try f.owner()
            _ = try await f.seedPending()
            let joining = ["beforeRetry", "afterRetry", "afterConfirm"].contains(stage)
            let display = joining ? try await retryPreview(f, owner) : nil
            f.hooks.once(stage) { try f.signOut() }
            do {
                if let display { _ = try await owner.join(display, consent: true) }
                else { _ = try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) }
                Issue.record("Retry returned current success after account change")
            } catch { #expect(error is TeamAccountSessionError) }
            #expect((await f.transport.calls).filter { $0 == "accept" }.count == (stage == "afterConfirm" ? 1 : 0))
            #expect(try f.saved()?.phase == (stage == "afterConfirm" ? .confirmed : .pending))
        }
    }
    @Test func retryConsentExpiresAndDeviceChangeOrSlowCommitPreventsDispatch() async throws {
        for mode in ["wall", "monotonic", "device", "commit", "recovery"] {
            let f = try MembershipFixture(), owner = try f.owner()
            _ = try await f.seedPending()
            let display = try await retryPreview(f, owner)
            switch mode {
            case "wall": f.clock.advance(wall: 300_000)
            case "monotonic": f.clock.advance(elapsed: .seconds(300))
            case "device": await f.devices.rotate()
            case "commit": f.hooks.once("afterRetry") { f.clock.advance(elapsed: .seconds(125)) }
            default: _ = try await owner.recover(teamID: "public-team")
            }
            do { _ = try await owner.join(display, consent: true); Issue.record("Stale retry was dispatched") }
            catch { #expect(error is TeamMembershipJoinError || error is TeamDeviceCustodyError) }
            #expect(!(await f.transport.calls).contains("accept"))
        }
    }
    @Test func cancelledLateAcceptanceStatusRetainsBusyAndNeverConfirmsOrArmsRetry() async throws {
        let f = try MembershipFixture(), owner = try f.owner()
        _ = try await f.seedPending()
        await f.transport.configure(accepted: true, gate: "acceptance")
        let task = Task { try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) }
        for _ in 0..<200 {
            if await f.transport.calls.contains("acceptance") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await f.transport.calls.contains("acceptance"))
        await owner.cancelPendingMembership()
        await #expect(throws: TeamMembershipJoinError.busy) { try await owner.recover(teamID: "public-team") }
        await f.transport.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try f.saved()?.phase == .pending)
        #expect(!(await f.transport.calls).contains("accept"))
    }
    @Test func lostExplicitRetryResponseKeepsUncertaintyAndSpentConsent() async throws {
        let f = try MembershipFixture(), owner = try f.owner()
        _ = try await f.seedPending()
        let display = try await retryPreview(f, owner)
        await f.transport.configure(failure: "accept")
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.join(display, consent: true) }
        #expect(try f.saved()?.phase == .pending)
        await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(display, consent: true) }
        await f.transport.configure(accepted: true)
        guard case .joined = try await owner.prepareRetry(token: membershipCode, teamID: "public-team", role: .reviewer) else {
            Issue.record("Later accepted status should reconcile"); return
        }
        #expect((await f.transport.calls).filter { $0 == "accept" }.count == 1)
    }
    @MainActor @Test func screenBridgeComposesRealOwnerStoreAndReadOnlyRecovery() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), intent = try await f.intent()
        let bridge = TeamMembershipScreenBridge(owner: owner, invitation: intent)
        let model = try TeamMembershipScreenModel(service: bridge)
        #expect(await f.transport.calls.isEmpty)
        await model.review()
        #expect(model.stage == .consent && !model.agreed && f.backend.writes == 0)
        model.setAgreement(true)
        await f.transport.configure(failure: "accept"); await model.join()
        #expect(model.stage == .uncertain && !model.canJoin)
        #expect(try f.saved()?.phase == .pending)
        await f.transport.configure(); await model.checkMembership()
        #expect(model.stage == .confirmed)
        #expect(try f.saved()?.phase == .confirmed)
        #expect(await f.transport.calls == ["lookup", "lookup", "accept", "lookup", "current"])
        model.close(); await model.waitForCleanup()
        #expect(model.stage == .closed)
        await #expect(throws: TeamMembershipJoinError.invalidated) { try await bridge.review() }

        let reopened = try TeamMembershipScreenModel(service: TeamMembershipScreenBridge(owner: f.owner(), invitation: intent))
        await reopened.review()
        #expect(reopened.stage == .uncertain && reopened.canCheck && !reopened.canReview && !reopened.canJoin)
        await reopened.checkMembership()
        #expect(reopened.stage == .confirmed)
        #expect((await f.transport.calls).filter { $0 == "accept" }.count == 1)
        reopened.close(); await reopened.waitForCleanup()
    }
    @Test func preparationIsReadOnlyAndSeparateConsentDispatchesOnce() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), intent = try await f.intent()
        let display = try await owner.prepare(intent)
        #expect(display.teamID == "public-team" && display.accountID == f.account.accountID && display.role == .reviewer)
        #expect(f.backend.writes == 0)
        await #expect(throws: TeamMembershipJoinError.consentRequired) { try await owner.join(display, consent: false) }
        #expect(await f.transport.calls == ["lookup"])
        let saved = try await owner.join(display, consent: true)
        #expect(saved.phase == .confirmed && saved.membershipRevision == 1)
        #expect(await f.transport.calls == ["lookup", "lookup", "accept"])
        #expect(f.backend.writes == 2)
        await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(display, consent: true) }
        await #expect(throws: TeamMembershipJoinError.recoveryRequired) { try await owner.prepare(intent) }
        #expect(f.backend.writes == 2)
    }
    @Test func replacedCrossOwnerAndCancelledPreviewsCannotJoin() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), other = try f.owner(), intent = try await f.intent()
        let first = try await owner.prepare(intent), foreign = try await other.prepare(intent)
        let next = try await owner.prepare(intent)
        for display in [first, foreign] {
            await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(display, consent: true) }
        }
        await owner.cancelPendingMembership()
        await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(next, consent: true) }
        #expect(f.backend.writes == 0)
    }
    @Test func unknownAcceptRecoversAfterProcessRestartAndInvitationExpiryWithoutReplay() async throws {
        let f = try MembershipFixture(), owner = try f.owner()
        let display = try await owner.prepare(f.intent())
        await f.transport.configure(failure: "accept")
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.join(display, consent: true) }
        let pending = try #require(try f.saved())
        #expect(pending.phase == .pending)
        #expect(!String(decoding: try #require(f.backend.bytes), as: UTF8.self).contains(membershipCode))
        await #expect(throws: TeamMembershipJoinError.staleConsent) { try await owner.join(display, consent: true) }
        await owner.close()
        f.clock.advance(wall: 500_000, elapsed: .seconds(500))
        await f.transport.configure()
        let reopened = try f.owner(), saved = try await reopened.recover(teamID: pending.teamID)
        #expect(saved.phase == .confirmed && saved.generation != pending.generation)
        #expect(await f.transport.calls == ["lookup", "lookup", "accept", "lookup", "current"])
    }
    @Test func accountOrDeviceReplacementInvalidatesEvenIdenticalAccountTokens() async throws {
        for what in ["account", "device"] {
            let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
            if what == "account" { try f.signOut(); _ = try f.sessions.saveInitial(f.pair, scope: f.scope, now: 1_000, consent: true) }
            else { await f.devices.rotate() }
            do { _ = try await owner.join(display, consent: true); Issue.record("Accepted stale generation") }
            catch { #expect(error is TeamAccountSessionError || error is TeamDeviceCustodyError) }
            #expect(f.backend.writes == 0)
            #expect(await f.transport.calls == ["lookup"])
        }
    }
    @Test func membershipConsentExpiresOnEitherClockAndRejectsRollback() async throws {
        for kind in ["wall", "monotonic", "rollback"] {
            let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
            if kind == "wall" { f.clock.advance(wall: 300_000) }
            if kind == "monotonic" { f.clock.advance(elapsed: .seconds(300)) }
            if kind == "rollback" { f.clock.advance(wall: -1) }
            do { _ = try await owner.join(display, consent: true); Issue.record("Accepted expired consent") }
            catch { #expect(error is TeamMembershipJoinError || error is TeamAccountSessionError) }
            #expect(f.backend.writes == 0)
            #expect(await f.transport.calls == ["lookup"])
        }
    }
    @Test func missingOrForeignRegistrationCannotCreateIntent() async throws {
        for mode in ["missing-device", "null", "foreign", "denied"] {
            let f = try MembershipFixture(), owner = try f.owner(), intent = try await f.intent()
            if mode == "missing-device" { await f.devices.remove() }
            await f.transport.configure(failure: mode == "denied" ? "lookup" : nil, absent: mode == "null", foreign: mode == "foreign")
            do { _ = try await owner.prepare(intent); Issue.record("Accepted unavailable registration") }
            catch { #expect(error is TeamMembershipJoinError) }
            #expect(f.backend.writes == 0)
            #expect(!(await f.transport.calls).contains("accept"))
        }
    }
    @Test func uncertainMarkerCommitNeverDispatchesAccept() async throws {
        for stage in ["beforeBegin", "afterBegin"] {
            let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
            f.hooks.once(stage) { throw TeamJoinError.unavailable(errSecNotAvailable) }
            await #expect(throws: TeamJoinError.unavailable(errSecNotAvailable)) { try await owner.join(display, consent: true) }
            #expect((try f.saved() != nil) == (stage == "afterBegin"))
            #expect(await f.transport.calls == ["lookup", "lookup"])
        }
    }
    @Test func signOutAfterSlowChecksWritesAndConfirmationNeverReturnsAuthority() async throws {
        for stage in ["deviceCheck", "lookup", "afterBegin", "afterConfirm"] {
            let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
            f.hooks.once(stage) { try f.signOut() }
            do { _ = try await owner.join(display, consent: true); Issue.record("Returned success after sign-out") }
            catch { #expect(error is TeamAccountSessionError) }
            let record = try f.saved()
            if stage == "afterConfirm" { #expect(record?.phase == .confirmed) }
            else if stage == "afterBegin" { #expect(record?.phase == .pending) }
            else { #expect(record == nil) }
            #expect((await f.transport.calls).filter { $0 == "accept" }.count == (stage == "afterConfirm" ? 1 : 0))
        }
    }
    @Test func monotonicDeadlineDuringMarkerWriteKeepsPendingWithoutDispatch() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
        f.hooks.once("afterBegin") { f.clock.advance(elapsed: .seconds(125)) }
        await #expect(throws: TeamMembershipJoinError.expired) { try await owner.join(display, consent: true) }
        #expect(try f.saved()?.phase == .pending)
        #expect(await f.transport.calls == ["lookup", "lookup"])
    }
    @Test func cancelledLateAcceptRetainsBusyAndPendingWithoutLateConfirmation() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), intent = try await f.intent(), display = try await owner.prepare(intent)
        await f.transport.configure(gate: "accept")
        let task = Task { try await owner.join(display, consent: true) }
        for _ in 0..<200 {
            if await f.transport.calls.contains("accept") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await f.transport.calls.contains("accept"))
        await owner.cancelPendingMembership()
        await #expect(throws: TeamMembershipJoinError.busy) { try await owner.prepare(intent) }
        await f.transport.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try f.saved()?.phase == .pending)
        await owner.close()
        await #expect(throws: TeamMembershipJoinError.invalidated) { try await owner.recover(teamID: "public-team") }
    }
    @Test func deniedRecoveryPreservesIntentAndNeverResendsAccept() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
        await f.transport.configure(failure: "accept")
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.join(display, consent: true) }
        let original = try #require(try f.saved())
        await f.transport.configure(failure: "lookup")
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.recover(teamID: original.teamID) }
        #expect(try f.saved() == original)
        await f.transport.configure(failure: "current")
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.recover(teamID: original.teamID) }
        #expect(try f.saved()?.phase == .pending)
        #expect(try f.saved()?.generation != original.generation)
        #expect((await f.transport.calls).filter { $0 == "accept" }.count == 1)
    }
    @Test func accessLifetimeAlsoUsesMonotonicTimeAcrossOperations() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), intent = try await f.intent()
        _ = try await owner.prepare(intent)
        f.clock.advance(elapsed: .seconds(900)) // Wall clock stalled, same owner.
        await #expect(throws: TeamMembershipJoinError.expired) { try await owner.prepare(intent) }
        #expect(await f.transport.calls == ["lookup"])
        #expect(f.backend.writes == 0)
    }
    @Test func firstSlowAccountReadCannotExtendAccessUnderStalledWallClock() async throws {
        let f = try MembershipFixture(accessExpiresAt: 6_000), owner = try f.owner(), intent = try await f.intent()
        f.hooks.once("accountRead") { f.clock.advance(elapsed: .seconds(6)) }
        await #expect(throws: TeamMembershipJoinError.expired) { try await owner.prepare(intent) }
        #expect(await f.devices.reads == 0)
        #expect(await f.transport.calls.isEmpty)
        #expect(f.backend.writes == 0)
    }
    @Test func closeWaitsForActualUncooperativeOperationBeforeCleanup() async throws {
        let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
        await f.transport.configure(gate: "accept")
        let request = Task { try await owner.join(display, consent: true) }
        for _ in 0..<200 {
            if await f.transport.calls.contains("accept") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await f.transport.calls.contains("accept"))
        let completion = MembershipCompletion()
        let closing = Task { await owner.close(); completion.finish() }
        var closed = false
        for _ in 0..<200 {
            do { _ = try await owner.recover(teamID: "public-team"); Issue.record("Concurrent recovery started") }
            catch TeamMembershipJoinError.invalidated { closed = true; break }
            catch { #expect(error as? TeamMembershipJoinError == .busy) }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(closed && !completion.finished)
        await f.transport.finish()
        await #expect(throws: CancellationError.self) { try await request.value }
        await closing.value
        #expect(completion.finished)
        #expect(try f.saved()?.phase == .pending)
    }
    @Test func foreignOrRegressedRecoveryResponseCannotConfirmNewAuthority() async throws {
        for foreign in [false, true] {
            let f = try MembershipFixture(), owner = try f.owner(), display = try await owner.prepare(f.intent())
            await f.transport.configure(failure: "accept")
            await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.join(display, consent: true) }
            if !foreign {
                let row = try #require(try f.saved())
                _ = try f.store.confirm(row, result: .init(teamID: row.teamID, accountID: f.account.accountID,
                    enrollmentID: row.enrollmentID, role: .reviewer, revision: 4))
            }
            await f.transport.configure(foreignCurrent: foreign)
            await #expect(throws: TeamJoinError.bindingMismatch) { try await owner.recover(teamID: "public-team") }
            #expect(try f.saved()?.membershipRevision == (foreign ? nil : 4))
            #expect((await f.transport.calls).filter { $0 == "accept" }.count == 1)
        }
    }
}
