import Foundation

public enum TeamAccountRefreshError: Error, Equatable {
    case busy, invalidated, transportFailure
}

protocol TeamAccountRefreshing: Sendable {
    func refresh(_ current: TeamAuthSessionPair) async throws -> TeamAuthSessionPair
}
extension TeamAuthHTTPClient: TeamAccountRefreshing {}

/// One owner for rotating refresh. Never auto-retries, starts provider sign-in,
/// changes accounts, or treats local removal as remote revocation. Still inactive
/// until integrated with approved configuration and native sign-in ownership.
public actor TeamAccountRefreshManager {
    private struct Pending {
        let id: UUID
        let task: Task<TeamAuthSessionPair, Error>
        var invalidated = false
    }
    private let scope: TeamAccountSessionScope
    private let store: TeamAccountSessionStore
    private let transport: any TeamAccountRefreshing
    private let clock: @Sendable () -> Int64
    private var lastNow: Int64?
    private var pending: Pending?

    public init(scope: TeamAccountSessionScope, store: TeamAccountSessionStore = .init()) throws {
        self.scope = scope; self.store = store
        transport = try TeamAuthHTTPClient(origin: scope.origin)
        clock = { Int64(Date().timeIntervalSince1970 * 1000) }
    }
    init(scope: TeamAccountSessionScope, store: TeamAccountSessionStore,
         transport: any TeamAccountRefreshing, clock: @escaping @Sendable () -> Int64) {
        self.scope = scope; self.store = store; self.transport = transport; self.clock = clock
    }

    public func refresh() async throws -> TeamAuthSessionPair {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamAccountRefreshError.busy }
        guard let current = try store.load(scope: scope) else {
            throw TeamAccountSessionError.reauthenticationRequired
        }
        let lease = try store.beginRefresh(current, now: now())
        // Cancellation during the synchronous protected write leaves its marker
        // intact but must not start the network call.
        try Task.checkCancellation()
        let id = UUID()
        let request = Task { [transport, pair = lease.previousPair] in
            try Task.checkCancellation()
            return try await transport.refresh(pair)
        }
        pending = Pending(id: id, task: request)
        defer { if pending?.id == id { pending = nil } }

        return try await withTaskCancellationHandler {
            let result: TeamAuthSessionPair
            do { result = try await request.value }
            catch {
                try Task.checkCancellation()
                guard pending?.id == id, pending?.invalidated == false else {
                    throw TeamAccountRefreshError.invalidated
                }
                // No raw provider/network error escapes. The durable marker stays.
                throw TeamAccountRefreshError.transportFailure
            }
            try Task.checkCancellation()
            guard pending?.id == id, pending?.invalidated == false else {
                throw TeamAccountRefreshError.invalidated
            }
            let saved = try store.completeRefresh(lease, next: result, now: now())
            // No await/cancellation check after commit: don't misreport a committed
            // pair as rollback. A later explicit store read reconciles ambiguity.
            return try saved.usablePair(now: saved.observedAt)
        } onCancel: { request.cancel() }
    }

    /// Lifecycle/account-owner invalidation. Keep the occupied slot until the
    /// underlying task actually settles, even if its implementation ignores cancel.
    public func cancelPendingRefresh() {
        guard var value = pending else { return }
        value.invalidated = true; pending = value
        value.task.cancel()
    }

    /// Explicit local action only. Notes, recovery keys and remote sessions are
    /// untouched. The remote logout/revocation workflow must be handled separately.
    public func signOutLocally(consent: Bool) throws {
        try Task.checkCancellation()
        guard consent else { throw TeamAccountSessionError.consentRequired }
        cancelPendingRefresh()
        try store.removeCurrent(scope: scope, consent: true)
    }

    private func now() throws -> Int64 {
        let value = clock()
        try TeamAccountSessionCodec.checkClock(value, since: lastNow ?? 0)
        lastNow = value
        return value
    }
}
