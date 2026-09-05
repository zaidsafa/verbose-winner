import CryptoKit
import Foundation
import Security

enum TeamJoinError: Error, Equatable {
    case consentRequired, invalidRecord, invalidInput, invalidTime, capacity
    case alreadyExists, staleOperation, bindingMismatch, unavailable(OSStatus)
}
enum TeamJoinPhase: String, Sendable { case pending, confirmed }
/// Local recovery metadata only, never current membership or account authority.
struct TeamJoinSnapshot: Equatable, TeamOnboardingDiagnostic {
    let scope: TeamDeviceScope
    let teamID: String
    let enrollmentID: String
    let role: TeamInvitationRole
    let invitationHash: String
    let generation: UUID
    let phase: TeamJoinPhase
    let checkedAt: Int64
    let membershipRevision: Int64?
}
protocol TeamJoinMetadataStore: Sendable {
    func load() throws -> Data?
    /// Atomic CAS. A thrown result may have committed: never dispatch on error.
    func replace(expected: Data?, next: Data) throws
}
private struct SystemTeamJoinMetadataAPI: TeamDeviceMetadataAPI {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
struct KeychainTeamJoinMetadata: TeamJoinMetadataStore {
    static let maximumBytes = 65_536
    private let service: String
    private let account = "bounded-join-index"
    private let keychain: any TeamDeviceMetadataAPI
    init() { service = "com.zaidsafa.pinbook.ios.team-join-custody.v1"; keychain = SystemTeamJoinMetadataAPI() }
    init(testService: String, keychain: any TeamDeviceMetadataAPI) throws {
        guard testService.hasPrefix("pinbook.join-test."), testService.utf8.count <= 128 else { throw TeamJoinError.invalidInput }
        service = testService; self.keychain = keychain
    }
    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    func load() throws -> Data? {
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true; query[kSecReturnAttributes as String] = true
        let (status, result) = keychain.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TeamJoinError.unavailable(status) }
        guard let fields = result as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == account,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String,
              let data = fields[kSecValueData as String] as? Data, (1...Self.maximumBytes).contains(data.count),
              fields[kSecAttrGeneric as String] as? Data == Data(SHA256.hash(data: data)) else { throw TeamJoinError.invalidRecord }
        return data
    }
    func replace(expected: Data?, next: Data) throws {
        guard (1...Self.maximumBytes).contains(next.count), expected.map({ (1...Self.maximumBytes).contains($0.count) }) ?? true else { throw TeamJoinError.invalidRecord }
        let payload: [String: Any] = [kSecValueData as String: next, kSecAttrGeneric as String: Data(SHA256.hash(data: next))]
        let status: OSStatus
        if let expected {
            var query = base
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            query[kSecAttrGeneric as String] = Data(SHA256.hash(data: expected))
            status = keychain.update(query, payload)
        } else {
            var attributes = base.merging(payload) { _, new in new }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            status = keychain.add(attributes)
        }
        if status == errSecDuplicateItem || status == errSecItemNotFound { throw TeamJoinError.staleOperation }
        guard status == errSecSuccess else { throw TeamJoinError.unavailable(status) }
    }
}

