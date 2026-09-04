import CryptoKit
import Foundation
import Security

enum PersonalGoogleDriveCredentialError: Error, Equatable, Sendable {
    case consentRequired
    case alreadyConnected
    case invalidRecord
    case scopeMismatch
    case staleOperation
    case expired
    case unavailable(OSStatus)
}

enum PersonalGoogleDriveCredentialPhase: String, Sendable {
    case active
    case revocationPending
}

struct PersonalGoogleDriveCredentialSnapshot: Sendable, CustomStringConvertible,
                                               CustomDebugStringConvertible,
                                               CustomReflectable {
    let generation: UUID
    let phase: PersonalGoogleDriveCredentialPhase
    let clientIDHash: String
    let connectedAt: Int64
    let refreshExpiresAt: Int64?
    fileprivate let refreshToken: PersonalGoogleDriveRefreshToken

    func usableRefreshToken(now: Int64) throws -> PersonalGoogleDriveRefreshToken {
        guard phase == .active else {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        guard now >= connectedAt, now <= TeamAuthWire.maximumSafeTime else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        if let refreshExpiresAt, now >= refreshExpiresAt {
            throw PersonalGoogleDriveCredentialError.expired
        }
        return refreshToken
    }

    func tokenForRevocation() -> PersonalGoogleDriveRefreshToken { refreshToken }

    var description: String { "PersonalGoogleDriveCredentialSnapshot(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol PersonalGoogleDriveCredentialKeychain: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemPersonalGoogleDriveCredentialKeychain:
    PersonalGoogleDriveCredentialKeychain {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

private enum PersonalGoogleDriveCredentialCodec {
    static let maximumBytes = 2_048
    private static let required: Set<String> = [
        "version", "generation", "phase", "clientIdSha256", "connectedAt", "refreshToken",
    ]

    static func clientIDHash(_ clientID: String) -> String {
        SHA256.hash(data: Data(clientID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ value: PersonalGoogleDriveCredentialSnapshot) throws -> Data {
        var fields: [String: Any] = [
            "version": 1,
            "generation": value.generation.uuidString,
            "phase": value.phase.rawValue,
            "clientIdSha256": value.clientIDHash,
            "connectedAt": value.connectedAt,
            "refreshToken": value.refreshToken.value,
        ]
        if let refreshExpiresAt = value.refreshExpiresAt {
            fields["refreshExpiresAt"] = refreshExpiresAt
        }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard (1...maximumBytes).contains(data.count) else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        return data
    }

    static func decode(_ data: Data) throws -> PersonalGoogleDriveCredentialSnapshot {
        do {
            let fields = try TeamStrictJSON.object(data, maximumBytes: maximumBytes)
            let keys = Set(fields.keys)
            guard required.isSubset(of: keys),
                  keys.isSubset(of: required.union(["refreshExpiresAt"])),
                  let version = fields["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(), version.int64Value == 1,
                  let generationText = fields["generation"] as? String,
                  let generation = UUID(uuidString: generationText),
                  generation.uuidString == generationText,
                  let phaseText = fields["phase"] as? String,
                  let phase = PersonalGoogleDriveCredentialPhase(rawValue: phaseText),
                  let clientIDHash = fields["clientIdSha256"] as? String,
                  RemoteBackupSnapshot.hexDigest(clientIDHash),
                  let connectedNumber = fields["connectedAt"] as? NSNumber,
                  CFGetTypeID(connectedNumber) != CFBooleanGetTypeID(),
                  (0...TeamAuthWire.maximumSafeTime).contains(connectedNumber.int64Value),
                  let rawRefresh = fields["refreshToken"] as? String else {
                throw PersonalGoogleDriveCredentialError.invalidRecord
            }
            let refreshExpiresAt: Int64?
            if let rawExpiry = fields["refreshExpiresAt"] {
                guard let expiry = rawExpiry as? NSNumber,
                      CFGetTypeID(expiry) != CFBooleanGetTypeID(),
                      expiry.int64Value > connectedNumber.int64Value,
                      expiry.int64Value <= TeamAuthWire.maximumSafeTime else {
                    throw PersonalGoogleDriveCredentialError.invalidRecord
                }
                refreshExpiresAt = expiry.int64Value
            } else { refreshExpiresAt = nil }
            return PersonalGoogleDriveCredentialSnapshot(
                generation: generation,
                phase: phase,
                clientIDHash: clientIDHash,
                connectedAt: connectedNumber.int64Value,
                refreshExpiresAt: refreshExpiresAt,
                refreshToken: try PersonalGoogleDriveRefreshToken(rawRefresh)
            )
        } catch {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
    }
}

/// Device-only refresh-token custody for the inactive personal Drive connection.
/// Access tokens remain memory-only. Generation-bound mutations prevent a late
/// refresh or disconnect from overwriting or deleting a newer connection.
struct PersonalGoogleDriveCredentialStore: Sendable {
    private let service: String
    private let account = "personal-drive-refresh-token"
    private let keychain: any PersonalGoogleDriveCredentialKeychain
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    init() {
        service = "com.zaidsafa.pinbook.ios.personal-drive-credential.v1"
        keychain = SystemPersonalGoogleDriveCredentialKeychain()
    }

    init(testService: String, keychain: any PersonalGoogleDriveCredentialKeychain) throws {
        guard testService.hasPrefix("pinbook.personal-drive-credential-test."),
              testService.utf8.count <= 160 else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        service = testService
        self.keychain = keychain
    }

    #if DEBUG
    init(deviceTestService: String) throws {
        guard deviceTestService.hasPrefix("pinbook.personal-drive-credential-device-test."),
              deviceTestService.utf8.count <= 160 else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        service = deviceTestService
        keychain = SystemPersonalGoogleDriveCredentialKeychain()
    }
    #endif

    private var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func matching(generation: UUID) -> [String: Any] {
        var query = base
        query[kSecAttrAccessible as String] = accessibility
        query[kSecAttrGeneric as String] = Data(generation.uuidString.utf8)
        return query
    }

    private func attributes(_ value: PersonalGoogleDriveCredentialSnapshot) throws
        -> [String: Any] {
        [
            kSecValueData as String: try PersonalGoogleDriveCredentialCodec.encode(value),
            kSecAttrGeneric as String: Data(value.generation.uuidString.utf8),
        ]
    }

    func load(configuration: PersonalGoogleDriveConfiguration) throws
        -> PersonalGoogleDriveCredentialSnapshot? {
        try Task.checkCancellation()
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        let (status, result) = keychain.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
        guard let fields = result as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == account,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String == accessibility,
              let data = fields[kSecValueData as String] as? Data,
              let generic = fields[kSecAttrGeneric as String] as? Data else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        let value = try PersonalGoogleDriveCredentialCodec.decode(data)
        guard generic == Data(value.generation.uuidString.utf8) else {
            throw PersonalGoogleDriveCredentialError.invalidRecord
        }
        guard value.clientIDHash
                == PersonalGoogleDriveCredentialCodec.clientIDHash(configuration.clientID) else {
            throw PersonalGoogleDriveCredentialError.scopeMismatch
        }
        return value
    }

    func saveInitial(_ grant: PersonalGoogleDriveGrant,
                     configuration: PersonalGoogleDriveConfiguration,
                     now: Int64, consent: Bool) throws
        -> PersonalGoogleDriveCredentialSnapshot {
        try Task.checkCancellation()
        return try addInitial(
            grant, configuration: configuration, now: now,
            consent: consent, phase: .active
        )
    }

    /// Fences a newly issued refresh token before connection success. This
    /// intentionally ignores caller cancellation: once a provider issues a
    /// token, durable custody must win before cleanup or activation can begin.
    func stageInitialForActivation(
        _ grant: PersonalGoogleDriveGrant,
        configuration: PersonalGoogleDriveConfiguration,
        now: Int64, consent: Bool
    ) throws -> PersonalGoogleDriveCredentialSnapshot {
        try addInitial(
            grant, configuration: configuration, now: now,
            consent: consent, phase: .revocationPending
        )
    }

    /// Converts the exact fenced generation into the active connection. The
    /// caller establishes its cancellation linearization before this atomic CAS.
    func activate(_ current: PersonalGoogleDriveCredentialSnapshot, now: Int64) throws
        -> PersonalGoogleDriveCredentialSnapshot {
        guard current.phase == .revocationPending,
              now >= current.connectedAt, now <= TeamAuthWire.maximumSafeTime else {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        if let expiry = current.refreshExpiresAt, expiry <= now {
            throw PersonalGoogleDriveCredentialError.expired
        }
        let active = PersonalGoogleDriveCredentialSnapshot(
            generation: UUID(), phase: .active,
            clientIDHash: current.clientIDHash, connectedAt: current.connectedAt,
            refreshExpiresAt: current.refreshExpiresAt,
            refreshToken: current.refreshToken
        )
        let status = keychain.update(
            matching(generation: current.generation), try attributes(active)
        )
        if status == errSecItemNotFound {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
        return active
    }

    private func addInitial(
        _ grant: PersonalGoogleDriveGrant,
        configuration: PersonalGoogleDriveConfiguration,
        now: Int64, consent: Bool,
        phase: PersonalGoogleDriveCredentialPhase
    ) throws -> PersonalGoogleDriveCredentialSnapshot {
        guard consent else { throw PersonalGoogleDriveCredentialError.consentRequired }
        _ = try grant.accessToken(now: now)
        if let expiry = grant.refreshExpiresAt, expiry <= now {
            throw PersonalGoogleDriveCredentialError.expired
        }
        let value = PersonalGoogleDriveCredentialSnapshot(
            generation: UUID(),
            phase: phase,
            clientIDHash: PersonalGoogleDriveCredentialCodec.clientIDHash(configuration.clientID),
            connectedAt: now,
            refreshExpiresAt: grant.refreshExpiresAt,
            refreshToken: grant.refresh
        )
        var fields = base.merging(try attributes(value)) { _, next in next }
        fields[kSecAttrAccessible as String] = accessibility
        let status = keychain.add(fields)
        if status == errSecDuplicateItem {
            throw PersonalGoogleDriveCredentialError.alreadyConnected
        }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
        return value
    }

    func replace(_ current: PersonalGoogleDriveCredentialSnapshot,
                 with grant: PersonalGoogleDriveGrant, now: Int64) throws
        -> PersonalGoogleDriveCredentialSnapshot {
        try Task.checkCancellation()
        guard current.phase == .active else {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        _ = try current.usableRefreshToken(now: now)
        _ = try grant.accessToken(now: now)
        let expiry = grant.refreshExpiresAt
            ?? (grant.refresh.value == current.refreshToken.value ? current.refreshExpiresAt : nil)
        if let expiry, expiry <= now { throw PersonalGoogleDriveCredentialError.expired }
        let next = PersonalGoogleDriveCredentialSnapshot(
            generation: UUID(), phase: .active, clientIDHash: current.clientIDHash,
            connectedAt: current.connectedAt, refreshExpiresAt: expiry,
            refreshToken: grant.refresh
        )
        let status = keychain.update(matching(generation: current.generation),
                                     try attributes(next))
        if status == errSecItemNotFound {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
        return next
    }

    /// Persistently fences refresh before remote revocation. A failed/ambiguous
    /// network result intentionally leaves this marker for an exact retry.
    func beginRevocation(_ current: PersonalGoogleDriveCredentialSnapshot) throws
        -> PersonalGoogleDriveCredentialSnapshot {
        try Task.checkCancellation()
        guard current.phase == .active else {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        let marker = PersonalGoogleDriveCredentialSnapshot(
            generation: UUID(), phase: .revocationPending,
            clientIDHash: current.clientIDHash, connectedAt: current.connectedAt,
            refreshExpiresAt: current.refreshExpiresAt,
            refreshToken: current.refreshToken
        )
        let status = keychain.update(matching(generation: current.generation),
                                     try attributes(marker))
        if status == errSecItemNotFound {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
        return marker
    }

    func remove(_ current: PersonalGoogleDriveCredentialSnapshot, consent: Bool) throws {
        try Task.checkCancellation()
        guard consent else { throw PersonalGoogleDriveCredentialError.consentRequired }
        let status = keychain.delete(matching(generation: current.generation))
        if status == errSecItemNotFound {
            throw PersonalGoogleDriveCredentialError.staleOperation
        }
        guard status == errSecSuccess else {
            throw PersonalGoogleDriveCredentialError.unavailable(status)
        }
    }
}
