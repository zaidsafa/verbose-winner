import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class SessionMemoryKeychain: TeamAccountSessionKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var item: [String: Any]?
    private var updateFailure = 0 // 1 before commit, 2 after commit.
    private var readFailure = false
    private var mutations = 0
    var writes: Int { lock.withLock { mutations } }
    var bytes: Data? { lock.withLock { item?[kSecValueData as String] as? Data } }
    var protection: String? { lock.withLock { item?[kSecAttrAccessible as String] as? String } }
    var synchronizes: Bool? { lock.withLock { item?[kSecAttrSynchronizable as String] as? Bool } }
    func failUpdate(afterCommit: Bool) { lock.withLock { updateFailure = afterCommit ? 2 : 1 } }
    func failRead() { lock.withLock { readFailure = true } }
    func corrupt(_ key: String, value: Any) { lock.withLock { item?[key] = value } }
    private func matches(_ query: [String: Any]) -> Bool {
        guard let item else { return false }
        for key in [kSecAttrService, kSecAttrAccount, kSecAttrAccessible] {
            if let wanted = query[key as String] as? String, wanted != item[key as String] as? String { return false }
        }
        if let wanted = query[kSecAttrGeneric as String] as? Data, wanted != item[kSecAttrGeneric as String] as? Data { return false }
        return true
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard item == nil else { return errSecDuplicateItem }
            item = attributes; mutations += 1; return errSecSuccess
        }
    }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.withLock {
            if readFailure { return (errSecInteractionNotAllowed, nil) }
            guard matches(query), let item else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, item as CFDictionary)
        }
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard matches(query) else { return errSecItemNotFound }
            let failure = updateFailure; updateFailure = 0
            if failure == 1 { return errSecNotAvailable }
            item?.merge(attributes) { _, new in new }; mutations += 1
            return failure == 2 ? errSecNotAvailable : errSecSuccess
        }
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            guard matches(query) else { return errSecItemNotFound }
            item = nil; mutations += 1; return errSecSuccess
        }
    }
}

struct TeamAccountSessionStoreTests {
    private func scope(_ provider: String = "public-ios") throws -> TeamAccountSessionScope {
        try TeamAccountSessionScope(origin: URL(string: "https://auth.invalid")!, providerID: provider)
    }
    private func pair(access: Character = "A", refresh: Character = "B", account: String = "public-account",
                      accessExpiry: Int64 = 10_000, sessionExpiry: Int64 = 30_000) -> TeamAuthSessionPair {
        TeamAuthSessionPair(accountID: account, sessionID: "public-session",
            accessToken: String(repeating: String(access), count: 42) + "A",
            refreshToken: String(repeating: String(refresh), count: 42) + "A",
            accessExpiresAt: accessExpiry, sessionExpiresAt: sessionExpiry)
    }
    private func store(_ keychain: SessionMemoryKeychain) -> TeamAccountSessionStore {
        TeamAccountSessionStore(testService: "synthetic-session", keychain: keychain)
    }