private struct TeamJoinIndex {
    var revision = UUID()
    var records = [TeamJoinSnapshot]()
    private static func uuid(_ value: Any?) -> UUID? {
        guard let raw = value as? String, let id = UUID(uuidString: raw), id.uuidString == raw else { return nil }
        return id
    }
    private static func scopeKey(_ scope: TeamDeviceScope) -> String {
        scope.audience + "\n" + scope.accountID + "\n" + scope.authorityEpoch
    }
    func checkCapacity() throws {
        let groups = Dictionary(grouping: records, by: { Self.scopeKey($0.scope) })
        guard records.count <= 80, groups.count <= 8, groups.values.allSatisfy({ $0.count <= 10 }) else { throw TeamJoinError.capacity }
    }
    func encoded() throws -> Data {
        try checkCapacity()
        let rows: [[String: Any]] = records.map { row in
            ["audience": row.scope.audience, "accountId": row.scope.accountID, "authorityEpoch": row.scope.authorityEpoch,
             "teamId": row.teamID, "enrollmentId": row.enrollmentID, "role": row.role.rawValue,
             "invitationHash": row.invitationHash, "generation": row.generation.uuidString,
             "phase": row.phase.rawValue, "checkedAt": row.checkedAt,
             "membershipRevision": row.membershipRevision as Any? ?? NSNull()]
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "revision": revision.uuidString, "records": rows], options: [.sortedKeys, .withoutEscapingSlashes])
        // Reserve room for future safe-time/revision digit growth and pending →
        // confirmed spelling. Capacity must not strand an existing recovery.
        let reservedGrowth = records.reduce(0) { total, row in
            total + (16 - String(row.checkedAt).count) +
                (row.membershipRevision.map { 16 - String($0).count } ?? 14)
        }
        guard data.count + reservedGrowth <= KeychainTeamJoinMetadata.maximumBytes else { throw TeamJoinError.capacity }
        return data
    }
    static func decoded(_ data: Data?) throws -> Self {
        guard let data else { return .init() }
        do {
            let object = try TeamStrictJSON.object(data, maximumBytes: KeychainTeamJoinMetadata.maximumBytes)
            guard Set(object.keys) == ["version", "revision", "records"], try TeamAuthWire.time(object, "version") == 1,
                  let revision = uuid(object["revision"]), let rows = object["records"] as? [[String: Any]], rows.count <= 80 else { throw TeamJoinError.invalidRecord }
            var result = Self(revision: revision), seen = Set<String>()
            for row in rows {
                guard Set(row.keys) == ["audience", "accountId", "authorityEpoch", "teamId", "enrollmentId", "role", "invitationHash", "generation", "phase", "checkedAt", "membershipRevision"],
                      let audience = row["audience"] as? String, let generation = uuid(row["generation"]),
                      let role = (row["role"] as? String).flatMap(TeamInvitationRole.init(rawValue:)),
                      let phase = (row["phase"] as? String).flatMap(TeamJoinPhase.init(rawValue:)),
                      let hash = row["invitationHash"] as? String, hash.utf8.count == 64,
                      hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw TeamJoinError.invalidRecord }
                let scope = try TeamDeviceScope(audience: audience, accountID: TeamAuthWire.string(row, "accountId"), authorityEpoch: TeamAuthWire.string(row, "authorityEpoch"))
                let team = try TeamAuthWire.string(row, "teamId")
                guard seen.insert(scopeKey(scope) + "\n" + team).inserted else { throw TeamJoinError.invalidRecord }
                let membership: Int64?
                if phase == .confirmed { membership = try TeamAuthWire.time(row, "membershipRevision") }
                else { guard row["membershipRevision"] is NSNull else { throw TeamJoinError.invalidRecord }; membership = nil }
                result.records.append(try .init(scope: scope, teamID: team, enrollmentID: TeamAuthWire.string(row, "enrollmentId"),
                    role: role, invitationHash: hash, generation: generation, phase: phase,
                    checkedAt: TeamAuthWire.time(row, "checkedAt"), membershipRevision: membership))
            }
            _ = try result.encoded() // Revalidate reserved recovery growth on load too.
            return result
        } catch { throw TeamJoinError.invalidRecord }
    }
}

