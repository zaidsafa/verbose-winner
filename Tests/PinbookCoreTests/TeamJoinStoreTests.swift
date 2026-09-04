import CryptoKit
import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private let joinCode = String(repeating: "E", count: 42) + "A"
private final class JoinClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_000
    func now() -> Int64 { lock.withLock { value } }
    func set(_ next: Int64) { lock.withLock { value = next } }
}
private final class JoinMemory: TeamJoinMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var count = 0
    private var failure = 0
    private var locked = false
    private var before: (@Sendable () throws -> Void)?
    private var after: (@Sendable () throws -> Void)?
    private var onRead: (@Sendable () throws -> Void)?
    func load() throws -> Data? {
        let (saved, denied, callback) = lock.withLock { (data, locked, onRead) }
        guard !denied else { throw TeamJoinError.unavailable(errSecInteractionNotAllowed) }
        try callback?(); return saved
    }
    func replace(expected: Data?, next: Data) throws {
        let callbacks = lock.withLock { (before, after) }
        try callbacks.0?()
        try lock.withLock {
            guard !locked else { throw TeamJoinError.unavailable(errSecInteractionNotAllowed) }
            guard data == expected else { throw TeamJoinError.staleOperation }
            let fail = failure; failure = 0
            if fail == 1 { throw TeamJoinError.unavailable(errSecNotAvailable) }
            data = next; count += 1
            if fail == 2 { throw TeamJoinError.unavailable(errSecNotAvailable) }
        }
        try callbacks.1?()
    }
    var bytes: Data? { lock.withLock { data } }
    var writes: Int { lock.withLock { count } }
    func fail(afterCommit: Bool) { lock.withLock { failure = afterCommit ? 2 : 1 } }
    func setLocked(_ value: Bool) { lock.withLock { locked = value } }
    func beforeWrite(_ callback: @escaping @Sendable () throws -> Void) { lock.withLock { before = callback } }
    func afterWrite(_ callback: @escaping @Sendable () throws -> Void) { lock.withLock { after = callback } }
    func afterRead(_ callback: @escaping @Sendable () throws -> Void) { lock.withLock { onRead = callback } }
    func corrupt(_ transform: (Data) throws -> Data) throws {
        try lock.withLock { data = try transform(#require(data)) }
    }
}
private struct JoinFixture {
    let memory = JoinMemory()
    let clock = JoinClock()
    let scope: TeamDeviceScope
    init(account: String = "public-account") throws {
        scope = try .init(audience: "https://pinbook.example", accountID: account, authorityEpoch: "public-epoch")
    }
    func owner() -> TeamJoinStore { .init(storage: memory, clock: { clock.now() }) }
    func registration(scope: TeamDeviceScope? = nil, enrollment: String = "public-enrollment") -> TeamRegisteredDevice {
        .init(enrollmentID: enrollment, accountID: (scope ?? self.scope).accountID, deviceID: "public-device",
              keyThumbprint: String(repeating: "A", count: 43), authorityEpoch: (scope ?? self.scope).authorityEpoch)
    }
    func begin(_ owner: TeamJoinStore, team: String = "public-team", scope: TeamDeviceScope? = nil) throws -> TeamJoinSnapshot {
        try owner.begin(scope: scope ?? self.scope, token: joinCode, teamID: team, role: .reviewer,
            expiresAt: 20_000, registration: registration(scope: scope), consent: true)
    }
    func membership(_ row: TeamJoinSnapshot, revision: Int64 = 1) -> TeamMembership {
        .init(teamID: row.teamID, accountID: row.scope.accountID, enrollmentID: row.enrollmentID, role: .reviewer, revision: revision)
    }
}
private final class JoinBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var arrivals = 0
    private let signal = DispatchSemaphore(value: 0)
    func enter() throws {
        let ready = lock.withLock { arrivals += 1; return arrivals == 2 }
        if ready { signal.signal(); signal.signal() }
        guard signal.wait(timeout: .now() + 5) == .success else { throw TeamJoinError.unavailable(errSecNotAvailable) }
    }
}
private func onJoinQueue(_ operation: @escaping @Sendable () -> Bool) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: operation()) }
    }
}

