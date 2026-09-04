import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class RefreshClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 2_000
    func now() -> Int64 { lock.withLock { value } }
    func set(_ value: Int64) { lock.withLock { self.value = value } }
}
private actor ControlledRefresh: TeamAccountRefreshing {
    private var continuation: CheckedContinuation<TeamAuthSessionPair, Error>?
    private(set) var calls = 0
    // Intentionally ignores cancellation until explicitly released by a test.
    func refresh(_ current: TeamAuthSessionPair) async throws -> TeamAuthSessionPair {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ result: Result<TeamAuthSessionPair, Error>) {
        let next = continuation; continuation = nil; next?.resume(with: result)
    }
}

struct TeamAccountRefreshManagerTests {
    private var old: TeamAuthSessionPair { pair("A", "B") }
    private var next: TeamAuthSessionPair { pair("C", "D") }
    private func pair(_ access: String, _ refresh: String, account: String = "public-account") -> TeamAuthSessionPair {
        TeamAuthSessionPair(accountID: account, sessionID: "public-session",
            accessToken: String(repeating: access, count: 42) + "A",
            refreshToken: String(repeating: refresh, count: 42) + "A",
            accessExpiresAt: 10_000, sessionExpiresAt: 30_000)
    }
    private func fixture() throws -> (TeamAccountRefreshManager, TeamAccountSessionStore, TeamAccountSessionScope,
                                     SessionMemoryKeychain, ControlledRefresh, RefreshClock) {
        let scope = try TeamAccountSessionScope(origin: URL(string: "https://auth.invalid")!, providerID: "public-ios")
        let backend = SessionMemoryKeychain(), transport = ControlledRefresh(), clock = RefreshClock()
        let store = TeamAccountSessionStore(testService: "refresh-fixture", keychain: backend)
        _ = try store.saveInitial(old, scope: scope, now: 1_000, consent: true)
        let manager = TeamAccountRefreshManager(scope: scope, store: store, transport: transport, clock: { clock.now() })
        return (manager, store, scope, backend, transport, clock)
    }
    private func waitForCall(_ transport: ControlledRefresh) async throws {
        for _ in 0..<100 {
            if await transport.calls == 1 { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic refresh did not start")
    }

    @Test func markerPrecedesDispatchAndPairIsSavedBeforeReturning() async throws {
        let (manager, store, scope, _, transport, clock) = try fixture()
        let operation = Task { try await manager.refresh() }
        try await waitForCall(transport)
        #expect(try store.load(scope: scope)?.phase == .refreshPending)
        await #expect(throws: TeamAccountRefreshError.busy) { try await manager.refresh() }
        clock.set(3_000)
        await transport.complete(.success(next))
        #expect(try await operation.value == next)
        #expect(try store.load(scope: scope)?.usablePair(now: 3_001) == next)
        #expect(await transport.calls == 1)
    }

    @Test func failedMarkerDoesNotDispatchAndLostResponseNeverReplays() async throws {
        for afterCommit in [false, true] {
            let (manager, _, _, backend, transport, _) = try fixture()
            backend.failUpdate(afterCommit: afterCommit)
            await #expect(throws: TeamAccountSessionError.unavailable(errSecNotAvailable)) { try await manager.refresh() }
            #expect(await transport.calls == 0)
        }
        let (manager, store, scope, _, transport, _) = try fixture()
        let operation = Task { try await manager.refresh() }
        try await waitForCall(transport)
        await transport.complete(.failure(URLError(.networkConnectionLost)))
        await #expect(throws: TeamAccountRefreshError.transportFailure) { try await operation.value }
        #expect(try store.load(scope: scope)?.phase == .refreshPending)
        await #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try await manager.refresh() }
        #expect(await transport.calls == 1)
    }

    @Test func cancelledCallerKeepsSlotUntilIgnoringTransportSettlesAndDiscardsLatePair() async throws {
        let (manager, store, scope, _, transport, _) = try fixture()
        let operation = Task { try await manager.refresh() }
        try await waitForCall(transport)
        operation.cancel()
        await #expect(throws: TeamAccountRefreshError.busy) { try await manager.refresh() }
        await transport.complete(.success(next))
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try store.load(scope: scope)?.phase == .refreshPending)
        await #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try await manager.refresh() }
        #expect(await transport.calls == 1)
    }

    @Test func invalidationAndNewLoginCannotBeOverwrittenByOldCallback() async throws {
        let (manager, store, scope, _, transport, _) = try fixture()
        let operation = Task { try await manager.refresh() }
        try await waitForCall(transport)
        await #expect(throws: TeamAccountSessionError.consentRequired) { try await manager.signOutLocally(consent: false) }
        try await manager.signOutLocally(consent: true)
        let another = pair("E", "F", account: "new-account")
        _ = try store.saveInitial(another, scope: scope, now: 3_000, consent: true)
        await #expect(throws: TeamAccountRefreshError.busy) { try await manager.refresh() }
        await transport.complete(.success(next))
        await #expect(throws: TeamAccountRefreshError.invalidated) { try await operation.value }
        #expect(try store.load(scope: scope)?.usablePair(now: 3_001) == another)
    }

    @Test func replacementFailureReconcilesPendingOrNewPairWithoutRetry() async throws {
        for afterCommit in [false, true] {
            let (manager, store, scope, backend, transport, _) = try fixture()
            let operation = Task { try await manager.refresh() }
            try await waitForCall(transport)
            backend.failUpdate(afterCommit: afterCommit)
            await transport.complete(.success(next))
            await #expect(throws: TeamAccountSessionError.unavailable(errSecNotAvailable)) { try await operation.value }
            let saved = try #require(try store.load(scope: scope))
            #expect(saved.phase == (afterCommit ? .active : .refreshPending))
            if afterCommit { #expect(try saved.usablePair(now: 3_000) == next) }
            #expect(await transport.calls == 1)
        }
    }

    @Test func rollbackExpiredReplyAndPrecancelledCallerCannotCreateUsableSession() async throws {
        for time: Int64 in [1_999, 10_000] {
            let (manager, store, scope, _, transport, clock) = try fixture()
            let operation = Task { try await manager.refresh() }
            try await waitForCall(transport)
            clock.set(time)
            await transport.complete(.success(next))
            do { _ = try await operation.value; Issue.record("Invalid clock/expiry accepted") }
            catch { #expect(error is TeamAccountSessionError) }
            #expect(try store.load(scope: scope)?.phase == .refreshPending)
        }
        let (manager, store, scope, backend, transport, _) = try fixture()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await manager.refresh() }
        }
        await cancelled.value
        #expect(await transport.calls == 0 && backend.writes == 1)
        #expect(try store.load(scope: scope)?.phase == .active)
    }
}
