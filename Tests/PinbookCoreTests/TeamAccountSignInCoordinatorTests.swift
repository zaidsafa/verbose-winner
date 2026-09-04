import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct SyntheticAppleIdentity: TeamNativeIdentityAuthorizing {
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        .apple(state: context.state, token: Data("public.header.signature".utf8))
    }
}
private final class SignInFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TeamSignInMoment(wallTime: 1_000, instant: .now)
    func now() -> TeamSignInMoment { lock.withLock { value } }
    func advance(wall: Int64 = 0, elapsed: Duration = .zero) {
        lock.withLock { value = TeamSignInMoment(wallTime: value.wallTime + wall, instant: value.instant.advanced(by: elapsed)) }
    }
}
private actor SignInFixtureTransport: TeamAccountSigningIn {
    let result: TeamAuthSessionPair
    let gateExchange: Bool
    private var continuation: CheckedContinuation<TeamAuthSessionPair, Error>?
    private(set) var challenges = 0
    private(set) var exchanges = 0
    init(pair: TeamAuthSessionPair, gateExchange: Bool = false) { result = pair; self.gateExchange = gateExchange }
    func challenge(providerID: String) async throws -> TeamAuthChallenge {
        challenges += 1
        return TeamAuthChallenge(challengeID: String(repeating: "A", count: 43),
            nonce: String(repeating: "B", count: 42) + "A", expiresAt: 121_000)
    }
    func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair {
        exchanges += 1
        if gateExchange { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return result
    }
    func finish() { let saved = continuation; continuation = nil; saved?.resume(returning: result) }
}
private actor SignInFixtureIdentity: TeamNativeIdentityAuthorizing {
    private var continuation: CheckedContinuation<TeamNativeIdentityResponse, Error>?
    private var context: TeamNativeSignInContext?
    private(set) var calls = 0
    // Intentionally waits for test callback even after cancellation.
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        self.context = context; calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(wrongState: Bool = false, google: Bool = false) {
        let callback = continuation; continuation = nil
        let token = Data("public.header.signature".utf8)
        callback?.resume(returning: google ? .google(token: token) :
            .apple(state: wrongState ? "wrong-state" : context?.state, token: token))
        context = nil
    }
}

struct TeamAccountSignInCoordinatorTests {
    private var pair: TeamAuthSessionPair {
        TeamAuthSessionPair(accountID: "public-account", sessionID: "public-session",
            accessToken: String(repeating: "C", count: 42) + "A", refreshToken: String(repeating: "D", count: 42) + "A",
            accessExpiresAt: 10_000, sessionExpiresAt: 30_000)
    }
    private func fixture(gateExchange: Bool = false) throws -> (TeamAccountSignInCoordinator, TeamAccountSessionStore,
        TeamAccountSessionScope, SessionMemoryKeychain, SignInFixtureIdentity, SignInFixtureTransport, SignInFixtureClock) {
        let scope = try TeamAccountSessionScope(origin: URL(string: "https://auth.invalid")!, providerID: "public-ios")
        let backend = SessionMemoryKeychain(), identity = SignInFixtureIdentity(), clock = SignInFixtureClock()
        let store = TeamAccountSessionStore(testService: "signin-fixture", keychain: backend)
        let transport = SignInFixtureTransport(pair: pair, gateExchange: gateExchange)
        return (TeamAccountSignInCoordinator(provider: .apple, scope: scope, store: store,
            identity: identity, transport: transport, clock: { clock.now() }), store, scope, backend, identity, transport, clock)
    }
    private func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic callback did not start")
    }

    @Test func durableReservationIsNotIdentityAndLateCommitCannotReplaceNewReservation() throws {
        let (_, store, scope, backend, _, _, _) = try fixture()
        #expect(throws: TeamAccountSessionError.consentRequired) { try store.beginLogin(scope: scope, now: 1_000, consent: false) }
        let first = try store.beginLogin(scope: scope, now: 1_000, consent: true)
        #expect(throws: TeamAccountSessionError.loginPending) { try store.load(scope: scope) }
        let bytes = try #require(backend.bytes)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("accountId"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Token"))
        #expect(try store.loginReservation(scope: scope)?.generation == first.generation)
        try store.cancelLogin(first)
        let second = try store.beginLogin(scope: scope, now: 2_000, consent: true)
        #expect(throws: TeamAccountSessionError.staleOperation) { try store.completeLogin(first, pair: pair, now: 3_000) }
        #expect(throws: TeamAccountSessionError.staleOperation) { try store.cancelLogin(first) }
        _ = try store.completeLogin(second, pair: pair, now: 3_000)
        #expect(throws: TeamAccountSessionError.staleOperation) { try store.cancelLogin(second) }
        #expect(throws: TeamAccountSessionError.alreadyExists) { try store.beginLogin(scope: scope, now: 4_000, consent: true) }
        #expect(try store.load(scope: scope)?.usablePair(now: 4_000) == pair)
        try store.removeCurrent(scope: scope, consent: true)
        let third = try store.beginLogin(scope: scope, now: 4_000, consent: true)
        try store.removeCurrent(scope: scope, consent: true)
        #expect(throws: TeamAccountSessionError.staleOperation) { try store.completeLogin(third, pair: pair, now: 4_001) }
        #expect(try store.load(scope: scope) == nil)
    }

    @Test func successBindsChallengeProviderCallbackExchangeAndProtectedCommit() async throws {
        let (owner, store, scope, _, identity, transport, _) = try fixture()
        let operation = Task { try await owner.signIn(consent: true) }
        try await waitUntil { await identity.calls == 1 }
        #expect(try store.loginReservation(scope: scope) != nil)
        await #expect(throws: TeamAccountSignInError.busy) { try await owner.signIn(consent: true) }
        await identity.finish()
        #expect(try await operation.value == pair)
        #expect(try store.load(scope: scope)?.usablePair(now: 2_000) == pair)
        #expect(await transport.challenges == 1)
        #expect(await transport.exchanges == 1)
    }

    @Test func consentExistingSessionAndPrecancelledCallerNeverContactProvider() async throws {
        let (owner, store, scope, backend, identity, transport, _) = try fixture()
        await #expect(throws: TeamAccountSessionError.consentRequired) { try await owner.signIn(consent: false) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await owner.signIn(consent: true) }
        }
        await cancelled.value
        #expect(backend.writes == 0)
        _ = try store.saveInitial(pair, scope: scope, now: 1_000, consent: true)
        await #expect(throws: TeamAccountSessionError.alreadyExists) { try await owner.signIn(consent: true) }
        #expect(await transport.challenges == 0)
        #expect(await identity.calls == 0)
    }

    @Test func cancellationQuarantinesProviderCallbackAndRequiresExplicitRestart() async throws {
        let (owner, store, scope, _, identity, transport, _) = try fixture()
        let operation = Task { try await owner.signIn(consent: true) }
        try await waitUntil { await identity.calls == 1 }
        operation.cancel()
        await #expect(throws: TeamAccountSignInError.busy) { try await owner.signIn(consent: true) }
        await identity.finish()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await transport.exchanges == 0)
        #expect(try store.loginReservation(scope: scope) != nil)
        await #expect(throws: TeamAccountSessionError.consentRequired) { try await owner.discardAbandonedReservation(consent: false) }
        try await owner.discardAbandonedReservation(consent: true)
        #expect(try store.load(scope: scope) == nil)
    }

    @Test func cancelledExchangeCannotInstallAfterAnotherOwnerStartsLogin() async throws {
        let (owner, store, scope, _, identity, transport, _) = try fixture(gateExchange: true)
        let operation = Task { try await owner.signIn(consent: true) }
        try await waitUntil { await identity.calls == 1 }; await identity.finish()
        try await waitUntil { await transport.exchanges == 1 }
        try await owner.cancelPendingSignIn()
        let newer = try store.beginLogin(scope: scope, now: 2_000, consent: true)
        await transport.finish()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try store.loginReservation(scope: scope)?.generation == newer.generation)
    }

    @Test func wallRollbackElapsedDeadlineAndWrongProviderOrStateNeverExchange() async throws {
        for mode in ["wall", "elapsed", "state", "provider"] {
            let (owner, store, scope, _, identity, transport, clock) = try fixture()
            let operation = Task { try await owner.signIn(consent: true) }
            try await waitUntil { await identity.calls == 1 }
            if mode == "wall" { clock.advance(wall: -1) }
            if mode == "elapsed" { clock.advance(elapsed: .seconds(120)) }
            await identity.finish(wrongState: mode == "state", google: mode == "provider")
            do { _ = try await operation.value; Issue.record("Invalid native result accepted") } catch {}
            #expect(await transport.exchanges == 0)
            #expect(try store.loginReservation(scope: scope) != nil)
        }
    }

    @Test func ambiguousLoginCommitIsReservationOrEntirePairWithoutSecondExchange() async throws {
        for afterCommit in [false, true] {
            let (owner, store, scope, backend, identity, transport, _) = try fixture()
            let operation = Task { try await owner.signIn(consent: true) }
            try await waitUntil { await identity.calls == 1 }
            backend.failUpdate(afterCommit: afterCommit)
            await identity.finish()
            await #expect(throws: TeamAccountSessionError.unavailable(errSecNotAvailable)) { try await operation.value }
            if afterCommit { #expect(try store.load(scope: scope)?.usablePair(now: 2_000) == pair) }
            else { #expect(try store.loginReservation(scope: scope) != nil) }
            #expect(await transport.exchanges == 1)
        }
    }
}