struct TeamJoinStoreTests {
    @Test func previewIsReadOnlyAndReopenRecoversExpiredInvitationWithoutRawToken() throws {
        let f = try JoinFixture(), owner = f.owner()
        #expect(try owner.list(scope: f.scope).isEmpty)
        #expect(f.memory.writes == 0)
        #expect(throws: TeamJoinError.consentRequired) {
            try owner.begin(scope: f.scope, token: joinCode, teamID: "public-team", role: .reviewer,
                expiresAt: 20_000, registration: f.registration(), consent: false)
        }
        let pending = try f.begin(owner)
        #expect(pending.phase == .pending && pending.membershipRevision == nil)
        #expect(!String(reflecting: pending).contains(joinCode) && Mirror(reflecting: pending).children.isEmpty)
        let bytes = try #require(f.memory.bytes), text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(joinCode) && !text.contains("accessToken") && !text.contains("refreshToken"))
        f.clock.set(30_000) // Original link has expired; recovery never needs it.
        let reopened = f.owner(), recovered = try reopened.beginRecovery(pending)
        #expect(recovered.generation != pending.generation)
        #expect(recovered.teamID == pending.teamID && recovered.enrollmentID == pending.enrollmentID)
        let confirmed = try reopened.confirm(recovered, result: f.membership(recovered))
        #expect(confirmed.phase == .confirmed && confirmed.membershipRevision == 1)
        #expect(try f.owner().load(scope: f.scope, teamID: pending.teamID) == confirmed)
        #expect(throws: TeamJoinError.staleOperation) { try owner.confirm(pending, result: f.membership(pending)) }
    }
    @Test func staleRecoveryForeignResponsesAndRevisionRollbackCannotOverwrite() throws {
        let f = try JoinFixture(), owner = f.owner(), first = try f.begin(owner)
        let recovery = try owner.beginRecovery(first)
        #expect(throws: TeamJoinError.staleOperation) { try owner.beginRecovery(first) }
        for result in [
            TeamMembership(teamID: "foreign", accountID: f.scope.accountID, enrollmentID: first.enrollmentID, role: .reviewer, revision: 1),
            TeamMembership(teamID: first.teamID, accountID: "foreign", enrollmentID: first.enrollmentID, role: .reviewer, revision: 1),
            TeamMembership(teamID: first.teamID, accountID: f.scope.accountID, enrollmentID: "foreign", role: .reviewer, revision: 1),
            TeamMembership(teamID: first.teamID, accountID: f.scope.accountID, enrollmentID: first.enrollmentID, role: .owner, revision: 1),
            f.membership(first, revision: -1), f.membership(first, revision: TeamAuthWire.maximumSafeTime + 1)
        ] {
            #expect(throws: TeamJoinError.bindingMismatch) { try owner.confirm(recovery, result: result) }
            #expect(try owner.load(scope: f.scope, teamID: first.teamID) == recovery)
        }
        let saved = try owner.confirm(recovery, result: f.membership(recovery, revision: 4))
        let checking = try owner.beginRecovery(saved)
        #expect(throws: TeamJoinError.bindingMismatch) { try owner.confirm(checking, result: f.membership(checking, revision: 3)) }
        #expect(try owner.confirm(checking, result: f.membership(checking, revision: 4)).membershipRevision == 4)
        #expect(throws: TeamJoinError.alreadyExists) { try f.begin(owner) }
    }
    @Test func uncertainWritesRemainAbsentOrWholeAndNeverReplay() throws {
        for after in [false, true] {
            let f = try JoinFixture(), owner = f.owner()
            f.memory.fail(afterCommit: after)
            #expect(throws: TeamJoinError.unavailable(errSecNotAvailable)) { try f.begin(owner) }
            let saved = try f.owner().load(scope: f.scope, teamID: "public-team")
            #expect((saved != nil) == after)
            #expect(f.memory.writes == (after ? 1 : 0))
            if let saved {
                #expect(throws: TeamJoinError.alreadyExists) { try f.begin(owner) }
                f.memory.fail(afterCommit: true)
                #expect(throws: TeamJoinError.unavailable(errSecNotAvailable)) { try owner.confirm(saved, result: f.membership(saved)) }
                #expect(try f.owner().load(scope: f.scope, teamID: saved.teamID)?.phase == .confirmed)
                #expect(throws: TeamJoinError.staleOperation) { try owner.beginRecovery(saved) }
            }
        }
    }
    @Test func clockExpiryDuringCommitAndPostcommitReadNeverPermitDispatch() throws {
        for point in ["commit", "read"] {
            let f = try JoinFixture(), owner = f.owner()
            if point == "commit" { f.memory.afterWrite { f.clock.set(20_000) } }
            else { f.memory.afterRead { if f.memory.writes == 1 { f.clock.set(20_000) } } }
            #expect(throws: TeamJoinError.invalidTime) { try f.begin(owner) }
            #expect(f.memory.writes == 1)
            #expect(try f.owner().load(scope: f.scope, teamID: "public-team")?.phase == .pending)
        }
    }
    @Test func lockedRollbackCancelledAndInvalidInputsHaveNoWrite() async throws {
        let f = try JoinFixture(), owner = f.owner()
        f.memory.setLocked(true)
        #expect(throws: TeamJoinError.unavailable(errSecInteractionNotAllowed)) { try f.begin(owner) }
        f.memory.setLocked(false)
        for code in ["", joinCode + "=", " " + joinCode] {
            #expect(throws: TeamJoinError.bindingMismatch) {
                try owner.begin(scope: f.scope, token: code, teamID: "public-team", role: .member,
                    expiresAt: 20_000, registration: f.registration(), consent: true)
            }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try f.begin(owner) }
        }
        await cancelled.value
        #expect(f.memory.writes == 0)
        let pending = try f.begin(owner)
        f.clock.set(999)
        #expect(throws: TeamJoinError.invalidTime) { try owner.beginRecovery(pending) }
        #expect(throws: TeamJoinError.invalidTime) { try owner.list(scope: f.scope) }
        #expect(throws: TeamJoinError.invalidTime) { try f.begin(owner, team: "another") }
        #expect(f.memory.writes == 1)
        f.clock.set(2_000)
        _ = try f.begin(owner, team: "newer-team")
        f.clock.set(1_500)
        #expect(throws: TeamJoinError.invalidTime) { try owner.beginRecovery(pending) }
        #expect(f.memory.writes == 2)
    }
    @Test func scopeIsolationSortingAndCapacityRetainExistingRecovery() throws {
        let f = try JoinFixture(), owner = f.owner()
        var first: TeamJoinSnapshot?
        for account in 0..<8 {
            let scope = try TeamDeviceScope(audience: f.scope.audience, accountID: "public-\(account)", authorityEpoch: f.scope.authorityEpoch)
            for team in (0..<10).reversed() {
                let row = try f.begin(owner, team: "team-\(team)", scope: scope)
                if first == nil { first = row }
            }
            #expect(try owner.list(scope: scope).map(\.teamID) == (0..<10).map { "team-\($0)" })
            #expect(throws: TeamJoinError.capacity) { try f.begin(owner, team: "eleventh", scope: scope) }
        }
        #expect(try owner.list(scope: f.scope).isEmpty)
        #expect(throws: TeamJoinError.capacity) { try f.begin(owner) }
        let row = try #require(first), recovery = try owner.beginRecovery(row)
        #expect(recovery.generation != row.generation)
        #expect(try owner.confirm(recovery, result: f.membership(recovery)).phase == .confirmed)
        #expect(f.memory.writes == 82)
    }
    @Test func duplicateFieldsRowsInvalidPhasesAndOversizedBytesFailWithoutClearing() throws {
        for mode in ["duplicate-key", "duplicate-row", "phase", "role", "revision", "number", "size"] {
            let f = try JoinFixture(), owner = f.owner()
            _ = try f.begin(owner)
            try f.memory.corrupt { data in
                if mode == "size" { return Data(repeating: 32, count: 65_537) }
                if mode == "duplicate-key" { return Data("{\"version\":1,\"version\":1}".utf8) }
                if mode == "number" { return Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"checkedAt\":1000", with: "\"checkedAt\":1e3").utf8) }
                var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                var rows = try #require(object["records"] as? [[String: Any]])
                if mode == "duplicate-row" { rows.append(rows[0]) }
                if mode == "phase" { rows[0]["phase"] = "confirmed" }
                if mode == "role" { rows[0]["role"] = "OWNER" }
                if mode == "revision" { rows[0]["membershipRevision"] = 3 }
                object["records"] = rows
                return try JSONSerialization.data(withJSONObject: object)
            }
            let corrupted = f.memory.bytes
            #expect(throws: TeamJoinError.invalidRecord) { try owner.list(scope: f.scope) }
            #expect(throws: TeamJoinError.invalidRecord) { try f.begin(owner, team: "another") }
            #expect(f.memory.bytes == corrupted && f.memory.writes == 1)
        }
    }
    @Test func byteCapacityReservesRoomForFutureRecoveryAndRevisionGrowth() throws {
        let f = try JoinFixture(), owner = f.owner()
        let audience = "https://" + Array(repeating: String(repeating: "a", count: 60), count: 4).joined(separator: ".") + ".example"
        var first: TeamJoinSnapshot?, inserted = 0, hitCapacity = false
        outer: for account in 0..<8 {
            let scope = try TeamDeviceScope(audience: audience, accountID: "a\(account)" + String(repeating: "b", count: 126),
                authorityEpoch: String(repeating: "c", count: 128))
            for team in 0..<10 {
                do {
                    let row = try owner.begin(scope: scope, token: joinCode, teamID: "t\(team)" + String(repeating: "d", count: 126),
                        role: .reviewer, expiresAt: 20_000,
                        registration: f.registration(scope: scope, enrollment: String(repeating: "e", count: 128)), consent: true)
                    inserted += 1; if first == nil { first = row }
                } catch TeamJoinError.capacity { hitCapacity = true; break outer }
            }
        }
        #expect(hitCapacity && inserted > 0 && inserted < 80)
        #expect(f.memory.writes == inserted)
        f.clock.set(TeamAuthWire.maximumSafeTime)
        let row = try #require(first), recovery = try owner.beginRecovery(row)
        let confirmed = try owner.confirm(recovery, result: f.membership(recovery, revision: TeamAuthWire.maximumSafeTime))
        #expect(confirmed.checkedAt == TeamAuthWire.maximumSafeTime)
        #expect(confirmed.membershipRevision == TeamAuthWire.maximumSafeTime)
        #expect(try #require(f.memory.bytes).count <= KeychainTeamJoinMetadata.maximumBytes)
    }
    @Test func twoOwnersCannotBothCommitSameTeamOrLoseAnotherTeam() async throws {
        for secondTeam in ["public-team", "different-team"] {
            let f = try JoinFixture(), a = f.owner(), b = f.owner(), barrier = JoinBarrier()
            f.memory.beforeWrite { try barrier.enter() }
            async let first = onJoinQueue { do { _ = try f.begin(a); return true } catch { #expect(error as? TeamJoinError == .staleOperation); return false } }
            async let second = onJoinQueue { do { _ = try f.begin(b, team: secondTeam); return true } catch { #expect(error as? TeamJoinError == .staleOperation); return false } }
            let winners = await [first, second]
            #expect(winners.filter { $0 }.count == 1)
            #expect(try a.list(scope: f.scope).count == 1 && f.memory.writes == 1)
        }
    }
    @Test func exactOriginEpochAndEnrollmentAreRequiredAndForgedSnapshotCannotConfirm() throws {
        let f = try JoinFixture(), owner = f.owner(), row = try f.begin(owner)
        for scope in [
            try TeamDeviceScope(audience: "https://another.example", accountID: f.scope.accountID, authorityEpoch: f.scope.authorityEpoch),
            try TeamDeviceScope(audience: f.scope.audience, accountID: f.scope.accountID, authorityEpoch: "new-epoch")
        ] {
            #expect(try owner.list(scope: scope).isEmpty)
            let forged = TeamJoinSnapshot(scope: scope, teamID: row.teamID, enrollmentID: row.enrollmentID,
                role: row.role, invitationHash: row.invitationHash, generation: row.generation, phase: row.phase,
                checkedAt: row.checkedAt, membershipRevision: row.membershipRevision)
            #expect(throws: TeamJoinError.staleOperation) { try owner.beginRecovery(forged) }
        }
        let wrongRegistration = TeamRegisteredDevice(enrollmentID: "enrollment", accountID: "foreign-account",
            deviceID: "device", keyThumbprint: String(repeating: "A", count: 43), authorityEpoch: f.scope.authorityEpoch)
        #expect(throws: TeamJoinError.bindingMismatch) {
            try owner.begin(scope: f.scope, token: joinCode, teamID: "another", role: .member,
                expiresAt: 20_000, registration: wrongRegistration, consent: true)
        }
        let forged = TeamJoinSnapshot(scope: row.scope, teamID: row.teamID, enrollmentID: "foreign",
            role: row.role, invitationHash: row.invitationHash, generation: row.generation, phase: row.phase,
            checkedAt: row.checkedAt, membershipRevision: row.membershipRevision)
        #expect(throws: TeamJoinError.staleOperation) { try owner.confirm(forged, result: f.membership(forged)) }
        #expect(f.memory.writes == 1)
    }
    @Test func composedKeychainStoreReopenRefusesCorruptionAndUnavailableRead() throws {
        let f = try JoinFixture(), backend = SessionMemoryKeychain()
        let metadata = try KeychainTeamJoinMetadata(testService: "pinbook.join-test.composed", keychain: backend)
        let owner = TeamJoinStore(storage: metadata, clock: { f.clock.now() })
        let pending = try f.begin(owner)
        let reopened = TeamJoinStore(storage: metadata, clock: { f.clock.now() })
        #expect(try reopened.load(scope: f.scope, teamID: pending.teamID) == pending)
        let next = try reopened.beginRecovery(pending)
        #expect(try owner.confirm(next, result: f.membership(next)).phase == .confirmed)
        let preserved = backend.bytes
        backend.corrupt(kSecAttrGeneric as String, value: Data(repeating: 0, count: 32))
        #expect(throws: TeamJoinError.invalidRecord) { try owner.list(scope: f.scope) }
        #expect(backend.bytes == preserved)
        backend.failRead()
        #expect(throws: TeamJoinError.unavailable(errSecInteractionNotAllowed)) { try owner.list(scope: f.scope) }
    }
    @Test func keychainUsesDedicatedPasscodePolicyAndExactPayloadCAS() throws {
        let backend = SessionMemoryKeychain()
        let metadata = try KeychainTeamJoinMetadata(testService: "pinbook.join-test.policy", keychain: backend)
        let a = Data("public-one".utf8), b = Data("public-two".utf8)
        #expect(try metadata.load() == nil)
        try metadata.replace(expected: nil, next: a)
        #expect(backend.protection == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
        #expect(backend.synchronizes == false)
        #expect(throws: TeamJoinError.staleOperation) { try metadata.replace(expected: nil, next: b) }
        #expect(throws: TeamJoinError.staleOperation) { try metadata.replace(expected: b, next: a) }
        try metadata.replace(expected: a, next: b)
        #expect(try metadata.load() == b)
        backend.failUpdate(afterCommit: true)
        #expect(throws: TeamJoinError.unavailable(errSecNotAvailable)) { try metadata.replace(expected: b, next: a) }
        #expect(try metadata.load() == a)
        backend.corrupt(kSecAttrAccessible as String, value: kSecAttrAccessibleAfterFirstUnlock)
        #expect(throws: TeamJoinError.invalidRecord) { try metadata.load() }
        #expect(throws: TeamJoinError.staleOperation) { try metadata.replace(expected: a, next: b) }
        #expect(backend.bytes == a)
    }
}