    @Test func explicitConsentPasscodeOnlyProtectionAndNoReplacement() throws {
        let backend = SessionMemoryKeychain(), scope = try scope()
        let custody = store(backend)
        #expect(throws: TeamAccountSessionError.consentRequired) {
            try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: false)
        }
        #expect(backend.writes == 0)
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        #expect(backend.protection == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
        #expect(backend.synchronizes == false)
        #expect(try saved.usablePair(now: 2_000) == pair())
        #expect(throws: TeamAccountSessionError.alreadyExists) {
            try custody.saveInitial(pair(account: "another"), scope: scope, now: 2_000, consent: true)
        }
        #expect(backend.writes == 1)
        #expect(!String(reflecting: saved).contains(pair().refreshToken))
        #expect(Mirror(reflecting: saved).children.isEmpty)
    }

    @Test func durableMarkerRemovesBothOldTokensBeforeDispatchAndSurvivesReopen() throws {
        let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        let lease = try custody.beginRefresh(saved, now: 12_000) // Expired access can still refresh.
        #expect(lease.previousPair == pair())
        let markerBytes = try #require(backend.bytes)
        let marker = try #require(try store(backend).load(scope: scope))
        #expect(marker.phase == .refreshPending && marker.pair == nil)
        #expect(!String(decoding: markerBytes, as: UTF8.self).contains(pair().refreshToken))
        #expect(!String(decoding: markerBytes, as: UTF8.self).contains(pair().accessToken))
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try marker.usablePair(now: 12_001) }
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try custody.beginRefresh(marker, now: 12_001) }
        #expect(throws: TeamAccountSessionError.staleOperation) { try custody.beginRefresh(saved, now: 12_001) }
        let next = pair(access: "C", refresh: "D", accessExpiry: 25_000)
        let fresh = try custody.completeRefresh(lease, next: next, now: 12_500)
        #expect(try store(backend).load(scope: scope)?.usablePair(now: 13_000) == next)
        #expect(fresh.generation != saved.generation && fresh.generation != marker.generation)
        #expect(throws: TeamAccountSessionError.staleOperation) { try custody.completeRefresh(lease, next: next, now: 13_000) }
    }

    @Test func ambiguousMarkerWriteNeverReturnsDispatchLease() throws {
        for afterCommit in [false, true] {
            let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
            let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
            backend.failUpdate(afterCommit: afterCommit)
            #expect(throws: TeamAccountSessionError.unavailable(errSecNotAvailable)) { try custody.beginRefresh(saved, now: 2_000) }
            let reopened = try #require(try store(backend).load(scope: scope))
            #expect(reopened.phase == (afterCommit ? .refreshPending : .active))
            // No HTTP dispatch occurred; the failed call returned no lease.
            if afterCommit { #expect(reopened.pair == nil) }
        }
    }

    @Test func ambiguousReplacementIsEitherPendingOrEntireNewPairNeverOldTokens() throws {
        for afterCommit in [false, true] {
            let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
            let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
            let lease = try custody.beginRefresh(saved, now: 2_000)
            backend.failUpdate(afterCommit: afterCommit)
            let next = pair(access: "C", refresh: "D")
            #expect(throws: TeamAccountSessionError.unavailable(errSecNotAvailable)) {
                try custody.completeRefresh(lease, next: next, now: 3_000)
            }
            let reopened = try #require(try store(backend).load(scope: scope))
            #expect(reopened.phase == (afterCommit ? .active : .refreshPending))
            if afterCommit { #expect(try reopened.usablePair(now: 3_001) == next) }
            else { #expect(reopened.pair == nil) }
            #expect(!String(decoding: try #require(backend.bytes), as: UTF8.self).contains(pair().refreshToken))
        }
    }

    @Test func concurrentRefreshHasOneWinnerAndLateCallbackCannotResurrectSignedOutAccount() async throws {
        let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        let leases = await withTaskGroup(of: TeamAccountRefreshLease?.self) { group in
            for _ in 0..<8 { group.addTask { try? custody.beginRefresh(saved, now: 2_000) } }
            var leases = [TeamAccountRefreshLease]()
            for await result in group { if let result { leases.append(result) } }
            return leases
        }
        #expect(leases.count == 1)
        let lease = try #require(leases.first), marker = try #require(try custody.load(scope: scope))
        try custody.remove(marker, consent: true)
        let other = pair(access: "E", refresh: "F", account: "new-account")
        _ = try custody.saveInitial(other, scope: scope, now: 3_000, consent: true)
        #expect(throws: TeamAccountSessionError.staleOperation) {
            try custody.completeRefresh(lease, next: pair(access: "C", refresh: "D"), now: 4_000)
        }
        #expect(throws: TeamAccountSessionError.staleOperation) { try custody.remove(marker, consent: true) }
        #expect(try custody.load(scope: scope)?.usablePair(now: 4_000) == other)
    }

    @Test func scopeCorruptionUnavailableAndTimeFailuresDoNotDeleteOrReplace() throws {
        let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        #expect(throws: TeamAccountSessionError.scopeMismatch) { try custody.load(scope: self.scope("other-provider")) }
        #expect(throws: TeamAccountSessionError.invalidTime) { try saved.usablePair(now: 999) }
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try saved.usablePair(now: 10_000) }
        #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try custody.beginRefresh(saved, now: 30_000) }
        #expect(throws: TeamAccountSessionError.consentRequired) { try custody.remove(saved, consent: false) }
        backend.corrupt(kSecAttrGeneric as String, value: Data("wrong-generation".utf8))
        #expect(throws: TeamAccountSessionError.invalidStoredItem) { try custody.load(scope: scope) }
        backend.failRead()
        #expect(throws: TeamAccountSessionError.unavailable(errSecInteractionNotAllowed)) { try custody.load(scope: scope) }
        #expect(backend.writes == 1)
    }

    @Test func invalidExpiryTokenReuseAndPrecancelledWriteFailClosed() async throws {
        let backend = SessionMemoryKeychain(), scope = try scope(), custody = store(backend)
        for invalid in [pair(accessExpiry: 999), pair(accessExpiry: 906_001, sessionExpiry: 1_000_000),
                        pair(sessionExpiry: 2_592_006_001), pair(access: "A", refresh: "A")] {
            #expect(throws: TeamAccountSessionError.invalidSession) { try custody.saveInitial(invalid, scope: scope, now: 1_000, consent: true) }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true) }
        }
        await cancelled.value
        #expect(backend.writes == 0)
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        let lease = try custody.beginRefresh(saved, now: 2_000)
        for invalid in [pair(access: "B", refresh: "A"), pair(access: "C", refresh: "D", account: "other"),
                        pair(access: "C", refresh: "D", sessionExpiry: 30_001)] {
            #expect(throws: TeamAccountSessionError.invalidSession) { try custody.completeRefresh(lease, next: invalid, now: 3_000) }
        }
        #expect(try custody.load(scope: scope)?.phase == .refreshPending)
    }

    #if !SWIFT_PACKAGE && DEBUG
    @Test func actualKeychainAtomicGenerationMatchingInIsolatedSimulatorNamespace() throws {
        let custody = try TeamAccountSessionStore(simulatorTestService: "pinbook.session-test.\(UUID())")
        let scope = try scope()
        var cleanup: TeamAccountSessionSnapshot?
        defer { if let cleanup { try? custody.remove(cleanup, consent: true) } }
        let saved = try custody.saveInitial(pair(), scope: scope, now: 1_000, consent: true)
        cleanup = saved
        let lease = try custody.beginRefresh(saved, now: 2_000)
        cleanup = try custody.load(scope: scope)
        #expect(cleanup?.phase == .refreshPending)
        #expect(throws: TeamAccountSessionError.staleOperation) { try custody.beginRefresh(saved, now: 2_000) }
        let next = pair(access: "C", refresh: "D")
        let updated = try custody.completeRefresh(lease, next: next, now: 3_000)
        cleanup = updated
        #expect(try custody.load(scope: scope)?.usablePair(now: 3_001) == next)
        #expect(throws: TeamAccountSessionError.staleOperation) { try custody.remove(saved, consent: true) }
        try custody.remove(updated, consent: true); cleanup = nil
        #expect(try custody.load(scope: scope) == nil)
        // This test uses WhenUnlockedThisDeviceOnly, NOT passcode/non-backup proof.
    }
    #endif
}