/// Inactive, immutable dependencies with atomic metadata CAS across owners.
/// No account authority, network, auto retry, deletion, financial data or archive keys.
final class TeamJoinStore: @unchecked Sendable {
    private let storage: any TeamJoinMetadataStore
    private let clock: @Sendable () -> Int64
    init() { storage = KeychainTeamJoinMetadata(); clock = { Int64(Date().timeIntervalSince1970 * 1000) } }
    init(storage: any TeamJoinMetadataStore, clock: @escaping @Sendable () -> Int64) { self.storage = storage; self.clock = clock }
    private func now(since: Int64 = 0, before deadline: Int64? = nil) throws -> Int64 {
        try Task.checkCancellation()
        let value = clock()
        guard value >= since, value >= 0, value <= TeamAuthWire.maximumSafeTime else { throw TeamJoinError.invalidTime }
        if let deadline {
            guard value < deadline, deadline <= TeamAuthWire.maximumSafeTime else { throw TeamJoinError.invalidTime }
        }
        return value
    }
    private func read() throws -> (Data?, TeamJoinIndex) {
        _ = try now(); let data = try storage.load()
        let index = try TeamJoinIndex.decoded(data); _ = try now()
        return (data, index)
    }
    func list(scope: TeamDeviceScope) throws -> [TeamJoinSnapshot] {
        let (_, index) = try read(), rows = index.records.filter { $0.scope == scope }
        _ = try now(since: rows.map(\.checkedAt).max() ?? 0)
        return rows.sorted { $0.teamID < $1.teamID }
    }
    func deleteAccount(audience: String, accountID: String,
                       authorityEpoch: String) throws {
        let scope = try TeamDeviceScope(audience: audience, accountID: accountID,
                                        authorityEpoch: authorityEpoch)
        let (raw, old) = try read()
        var index = old
        index.records.removeAll { $0.scope == scope }
        guard index.records.count != old.records.count else { return }
        index.revision = UUID()
        try storage.replace(expected: raw, next: index.encoded())
    }
    func load(scope: TeamDeviceScope, teamID: String) throws -> TeamJoinSnapshot? {
        guard TeamAuthWire.identifier(teamID) else { throw TeamJoinError.invalidInput }
        return try list(scope: scope).first { $0.teamID == teamID }
    }
    func requireCurrent(_ expected: TeamJoinSnapshot) throws {
        guard try load(scope: expected.scope, teamID: expected.teamID) == expected else { throw TeamJoinError.staleOperation }
    }
    /// Separate membership consent and current account/device/epoch checks must
    /// precede this operation. Successful persistence is a prerequisite for the
    /// owner's one-use accept, not an independently spendable authorization token.
    func begin(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole,
               expiresAt: Int64, registration: TeamRegisteredDevice, consent: Bool) throws -> TeamJoinSnapshot {
        guard consent else { throw TeamJoinError.consentRequired }
        guard TeamAuthWire.credential(token), TeamAuthWire.identifier(teamID),
              TeamAuthWire.identifier(registration.enrollmentID), TeamAuthWire.identifier(registration.deviceID),
              TeamAuthWire.credential(registration.keyThumbprint), registration.accountID == scope.accountID,
              registration.authorityEpoch == scope.authorityEpoch else { throw TeamJoinError.bindingMismatch }
        let (raw, old) = try read(); var index = old
        guard !index.records.contains(where: { $0.scope == scope && $0.teamID == teamID }) else { throw TeamJoinError.alreadyExists }
        let time = try now(since: index.records.filter { $0.scope == scope }.map(\.checkedAt).max() ?? 0)
        guard expiresAt > time, expiresAt <= TeamAuthWire.maximumSafeTime, expiresAt - time <= 604_805_000 else { throw TeamJoinError.invalidTime }
        let next = TeamJoinSnapshot(scope: scope, teamID: teamID, enrollmentID: registration.enrollmentID, role: role,
            invitationHash: Self.invitationHash(token), generation: UUID(), phase: .pending, checkedAt: time, membershipRevision: nil)
        index.records.append(next); index.revision = UUID()
        let encoded = try index.encoded()
        guard try now(since: time) < expiresAt else { throw TeamJoinError.invalidTime }
        try storage.replace(expected: raw, next: encoded)
        // Unknown/expired completion must not permit dispatch; committed metadata
        // is intentionally retained for read-only recovery, not rolled back.
        guard try now(since: time) < expiresAt else { throw TeamJoinError.invalidTime }
        try requireCurrent(next)
        guard try now(since: time) < expiresAt else { throw TeamJoinError.invalidTime }
        return next
    }
    func beginRecovery(_ expected: TeamJoinSnapshot) throws -> TeamJoinSnapshot {
        try replace(expected) { row, time in
            .init(scope: row.scope, teamID: row.teamID, enrollmentID: row.enrollmentID, role: row.role,
                invitationHash: row.invitationHash, generation: UUID(), phase: row.phase,
                checkedAt: time, membershipRevision: row.membershipRevision)
        }
    }
    /// Read-only matching for a reopened ORIGINAL invitation. It neither proves
    /// server eligibility nor reserves/clears the existing uncertain attempt.
    func retryCandidate(scope: TeamDeviceScope, token: String, teamID: String, role: TeamInvitationRole) throws -> TeamJoinSnapshot {
        guard TeamAuthWire.credential(token), TeamAuthWire.identifier(teamID) else { throw TeamJoinError.invalidInput }
        guard let row = try load(scope: scope, teamID: teamID), row.phase == .pending,
              row.role == role, row.invitationHash == Self.invitationHash(token) else { throw TeamJoinError.bindingMismatch }
        return row
    }
    /// After one exact eligible-pending lookup and NEW user consent, the owner
    /// commits a new generation before ONE same-identity accept. The deadline is
    /// the owner's consent/access bound, not an invented invitation expiry. Server
    /// expiry remains authoritative; owner must additionally check monotonic time,
    /// exact account/device generation and current registration around this IO.
    func beginExplicitRetry(_ expected: TeamJoinSnapshot, token: String, consentExpiresAt: Int64,
                            registration: TeamRegisteredDevice, consent: Bool) throws -> TeamJoinSnapshot {
        guard consent else { throw TeamJoinError.consentRequired }
        guard expected.phase == .pending, expected.membershipRevision == nil,
              TeamAuthWire.credential(token), expected.invitationHash == Self.invitationHash(token),
              registration.accountID == expected.scope.accountID,
              registration.authorityEpoch == expected.scope.authorityEpoch,
              registration.enrollmentID == expected.enrollmentID,
              TeamAuthWire.identifier(registration.enrollmentID), TeamAuthWire.identifier(registration.deviceID),
              TeamAuthWire.credential(registration.keyThumbprint) else { throw TeamJoinError.bindingMismatch }
        return try replace(expected, before: consentExpiresAt) { row, time in
            guard consentExpiresAt - time <= 300_000 else { throw TeamJoinError.invalidTime }
            return .init(scope: row.scope, teamID: row.teamID, enrollmentID: row.enrollmentID, role: row.role,
                invitationHash: row.invitationHash, generation: UUID(), phase: .pending,
                checkedAt: time, membershipRevision: nil)
        }
    }
    /// Only a freshly bound accept/current result can confirm; no null/error API.
    func confirm(_ expected: TeamJoinSnapshot, result: TeamMembership) throws -> TeamJoinSnapshot {
        try replace(expected) { row, time in
            guard result.teamID == row.teamID, result.accountID == row.scope.accountID,
                  result.enrollmentID == row.enrollmentID, result.role.rawValue == row.role.rawValue,
                  result.revision >= (row.membershipRevision ?? 0), result.revision <= TeamAuthWire.maximumSafeTime else { throw TeamJoinError.bindingMismatch }
            return .init(scope: row.scope, teamID: row.teamID, enrollmentID: row.enrollmentID, role: row.role,
                invitationHash: row.invitationHash, generation: UUID(), phase: .confirmed,
                checkedAt: time, membershipRevision: result.revision)
        }
    }
    private func replace(_ expected: TeamJoinSnapshot, before deadline: Int64? = nil,
                         transform: (TeamJoinSnapshot, Int64) throws -> TeamJoinSnapshot) throws -> TeamJoinSnapshot {
        let (raw, old) = try read(); var index = old
        guard let position = index.records.firstIndex(where: { $0.scope == expected.scope && $0.teamID == expected.teamID }),
              index.records[position] == expected else { throw TeamJoinError.staleOperation }
        let latest = index.records.filter { $0.scope == expected.scope }.map(\.checkedAt).max() ?? expected.checkedAt
        let next = try transform(expected, now(since: latest, before: deadline))
        index.records[position] = next; index.revision = UUID()
        let encoded = try index.encoded(); _ = try now(since: next.checkedAt, before: deadline)
        try storage.replace(expected: raw, next: encoded)
        _ = try now(since: next.checkedAt, before: deadline)
        try requireCurrent(next)
        _ = try now(since: next.checkedAt, before: deadline); return next
    }
    static func invitationHash(_ token: String) -> String {
        SHA256.hash(data: Data(("pinbook-team-invite-v1\0" + token).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
