import Foundation
import Security

public enum TeamAccountSessionError: Error, Equatable {
    case consentRequired, alreadyExists, scopeMismatch, invalidStoredItem
    case staleOperation, reauthenticationRequired, invalidTime, invalidSession
    case unavailable(OSStatus)
}

/// Selected from trusted configuration, never from an ID token or remote payload.
public struct TeamAccountSessionScope: Sendable, Equatable {
    public let origin: URL
    public let providerID: String
    public init(origin: URL, providerID: String) throws {
        _ = try TeamAuthHTTPClient(origin: origin) // Validation only; does not connect.
        guard TeamAuthWire.identifier(providerID), origin.absoluteString.utf8.count <= 1024 else {
            throw TeamAccountSessionError.invalidSession
        }
        self.origin = origin.appendingPathComponent("")
        self.providerID = providerID
    }
}

public enum TeamAccountSessionPhase: String, Sendable { case active, refreshPending }

/// A pending record deliberately contains NO old credential. It is a durable
/// reauthentication barrier, not an instruction to retry the previous refresh.
public struct TeamAccountSessionSnapshot: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let scope: TeamAccountSessionScope
    public let phase: TeamAccountSessionPhase
    public let accountID: String
    public let sessionID: String
    public let sessionExpiresAt: Int64
    let generation: UUID
    let observedAt: Int64
    let pair: TeamAuthSessionPair?
    public var description: String { "TeamAccountSessionSnapshot(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    public func usablePair(now: Int64) throws -> TeamAuthSessionPair {
        try TeamAccountSessionCodec.checkClock(now, since: observedAt)
        guard phase == .active, let pair, now < pair.accessExpiresAt,
              now < sessionExpiresAt else { throw TeamAccountSessionError.reauthenticationRequired }
        return pair
    }
}

