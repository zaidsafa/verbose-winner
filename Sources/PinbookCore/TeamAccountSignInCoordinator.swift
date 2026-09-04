import Foundation

public enum TeamAccountSignInError: Error, Equatable { case busy, invalidated, expired, providerFailure, transportFailure }

public enum TeamNativeIdentityResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case apple(state: String?, token: Data)
    case google(token: Data)
    public var description: String { "TeamNativeIdentityResponse(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Adapter must own a fresh interactive native request, bind its own callback,
/// forward the exact challenge nonce, and settle cancellation before returning.
/// Cached SDK currentUser/Drive credentials cannot satisfy this protocol contract.
public protocol TeamNativeIdentityAuthorizing: Sendable {
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse
}
protocol TeamAccountSigningIn: Sendable {
    func challenge(providerID: String) async throws -> TeamAuthChallenge
    func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair
}
extension TeamAuthHTTPClient: TeamAccountSigningIn {}

struct TeamSignInMoment: Sendable {
    let wallTime: Int64
    let instant: ContinuousClock.Instant
    static func current() -> Self { Self(wallTime: Int64(Date().timeIntervalSince1970 * 1000), instant: .now) }
}

/// Durable reservation + one-owner native callback + one-use server exchange.
/// Still inactive: real provider adapter/configuration and UI are separate gates.
public actor TeamAccountSignInCoordinator {
    private struct Pending {
        let id: UUID
        let reservation: TeamAccountLoginReservation
        let task: Task<TeamAuthSessionPair, Error>
        var invalidated = false
    }
    private let provider: TeamNativeSignInProvider
    private let scope: TeamAccountSessionScope
    private let store: TeamAccountSessionStore
    private let transport: any TeamAccountSigningIn
    private let identity: any TeamNativeIdentityAuthorizing
    private let flow = TeamNativeSignInFlow()
    private let clock: @Sendable () -> TeamSignInMoment
    private var pending: Pending?
    private var lastMoment: TeamSignInMoment?

    public init(provider: TeamNativeSignInProvider, scope: TeamAccountSessionScope,
                store: TeamAccountSessionStore = .init(), identity: any TeamNativeIdentityAuthorizing) throws {
        self.provider = provider; self.scope = scope; self.store = store; self.identity = identity
        transport = try TeamAuthHTTPClient(origin: scope.origin)
        clock = { .current() }
    }
    init(provider: TeamNativeSignInProvider, scope: TeamAccountSessionScope, store: TeamAccountSessionStore,
         identity: any TeamNativeIdentityAuthorizing, transport: any TeamAccountSigningIn,
         clock: @escaping @Sendable () -> TeamSignInMoment) {
        self.provider = provider; self.scope = scope; self.store = store
        self.identity = identity; self.transport = transport; self.clock = clock
    }

    public func signIn(consent: Bool) async throws -> TeamAuthSessionPair {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamAccountSignInError.busy }
        let start = try moment()
        let reservation = try store.beginLogin(scope: scope, now: start.wallTime, consent: consent)
        try Task.checkCancellation()
        let id = UUID()
        let task = Task { try await self.perform(id: id, reservation: reservation, start: start) }
        pending = Pending(id: id, reservation: reservation, task: task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler {
            // Child checks cancellation before commit. No post-commit cancellation
            // is reported as rollback by the parent.
            try await task.value
        } onCancel: { task.cancel() }
    }

    /// Cancels only this operation and its exact durable reservation. A provider
    /// ignoring cancellation keeps the occupied slot until its callback settles.
    public func cancelPendingSignIn() throws {
        guard var value = pending else { return }
        value.invalidated = true; pending = value; value.task.cancel()
        try store.cancelLogin(value.reservation)
    }
    /// Explicit recovery after process death or an unsuccessful attempt. Never
    /// removes an active session. Caller must not label this as remote revocation.
    public func discardAbandonedReservation(consent: Bool) throws {
        try Task.checkCancellation()
        guard consent else { throw TeamAccountSessionError.consentRequired }
        guard pending == nil else { throw TeamAccountSignInError.busy }
        if let value = try store.loginReservation(scope: scope) { try store.cancelLogin(value) }
    }

    private func perform(id: UUID, reservation: TeamAccountLoginReservation,
                         start: TeamSignInMoment) async throws -> TeamAuthSessionPair {
        _ = try checkpoint(id, reservation, start)
        let challenge: TeamAuthChallenge
        do { challenge = try await transport.challenge(providerID: scope.providerID) }
        catch { _ = try checkpoint(id, reservation, start); throw TeamAccountSignInError.transportFailure }
        let now = try checkpoint(id, reservation, start)
        let context = try await flow.begin(provider: provider, providerID: scope.providerID,
            challengeID: challenge.challengeID, nonce: challenge.nonce, expiresAt: challenge.expiresAt, now: now.wallTime)
        let challengeDeadline = now.instant.advanced(by: .milliseconds(context.expiresAt - now.wallTime))
        do {
            let beforeProvider = try checkpoint(id, reservation, start)
            guard beforeProvider.wallTime < context.expiresAt, beforeProvider.instant < challengeDeadline else {
                throw TeamAccountSignInError.expired
            }
            let response: TeamNativeIdentityResponse
            do { response = try await identity.authorize(context) }
            catch { _ = try checkpoint(id, reservation, start); throw TeamAccountSignInError.providerFailure }
            let returnedAt = try checkpoint(id, reservation, start)
            let submission: TeamNativeLoginSubmission
            switch (provider, response) {
            case (.apple, .apple(let state, let token)):
                submission = try await flow.acceptApple(attemptID: context.id, returnedState: state,
                    identityToken: token, now: returnedAt.wallTime)
            case (.google, .google(let token)):
                submission = try await flow.acceptGoogleSDK(attemptID: context.id, identityToken: token, now: returnedAt.wallTime)
            default: throw TeamNativeSignInError.invalidCallback
            }
            let beforeExchange = try checkpoint(id, reservation, start)
            guard beforeExchange.wallTime < context.expiresAt, beforeExchange.instant < challengeDeadline else {
                throw TeamAccountSignInError.expired
            }
            let pair: TeamAuthSessionPair
            do { pair = try await transport.exchange(submission) }
            catch { _ = try checkpoint(id, reservation, start); throw TeamAccountSignInError.transportFailure }
            let completedAt = try checkpoint(id, reservation, start)
            guard completedAt.wallTime < context.expiresAt, completedAt.instant < challengeDeadline else {
                throw TeamAccountSignInError.expired
            }
            let saved = try store.completeLogin(reservation, pair: pair, now: completedAt.wallTime)
            return try saved.usablePair(now: completedAt.wallTime)
        } catch {
            await flow.cancel(attemptID: context.id)
            throw error
        }
    }

    private func checkpoint(_ id: UUID, _ reservation: TeamAccountLoginReservation,
                            _ start: TeamSignInMoment) throws -> TeamSignInMoment {
        try Task.checkCancellation()
        guard pending?.id == id, pending?.invalidated == false else { throw TeamAccountSignInError.invalidated }
        guard try store.loginReservation(scope: scope)?.generation == reservation.generation else {
            throw TeamAccountSessionError.staleOperation
        }
        // Time is sampled AFTER synchronous custody access, not before it.
        let current = try moment()
        guard current.wallTime < reservation.expiresAt,
              start.instant.duration(to: current.instant) < .seconds(120) else { throw TeamAccountSignInError.expired }
        return current
    }
    private func moment() throws -> TeamSignInMoment {
        let value = clock()
        try TeamAccountSessionCodec.checkClock(value.wallTime, since: lastMoment?.wallTime ?? 0)
        guard lastMoment.map({ value.instant >= $0.instant }) ?? true else { throw TeamAccountSignInError.expired }
        lastMoment = value
        return value
    }
}
