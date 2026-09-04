import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private let invitationCode = String(repeating: "E", count: 42) + "A"
private let invitationPair = TeamAuthSessionPair(accountID: "public-account", sessionID: "public-session",
    accessToken: String(repeating: "C", count: 42) + "A", refreshToken: String(repeating: "D", count: 42) + "A",
    accessExpiresAt: 900_000, sessionExpiresAt: 2_000_000)
private final class InvitationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TeamSignInMoment(wallTime: 1_000, instant: .now)
    private var shiftAfterRead: (Int64, Duration)?
    func now() -> TeamSignInMoment {
        lock.withLock {
            let result = value
            if let (wall, elapsed) = shiftAfterRead {
                shiftAfterRead = nil
                value = .init(wallTime: value.wallTime + wall, instant: value.instant.advanced(by: elapsed))
            }
            return result
        }
    }
    func advanceAfterNextRead(wall: Int64, elapsed: Duration) { lock.withLock { shiftAfterRead = (wall, elapsed) } }
    func advance(wall: Int64 = 0, elapsed: Duration = .zero) {
        lock.withLock { value = .init(wallTime: value.wallTime + wall, instant: value.instant.advanced(by: elapsed)) }
    }
}
private actor InvitationTransport: TeamInvitationAccountTransport {
    private(set) var calls = [String]()
    private(set) var bindings = [(String, String, TeamInvitationRole)]()
    private let failPreview: Bool
    private let failExchange: Bool
    private let gate: String?
    private let now: @Sendable () -> Int64
    private var waiter: CheckedContinuation<Void, Never>?
    private let hook: @Sendable (String) throws -> Void
    init(failPreview: Bool = false, failExchange: Bool = false, gate: String? = nil,
         now: @escaping @Sendable () -> Int64 = { 1_000 },
         hook: @escaping @Sendable (String) throws -> Void = { _ in }) {
        self.failPreview = failPreview; self.failExchange = failExchange; self.gate = gate; self.hook = hook
        self.now = now
    }
    private func step(_ label: String) async throws {
        calls.append(label)
        if gate == label { await withCheckedContinuation { waiter = $0 } }
        try hook(label)
    }
    func previewInvitation(token: String) async throws -> TeamInvitationPreview {
        try await step("preview")
        if failPreview { throw TeamAuthHTTPError.server(.invalidCredentials) }
        return .init(inviteID: "public-invite", teamID: "public-team", role: .reviewer, expiresAt: 1_000_000)
    }
    func invitedChallenge(providerID: String, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthChallenge {
        bindings.append((token, teamID, role)); try await step("challenge")
        #expect(providerID == "public-ios")
        return .init(challengeID: String(repeating: "A", count: 43), nonce: String(repeating: "B", count: 42) + "A", expiresAt: now() + 120_000)
    }
    func invitedExchange(_ submission: TeamNativeLoginSubmission, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthSessionPair {
        bindings.append((token, teamID, role)); try await step("exchange")
        if failExchange { throw TeamAuthHTTPError.server(.uncertain) }
        return invitationPair
    }
    func finish() { let saved = waiter; waiter = nil; saved?.resume() }
}
private actor InvitationIdentity: TeamNativeIdentityAuthorizing {
    private let gate: Bool
    private let hook: @Sendable () throws -> Void
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(gate: Bool = false, hook: @escaping @Sendable () throws -> Void = {}) { self.gate = gate; self.hook = hook }
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        calls += 1
        if gate { await withCheckedContinuation { waiter = $0 } }
        try hook()
        return .apple(state: context.state, token: Data("public.header.signature".utf8))
    }
    func finish() { let saved = waiter; waiter = nil; saved?.resume() }
}
private struct InvitationFixture {
    let clock = InvitationClock()
    let scope: TeamAccountSessionScope
    let backend = SessionMemoryKeychain()
    let sessions: TeamAccountSessionStore
    init(active: Bool = false) throws {
        scope = try .init(origin: URL(string: "https://pinbook.example")!, providerID: "public-ios")
        sessions = .init(testService: "invitation-fixture", keychain: backend)
        if active { _ = try sessions.saveInitial(invitationPair, scope: scope, now: 1_000, consent: true) }
    }
    func owner(_ transport: InvitationTransport, identity: InvitationIdentity = InvitationIdentity()) -> TeamInvitedSignIn {
        .init(provider: .apple, scope: scope, sessions: sessions, identity: identity, transport: transport, clock: { clock.now() })
    }
}

struct TeamInvitedSignInTests {
    @Test func screenHandoffRechecksTimeAfterProtectedAccountRead() async throws {
        for delta: Int64 in [899_000, 1_000_000, -1] {
            let f = try InvitationFixture(active: true), bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(InvitationTransport()), code: invitationCode)
            let display = try await bridge.review(), receipt = try await bridge.access(display, consent: false)
            // The first handoff clock read is valid; time changes before the
            // protected-account read finishes. Test access/invite expiry/rollback.
            f.clock.advanceAfterNextRead(wall: delta, elapsed: .milliseconds(max(0, delta)))
            await #expect(throws: (any Error).self) { try await bridge.takeIntent(receipt) }
            await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.takeIntent(receipt) }
            try await bridge.close()
            #expect(try f.sessions.load(scope: f.scope) != nil)
        }
    }
    @Test func screenBridgeHidesSecretsAndMakesOneExactExistingAccountHandoff() async throws {
        let f = try InvitationFixture(active: true), transport = InvitationTransport(), identity = InvitationIdentity()
        let bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(transport, identity: identity), code: invitationCode)
        #expect(await transport.calls.isEmpty)
        let display = try await bridge.review()
        let forged = TeamInvitationAccountReview(teamID: display.teamID, role: display.role, expiresAt: display.expiresAt, accountID: display.accountID)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.access(forged, consent: true) }
        let receipt = try await bridge.access(display, consent: false)
        #expect(Mirror(reflecting: display).children.isEmpty && Mirror(reflecting: receipt).children.isEmpty)
        #expect(!String(reflecting: receipt).contains(invitationCode))
        let forgedReceipt = TeamInvitationAccountReceipt(teamID: receipt.teamID, role: receipt.role, accountID: receipt.accountID)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.takeIntent(forgedReceipt) }
        let intent = try await bridge.takeIntent(receipt)
        #expect(intent.token == invitationCode && intent.account.accountID == display.accountID)
        try f.sessions.requireCurrentAccess(intent.account, now: 1_000)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.takeIntent(receipt) }
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.review() }
        #expect(await identity.calls == 0)
        #expect(await transport.calls == ["preview"])
        try await bridge.close()
        #expect(try f.sessions.load(scope: f.scope) != nil)
    }
    @Test func screenBridgeNewAccountConsentIsSeparateAndFailedExchangeCannotReplay() async throws {
        for fail in [false, true] {
            let f = try InvitationFixture(), transport = InvitationTransport(failExchange: fail), identity = InvitationIdentity()
            let bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(transport, identity: identity), code: invitationCode)
            let display = try await bridge.review()
            await #expect(throws: TeamInvitationAccountError.consentRequired) { try await bridge.access(display, consent: false) }
            #expect(f.backend.writes == 0)
            #expect(await identity.calls == 0)
            if fail { await #expect(throws: (any Error).self) { try await bridge.access(display, consent: true) } }
            else {
                let receipt = try await bridge.access(display, consent: true)
                let intent = try await bridge.takeIntent(receipt)
                #expect(intent.account.accountID == invitationPair.accountID && intent.role == .reviewer)
            }
            await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.access(display, consent: true) }
            await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.review() }
            #expect(await transport.calls == ["preview", "challenge", "exchange"])
            #expect(await identity.calls == 1)
            try await bridge.close()
        }
    }
    @Test func screenHandoffRejectsAccountReplacementAndExpiryWithoutDeletingAccounts() async throws {
        for expired in [false, true] {
            let f = try InvitationFixture(active: true), bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(InvitationTransport()), code: invitationCode)
            let display = try await bridge.review(), receipt = try await bridge.access(display, consent: false)
            if expired { f.clock.advance(wall: 1_000_000, elapsed: .seconds(1_000)) }
            else {
                try f.sessions.removeCurrent(scope: f.scope, consent: true)
                _ = try f.sessions.saveInitial(invitationPair, scope: f.scope, now: 1_000, consent: true)
            }
            await #expect(throws: (any Error).self) { try await bridge.takeIntent(receipt) }
            await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.takeIntent(receipt) }
            try await bridge.close()
            #expect(try f.sessions.load(scope: f.scope) != nil)
        }
    }
    @Test func screenBridgeCloseDrainsDelayedPreviewAndCannotReopen() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(gate: "preview")
        let bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(transport), code: invitationCode)
        let work = Task { try await bridge.review() }
        for _ in 0..<200 {
            if await transport.calls.contains("preview") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await transport.calls == ["preview"])
        let closing = Task { try await bridge.close() }
        // Wait for the permanently closed state without releasing transport yet.
        for _ in 0..<200 {
            do { _ = try await bridge.review(); Issue.record("Unexpected second preview") }
            catch TeamInvitationAccountError.staleConsent { break }
            catch TeamInvitationAccountError.busy { await Task.yield() }
        }
        await transport.finish()
        await #expect(throws: (any Error).self) { try await work.value }
        try await closing.value; try await bridge.close()
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.review() }
        #expect(f.backend.writes == 0)
        #expect(await transport.calls == ["preview"])
    }
    @Test func screenBridgeCloseInvalidatesCompletedReceiptButPreservesCommittedAccount() async throws {
        let f = try InvitationFixture(), bridge = try TeamInvitationAccountScreenBridge(owner: f.owner(InvitationTransport()), code: invitationCode)
        let display = try await bridge.review(), receipt = try await bridge.access(display, consent: true)
        try await bridge.close()
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await bridge.takeIntent(receipt) }
        #expect(try f.sessions.load(scope: f.scope)?.usablePair(now: 1_000) == invitationPair)
    }
    @Test func previewIsReadOnlyAndAccountConsentDoesNotJoinTeam() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(), identity = InvitationIdentity(), owner = f.owner(transport, identity: identity)
        let display = try await owner.preview(code: invitationCode)
        #expect(display.teamID == "public-team" && display.role == .reviewer && display.accountID == nil)
        #expect(f.backend.writes == 0)
        await #expect(throws: TeamInvitationAccountError.consentRequired) { try await owner.confirmAccountAccess(display, agreed: false) }
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        let intent = try await owner.signIn(consent)
        #expect(intent.token == invitationCode && intent.teamID == display.teamID && intent.role == .reviewer)
        try f.sessions.requireCurrentAccess(intent.account, now: 1_000)
        #expect(await transport.calls == ["preview", "challenge", "exchange"])
        #expect(await identity.calls == 1)
        #expect(await transport.bindings.allSatisfy { $0.0 == invitationCode && $0.1 == "public-team" && $0.2 == .reviewer })
        #expect(!String(reflecting: intent).contains(invitationCode) && Mirror(reflecting: intent).children.isEmpty)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.signIn(consent) }
    }
    @Test func newPreviewReconfirmationOtherInstanceAndClearInvalidateOldConsent() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(), owner = f.owner(transport)
        let first = try await owner.preview(code: invitationCode)
        let old = try await owner.confirmAccountAccess(first, agreed: true)
        let newer = try await owner.confirmAccountAccess(first, agreed: true)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.signIn(old) }
        let other = f.owner(transport)
        _ = try await other.preview(code: invitationCode)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await other.signIn(newer) }
        _ = try await owner.preview(code: invitationCode)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.signIn(newer) }
        try await owner.clear()
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.confirmAccountAccess(first, agreed: true) }
        #expect(f.backend.writes == 0)
    }
    @Test func existingAccountUsesExactDisplayedTicketWithoutProviderOrAccountCreation() async throws {
        let f = try InvitationFixture(active: true), transport = InvitationTransport(), identity = InvitationIdentity(), owner = f.owner(transport, identity: identity)
        let display = try await owner.preview(code: invitationCode)
        #expect(display.accountID == invitationPair.accountID)
        await #expect(throws: TeamInvitationAccountError.existingAccountRequired) { try await owner.confirmAccountAccess(display, agreed: true) }
        let intent = try await owner.existingAccountIntent(display)
        try f.sessions.requireCurrentAccess(intent.account, now: 1_000)
        #expect(await identity.calls == 0)
        #expect(await transport.calls == ["preview"])
        #expect(f.backend.writes == 1)
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.existingAccountIntent(display) }
    }
    @Test func accountChangeAfterPreviewCannotSilentlyChooseNewAccount() async throws {
        let f = try InvitationFixture(active: true), owner = f.owner(InvitationTransport())
        let display = try await owner.preview(code: invitationCode)
        try f.sessions.removeCurrent(scope: f.scope, consent: true)
        _ = try f.sessions.saveInitial(invitationPair, scope: f.scope, now: 1_000, consent: true)
        await #expect(throws: TeamAccountSessionError.staleOperation) { try await owner.existingAccountIntent(display) }
        #expect(try f.sessions.load(scope: f.scope)?.usablePair(now: 1_000) == invitationPair)
    }
    @Test func newAccountConsentCannotReplaceAccountCreatedAfterPreview() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(), owner = f.owner(transport)
        let display = try await owner.preview(code: invitationCode)
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        _ = try f.sessions.saveInitial(invitationPair, scope: f.scope, now: 1_000, consent: true)
        await #expect(throws: TeamAccountSessionError.alreadyExists) { try await owner.signIn(consent) }
        #expect(await transport.calls == ["preview"])
        #expect(try f.sessions.load(scope: f.scope)?.usablePair(now: 1_000) == invitationPair)
    }
    @Test func publicFailureAndMalformedCodeNeverDeleteUnrelatedAccount() async throws {
        let f = try InvitationFixture(active: true), transport = InvitationTransport(failPreview: true), owner = f.owner(transport)
        for code in ["", invitationCode + "=", " " + invitationCode, String(repeating: "Z", count: 50_000)] {
            await #expect(throws: TeamInvitationAccountError.invalidCode) { try await owner.preview(code: code) }
        }
        #expect(await transport.calls.isEmpty)
        await #expect(throws: TeamInvitationAccountError.previewUnavailable) { try await owner.preview(code: invitationCode) }
        #expect(try f.sessions.load(scope: f.scope)?.usablePair(now: 1_000) == invitationPair)
        #expect(f.backend.writes == 1)
    }
    @Test func consentExpiresOnMonotonicOrWallTimeAndRollbackFails() async throws {
        for kind in ["wall", "monotonic", "rollback"] {
            let f = try InvitationFixture(), transport = InvitationTransport(), owner = f.owner(transport)
            let display = try await owner.preview(code: invitationCode)
            let consent = try await owner.confirmAccountAccess(display, agreed: true)
            if kind == "wall" { f.clock.advance(wall: 300_000) }
            if kind == "monotonic" { f.clock.advance(elapsed: .seconds(300)) }
            if kind == "rollback" { f.clock.advance(wall: -1) }
            do { _ = try await owner.signIn(consent); Issue.record("Accepted expired consent") }
            catch { #expect(error is TeamInvitationAccountError || error is TeamAccountSessionError) }
            #expect(await transport.calls == ["preview"])
            #expect(f.backend.writes == 0)
        }
    }
    @Test func consentExpiryDuringProviderCannotDispatchExchange() async throws {
        let f = try InvitationFixture()
        let transport = InvitationTransport(now: { f.clock.now().wallTime })
        let identity = InvitationIdentity(hook: { f.clock.advance(wall: 20_000, elapsed: .seconds(20)) })
        let owner = f.owner(transport, identity: identity)
        let display = try await owner.preview(code: invitationCode)
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        f.clock.advance(wall: 290_000, elapsed: .seconds(290))
        await #expect(throws: TeamAccountSignInError.providerFailure) { try await owner.signIn(consent) }
        #expect(await identity.calls == 1)
        #expect(await transport.calls == ["preview", "challenge"])
        #expect(try f.sessions.loginReservation(scope: f.scope) != nil)
    }
    @Test func unknownExchangeNeverReusesConsentOrProof() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(failExchange: true), owner = f.owner(transport)
        let display = try await owner.preview(code: invitationCode)
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        await #expect(throws: TeamAccountSignInError.transportFailure) { try await owner.signIn(consent) }
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.signIn(consent) }
        #expect(await transport.calls == ["preview", "challenge", "exchange"])
        let bytes = try #require(f.backend.bytes)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(invitationCode))
        #expect(try f.sessions.loginReservation(scope: f.scope) != nil)
    }
    @Test func clearRejectsLatePreviewAndRetainsBusyUntilCallback() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(gate: "preview"), owner = f.owner(transport)
        let operation = Task { try await owner.preview(code: invitationCode) }
        for _ in 0..<200 {
            if await transport.calls.contains("preview") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await owner.clear()
        await #expect(throws: TeamInvitationAccountError.busy) { try await owner.preview(code: invitationCode) }
        await transport.finish()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(f.backend.writes == 0)
    }
    @Test func clearDuringProviderDropsReservationButNotNewerAccount() async throws {
        let f = try InvitationFixture(), transport = InvitationTransport(), identity = InvitationIdentity(gate: true), owner = f.owner(transport, identity: identity)
        let display = try await owner.preview(code: invitationCode)
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        let operation = Task { try await owner.signIn(consent) }
        for _ in 0..<200 {
            if await identity.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await owner.clear()
        #expect(try f.sessions.loginReservation(scope: f.scope) == nil)
        _ = try f.sessions.saveInitial(invitationPair, scope: f.scope, now: 1_000, consent: true)
        await identity.finish()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await transport.calls == ["preview", "challenge"])
        #expect(try f.sessions.load(scope: f.scope)?.usablePair(now: 1_000) == invitationPair)
    }
}