/// Volatile dispatch capability returned ONLY after the durable marker write
/// succeeds. Never persist this value or put it in a portable backup.
public struct TeamAccountRefreshLease: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let previousPair: TeamAuthSessionPair
    let marker: TeamAccountSessionSnapshot
    public var description: String { "TeamAccountRefreshLease(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol TeamAccountSessionKeychain: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}
private struct SystemTeamAccountSessionKeychain: TeamAccountSessionKeychain {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

enum TeamAccountSessionCodec {
    static let maximumBytes = 4096
    static func checkClock(_ now: Int64, since: Int64 = 0) throws {
        guard now >= since, now >= 0, now <= TeamAuthWire.maximumSafeTime else {
            throw TeamAccountSessionError.invalidTime
        }
    }
    static func checkNewPair(_ pair: TeamAuthSessionPair, now: Int64) throws {
        try checkClock(now)
        guard TeamAuthWire.identifier(pair.accountID), TeamAuthWire.identifier(pair.sessionID),
              TeamAuthWire.credential(pair.accessToken), TeamAuthWire.credential(pair.refreshToken),
              pair.accessToken != pair.refreshToken,
              pair.accessExpiresAt > now, pair.sessionExpiresAt > now,
              pair.accessExpiresAt <= pair.sessionExpiresAt,
              pair.accessExpiresAt <= TeamAuthWire.maximumSafeTime,
              pair.sessionExpiresAt <= TeamAuthWire.maximumSafeTime,
              pair.accessExpiresAt - now <= 905_000,
              pair.sessionExpiresAt - now <= 2_592_005_000 else {
            throw TeamAccountSessionError.invalidSession
        }
    }
    static func active(pair: TeamAuthSessionPair, scope: TeamAccountSessionScope, now: Int64) throws -> TeamAccountSessionSnapshot {
        try checkNewPair(pair, now: now)
        return TeamAccountSessionSnapshot(scope: scope, phase: .active, accountID: pair.accountID,
            sessionID: pair.sessionID, sessionExpiresAt: pair.sessionExpiresAt,
            generation: UUID(), observedAt: now, pair: pair)
    }
    static func encode(_ value: TeamAccountSessionSnapshot) throws -> Data {
        var fields: [String: Any] = ["version": 1, "origin": value.scope.origin.absoluteString,
            "providerId": value.scope.providerID, "phase": value.phase.rawValue,
            "accountId": value.accountID, "sessionId": value.sessionID,
            "sessionExpiresAt": value.sessionExpiresAt, "observedAt": value.observedAt,
            "generation": value.generation.uuidString]
        if let pair = value.pair {
            fields["accessToken"] = pair.accessToken; fields["refreshToken"] = pair.refreshToken
            fields["accessExpiresAt"] = pair.accessExpiresAt
        }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw TeamAccountSessionError.invalidStoredItem }
        return data
    }
    static func decode(_ data: Data) throws -> TeamAccountSessionSnapshot {
        do {
            guard data.count <= maximumBytes,
                  let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let phaseText = raw["phase"] as? String,
                  let phase = TeamAccountSessionPhase(rawValue: phaseText) else {
                throw TeamAccountSessionError.invalidStoredItem
            }
            var keys: Set<String> = ["version", "origin", "providerId", "phase", "accountId", "sessionId",
                                     "sessionExpiresAt", "observedAt", "generation"]
            if phase == .active { keys.formUnion(["accessToken", "refreshToken", "accessExpiresAt"]) }
            let fields = try TeamAuthWire.object(data, keys: keys)
            guard try TeamAuthWire.time(fields, "version") == 1,
                  let rawOrigin = fields["origin"] as? String, let origin = URL(string: rawOrigin),
                  let rawGeneration = fields["generation"] as? String,
                  let generation = UUID(uuidString: rawGeneration), generation.uuidString == rawGeneration else {
                throw TeamAccountSessionError.invalidStoredItem
            }
            let scope = try TeamAccountSessionScope(origin: origin, providerID: TeamAuthWire.string(fields, "providerId"))
            guard scope.origin.absoluteString == rawOrigin else { throw TeamAccountSessionError.invalidStoredItem }
            let accountID = try TeamAuthWire.string(fields, "accountId")
            let sessionID = try TeamAuthWire.string(fields, "sessionId")
            let expiresAt = try TeamAuthWire.time(fields, "sessionExpiresAt")
            let observedAt = try TeamAuthWire.time(fields, "observedAt")
            guard expiresAt > observedAt, expiresAt - observedAt <= 2_592_005_000 else {
                throw TeamAccountSessionError.invalidStoredItem
            }
            let pair: TeamAuthSessionPair?
            if phase == .active {
                pair = try TeamAuthSessionPair(accountID: accountID, sessionID: sessionID,
                    accessToken: TeamAuthWire.string(fields, "accessToken", secret: true),
                    refreshToken: TeamAuthWire.string(fields, "refreshToken", secret: true),
                    accessExpiresAt: TeamAuthWire.time(fields, "accessExpiresAt"), sessionExpiresAt: expiresAt)
                try checkNewPair(pair!, now: observedAt)
            } else { pair = nil }
            return TeamAccountSessionSnapshot(scope: scope, phase: phase, accountID: accountID,
                sessionID: sessionID, sessionExpiresAt: expiresAt, generation: generation,
                observedAt: observedAt, pair: pair)
        } catch { throw TeamAccountSessionError.invalidStoredItem }
    }
}

/// Separate, inactive account-session custody. Public construction ALWAYS uses
/// passcode-required/unlocked/non-sync/non-backup Keychain protection. Removing a
/// passcode may force reauthentication; archive keys and user files are untouched.
public struct TeamAccountSessionStore: Sendable {
    private let service: String
    private let keychain: any TeamAccountSessionKeychain
    private let accessibility: String
    private let account = "active-account-session"

    public init() {
        service = "com.zaidsafa.pinbook.ios.team-account-session.v1"
        keychain = SystemTeamAccountSessionKeychain()
        accessibility = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String
    }
    // Synthetic namespace only; never changes an existing production item/class.
    init(testService: String, keychain: any TeamAccountSessionKeychain) {
        service = testService; self.keychain = keychain
        accessibility = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String
    }
    #if DEBUG
    // Tests atomic SecItem generation matching in Simulator, which cannot prove
    // passcode-only custody. Uses a separate caller-generated test namespace.
    init(simulatorTestService: String) throws {
        guard simulatorTestService.hasPrefix("pinbook.session-test."), simulatorTestService.count <= 128 else {
            throw TeamAccountSessionError.invalidSession
        }
        service = simulatorTestService; keychain = SystemTeamAccountSessionKeychain()
        accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    }
    #endif

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    private func matching(_ value: TeamAccountSessionSnapshot) -> [String: Any] {
        var query = base
        query[kSecAttrGeneric as String] = Data(value.generation.uuidString.utf8)
        query[kSecAttrAccessible as String] = accessibility
        return query
    }
    private func attributes(_ value: TeamAccountSessionSnapshot) throws -> [String: Any] {
        [kSecValueData as String: try TeamAccountSessionCodec.encode(value),
         kSecAttrGeneric as String: Data(value.generation.uuidString.utf8)]
    }
    public func load(scope: TeamAccountSessionScope) throws -> TeamAccountSessionSnapshot? {
        try Task.checkCancellation()
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true; query[kSecReturnAttributes as String] = true
        let (status, result) = keychain.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TeamAccountSessionError.unavailable(status) }
        guard let fields = result as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == account,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String == accessibility,
              let data = fields[kSecValueData as String] as? Data else {
            throw TeamAccountSessionError.invalidStoredItem
        }
        let value = try TeamAccountSessionCodec.decode(data)
        guard fields[kSecAttrGeneric as String] as? Data == Data(value.generation.uuidString.utf8) else {
            throw TeamAccountSessionError.invalidStoredItem
        }
        guard value.scope == scope else { throw TeamAccountSessionError.scopeMismatch }
        return value
    }
    public func saveInitial(_ pair: TeamAuthSessionPair, scope: TeamAccountSessionScope,
                            now: Int64, consent: Bool) throws -> TeamAccountSessionSnapshot {
        try Task.checkCancellation()
        guard consent else { throw TeamAccountSessionError.consentRequired }
        let value = try TeamAccountSessionCodec.active(pair: pair, scope: scope, now: now)
        var fields = base.merging(try attributes(value)) { _, new in new }
        fields[kSecAttrAccessible as String] = accessibility
        let status = keychain.add(fields)
        if status == errSecDuplicateItem { throw TeamAccountSessionError.alreadyExists }
        guard status == errSecSuccess else { throw TeamAccountSessionError.unavailable(status) }
        return value // Never report cancellation as rollback after a completed write.
    }
    public func beginRefresh(_ current: TeamAccountSessionSnapshot, now: Int64) throws -> TeamAccountRefreshLease {
        try Task.checkCancellation()
        try TeamAccountSessionCodec.checkClock(now, since: current.observedAt)
        guard current.phase == .active, let pair = current.pair, now < current.sessionExpiresAt else {
            throw TeamAccountSessionError.reauthenticationRequired
        }
        let marker = TeamAccountSessionSnapshot(scope: current.scope, phase: .refreshPending,
            accountID: current.accountID, sessionID: current.sessionID, sessionExpiresAt: current.sessionExpiresAt,
            generation: UUID(), observedAt: now, pair: nil)
        try replace(current, with: marker)
        return TeamAccountRefreshLease(previousPair: pair, marker: marker)
    }
    public func completeRefresh(_ lease: TeamAccountRefreshLease, next: TeamAuthSessionPair,
                                now: Int64) throws -> TeamAccountSessionSnapshot {
        try Task.checkCancellation()
        try TeamAccountSessionCodec.checkClock(now, since: lease.marker.observedAt)
        let previous = lease.previousPair
        guard next.accountID == previous.accountID, next.sessionID == previous.sessionID,
              next.sessionExpiresAt == previous.sessionExpiresAt,
              ![previous.accessToken, previous.refreshToken].contains(next.accessToken),
              ![previous.accessToken, previous.refreshToken].contains(next.refreshToken) else {
            throw TeamAccountSessionError.invalidSession
        }
        let value = try TeamAccountSessionCodec.active(pair: next, scope: lease.marker.scope, now: now)
        try replace(lease.marker, with: value)
        return value
    }
    private func replace(_ expected: TeamAccountSessionSnapshot, with next: TeamAccountSessionSnapshot) throws {
        // A single SecItemUpdate changes payload+generation atomically. Query the
        // old generation; never read-then-unconditionally-write a rotating pair.
        let status = keychain.update(matching(expected), try attributes(next))
        if status == errSecItemNotFound { throw TeamAccountSessionError.staleOperation }
        guard status == errSecSuccess else { throw TeamAccountSessionError.unavailable(status) }
    }
    /// Explicit local sign-out/account replacement only. Not server revocation.
    /// Exact generation prevents a late callback deleting a newer login.
    public func remove(_ current: TeamAccountSessionSnapshot, consent: Bool) throws {
        try Task.checkCancellation()
        guard consent else { throw TeamAccountSessionError.consentRequired }
        let status = keychain.delete(matching(current))
        if status == errSecItemNotFound { throw TeamAccountSessionError.staleOperation }
        guard status == errSecSuccess else { throw TeamAccountSessionError.unavailable(status) }
    }
}
