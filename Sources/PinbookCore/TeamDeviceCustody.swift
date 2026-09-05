import CryptoKit
import Foundation
import Security

enum TeamDeviceCustodyError: Error, Equatable {
    case consentRequired, invalidScope, invalidRecord, capacity, staleOperation
    case invalidPhase, invalidTime, keyUnavailable, bindingMismatch, recoveryWait
    case unavailable(OSStatus)
}

struct TeamDeviceScope: Equatable, TeamOnboardingDiagnostic {
    let audience: String
    let accountID: String
    let authorityEpoch: String
    init(audience: String, accountID: String, authorityEpoch: String) throws {
        guard TeamDeviceEnrollmentWire.canonicalAudience(audience),
              TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(authorityEpoch) else { throw TeamDeviceCustodyError.invalidScope }
        self.audience = audience; self.accountID = accountID; self.authorityEpoch = authorityEpoch
    }
}
enum TeamDevicePhase: String, Sendable { case reserved, ready, submitPending, recovering, registered }
struct TeamDeviceSnapshot: TeamOnboardingDiagnostic {
    let scope: TeamDeviceScope
    let deviceID: String
    let generation: UUID
    let phase: TeamDevicePhase
    let observedAt: Int64
    let publicKey: TeamDeviceEnrollmentWire.PublicKey?
    let proofExpiresAt: Int64?
    let enrollmentID: String?
}
struct TeamDeviceSubmission: TeamOnboardingDiagnostic {
    let pending: TeamDeviceSnapshot
    let signature: Data
}

/// Opaque provider representation only. Never export, log or put in an archive.
/// Production uses SecureEnclave, never software P256 private-key bytes.
struct TeamDeviceKeyMaterial: TeamOnboardingDiagnostic {
    let sealed: Data
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
}
protocol TeamDeviceKeyProvider: Sendable {
    func generate() throws -> TeamDeviceKeyMaterial
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey
    func sign(sealed: Data, message: Data) throws -> Data
}
struct SecureEnclaveTeamDeviceKeys: TeamDeviceKeyProvider {
    private func restored(_ data: Data) throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable, (1...4096).contains(data.count) else { throw TeamDeviceCustodyError.keyUnavailable }
        do { return try .init(dataRepresentation: data) }
        catch { throw TeamDeviceCustodyError.keyUnavailable }
    }
    func generate() throws -> TeamDeviceKeyMaterial {
        guard SecureEnclave.isAvailable,
              let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .privateKeyUsage, nil) else { throw TeamDeviceCustodyError.keyUnavailable }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false, accessControl: access)
            guard (1...4096).contains(key.dataRepresentation.count) else { throw TeamDeviceCustodyError.keyUnavailable }
            return try .init(sealed: key.dataRepresentation, publicKey: TeamDeviceEnrollmentWire.publicKey(key.publicKey))
        } catch { throw TeamDeviceCustodyError.keyUnavailable }
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        try TeamDeviceEnrollmentWire.publicKey(restored(sealed).publicKey)
    }
    func sign(sealed: Data, message: Data) throws -> Data {
        guard (1...4096).contains(message.count) else { throw TeamDeviceCustodyError.bindingMismatch }
        do { return try restored(sealed).signature(for: message).rawRepresentation }
        catch { throw TeamDeviceCustodyError.keyUnavailable }
    }
}

protocol TeamDeviceMetadataStore: Sendable {
    func load() throws -> Data?
    /// Atomic compare-and-swap. A thrown response may still have committed.
    func replace(expected: Data?, next: Data) throws
}
protocol TeamDeviceMetadataAPI: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
}
private struct SystemTeamDeviceMetadataAPI: TeamDeviceMetadataAPI {
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result); return (status, result)
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus { SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
}
struct KeychainTeamDeviceMetadata: TeamDeviceMetadataStore {
    static let maximumBytes = 65_536
    private let service: String
    private let account = "bounded-device-index"
    private let keychain: any TeamDeviceMetadataAPI
    init() {
        service = "com.zaidsafa.pinbook.ios.team-device-custody.v1"; keychain = SystemTeamDeviceMetadataAPI()
    }
    init(testService: String, keychain: any TeamDeviceMetadataAPI) throws {
        guard testService.hasPrefix("pinbook.device-test."), testService.utf8.count <= 128 else { throw TeamDeviceCustodyError.invalidScope }
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
        guard status == errSecSuccess else { throw TeamDeviceCustodyError.unavailable(status) }
        guard let fields = result as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == account,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String,
              let data = fields[kSecValueData as String] as? Data, (1...Self.maximumBytes).contains(data.count),
              fields[kSecAttrGeneric as String] as? Data == Data(SHA256.hash(data: data)) else { throw TeamDeviceCustodyError.invalidRecord }
        return data
    }
    func replace(expected: Data?, next: Data) throws {
        guard (1...Self.maximumBytes).contains(next.count) else { throw TeamDeviceCustodyError.invalidRecord }
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
        if status == errSecDuplicateItem || status == errSecItemNotFound { throw TeamDeviceCustodyError.staleOperation }
        guard status == errSecSuccess else { throw TeamDeviceCustodyError.unavailable(status) }
    }
}

private struct TeamDeviceRecord {
    var snapshot: TeamDeviceSnapshot
    let sealedKey: Data?
    let challengeID: String?
}
private struct TeamDeviceIndex {
    var revision = UUID()
    var records = [TeamDeviceRecord]()
    func encoded() throws -> Data {
        let rows: [[String: Any]] = records.map { row in
            let s = row.snapshot
            return ["audience": s.scope.audience, "accountId": s.scope.accountID, "authorityEpoch": s.scope.authorityEpoch,
                "deviceId": s.deviceID, "generation": s.generation.uuidString, "phase": s.phase.rawValue, "observedAt": s.observedAt,
                "publicKey": s.publicKey?.jwk as Any? ?? NSNull(), "sealedKey": row.sealedKey?.base64EncodedString() as Any? ?? NSNull(),
                "proofExpiresAt": s.proofExpiresAt as Any? ?? NSNull(), "challengeId": row.challengeID as Any? ?? NSNull(),
                "enrollmentId": s.enrollmentID as Any? ?? NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: ["version": 1, "revision": revision.uuidString, "records": rows], options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func decoded(_ data: Data?) throws -> Self {
        guard let data else { return .init() }
        do {
            let object = try TeamStrictJSON.object(data, maximumBytes: KeychainTeamDeviceMetadata.maximumBytes)
            guard Set(object.keys) == ["version", "revision", "records"], try TeamAuthWire.time(object, "version") == 1,
                  let revision = uuid(object["revision"]), let rows = object["records"] as? [[String: Any]], rows.count <= 8 else { throw TeamDeviceCustodyError.invalidRecord }
            var result = Self(revision: revision), seen = Set<String>()
            for row in rows {
                guard Set(row.keys) == ["audience", "accountId", "authorityEpoch", "deviceId", "generation", "phase", "observedAt", "publicKey", "sealedKey", "proofExpiresAt", "challengeId", "enrollmentId"],
                      let audience = row["audience"] as? String, let generation = uuid(row["generation"]),
                      let phase = (row["phase"] as? String).flatMap(TeamDevicePhase.init(rawValue:)) else { throw TeamDeviceCustodyError.invalidRecord }
                let scope = try TeamDeviceScope(audience: audience, accountID: TeamAuthWire.string(row, "accountId"), authorityEpoch: TeamAuthWire.string(row, "authorityEpoch"))
                let identity = scope.audience + "\n" + scope.accountID + "\n" + scope.authorityEpoch
                guard seen.insert(identity).inserted else { throw TeamDeviceCustodyError.invalidRecord }
                let key: TeamDeviceEnrollmentWire.PublicKey?, sealed: Data?
                if phase == .reserved {
                    guard row["publicKey"] is NSNull, row["sealedKey"] is NSNull else { throw TeamDeviceCustodyError.invalidRecord }
                    key = nil; sealed = nil
                } else {
                    guard let jwk = row["publicKey"] as? [String: String], let raw = row["sealedKey"] as? String,
                          raw.utf8.count <= 5464, let bytes = Data(base64Encoded: raw), (1...4096).contains(bytes.count),
                          bytes.base64EncodedString() == raw else { throw TeamDeviceCustodyError.invalidRecord }
                    key = try TeamDeviceEnrollmentWire.publicKey(jwk); sealed = bytes
                }
                let deadline: Int64?, challenge: String?, enrollment: String?
                if phase == .submitPending || phase == .recovering {
                    deadline = try TeamAuthWire.time(row, "proofExpiresAt")
                    challenge = try TeamAuthWire.string(row, "challengeId", secret: true)
                } else {
                    guard row["proofExpiresAt"] is NSNull, row["challengeId"] is NSNull else { throw TeamDeviceCustodyError.invalidRecord }
                    deadline = nil; challenge = nil
                }
                if phase == .registered { enrollment = try TeamAuthWire.string(row, "enrollmentId") }
                else { guard row["enrollmentId"] is NSNull else { throw TeamDeviceCustodyError.invalidRecord }; enrollment = nil }
                let observed = try TeamAuthWire.time(row, "observedAt")
                if phase == .submitPending, let deadline { guard deadline > observed, deadline - observed <= 120_000 else { throw TeamDeviceCustodyError.invalidRecord } }
                if phase == .recovering, let deadline { guard observed >= deadline else { throw TeamDeviceCustodyError.invalidRecord } }
                result.records.append(.init(snapshot: .init(scope: scope, deviceID: try TeamAuthWire.string(row, "deviceId"), generation: generation,
                    phase: phase, observedAt: observed, publicKey: key, proofExpiresAt: deadline, enrollmentID: enrollment), sealedKey: sealed, challengeID: challenge))
            }
            return result
        } catch { throw TeamDeviceCustodyError.invalidRecord }
    }
    private static func uuid(_ value: Any?) -> UUID? {
        guard let raw = value as? String, let id = UUID(uuidString: raw), id.uuidString == raw else { return nil }; return id
    }
}

/// Inactive. Durable identity only, NOT current account/team authority. A future
/// owner must check current session generation + monotonic deadline around calls.
/// No delete, export, automatic retry, identity replacement or network operation.
final class TeamDeviceCustody: @unchecked Sendable {
    private let storage: any TeamDeviceMetadataStore
    private let keys: any TeamDeviceKeyProvider
    private let clock: @Sendable () -> Int64
    init() {
        storage = KeychainTeamDeviceMetadata(); keys = SecureEnclaveTeamDeviceKeys()
        clock = { Int64(Date().timeIntervalSince1970 * 1000) }
    }
    init(storage: any TeamDeviceMetadataStore, keys: any TeamDeviceKeyProvider, clock: @escaping @Sendable () -> Int64) {
        self.storage = storage; self.keys = keys; self.clock = clock
    }
    private func now(since: Int64 = 0) throws -> Int64 {
        try Task.checkCancellation()
        let value = clock()
        guard value >= since, value >= 0, value <= TeamAuthWire.maximumSafeTime else { throw TeamDeviceCustodyError.invalidTime }
        return value
    }
    private func read() throws -> (Data?, TeamDeviceIndex) {
        _ = try now(); let raw = try storage.load(); return (raw, try TeamDeviceIndex.decoded(raw))
    }
    private func checkedKey(_ row: TeamDeviceRecord) throws {
        guard let sealed = row.sealedKey, let expected = row.snapshot.publicKey,
              try keys.publicKey(sealed: sealed).thumbprint == expected.thumbprint else { throw TeamDeviceCustodyError.keyUnavailable }
        _ = try now(since: row.snapshot.observedAt)
    }
    func load(scope: TeamDeviceScope) throws -> TeamDeviceSnapshot? {
        let (_, index) = try read()
        guard let row = index.records.first(where: { $0.snapshot.scope == scope }) else { return nil }
        if row.snapshot.phase != .reserved { try checkedKey(row) }
        _ = try now(since: row.snapshot.observedAt)
        return row.snapshot
    }
    func deleteAccount(audience: String, accountID: String,
                       authorityEpoch: String) throws {
        let scope = try TeamDeviceScope(audience: audience, accountID: accountID,
                                        authorityEpoch: authorityEpoch)
        let (raw, old) = try read()
        var index = old
        index.records.removeAll { $0.snapshot.scope == scope }
        guard index.records.count != old.records.count else { return }
        index.revision = UUID()
        try storage.replace(expected: raw, next: index.encoded())
    }
    func requireCurrent(_ expected: TeamDeviceSnapshot) throws { _ = try current(expected) }
    private func current(_ expected: TeamDeviceSnapshot) throws -> TeamDeviceRecord {
        let (_, index) = try read()
        guard let row = index.records.first(where: { $0.snapshot.scope == expected.scope }), row.snapshot.generation == expected.generation else { throw TeamDeviceCustodyError.staleOperation }
        if row.snapshot.phase != .reserved { try checkedKey(row) }
        _ = try now(since: row.snapshot.observedAt)
        return row
    }
    private func replace(_ expected: TeamDeviceSnapshot, row: TeamDeviceRecord) throws -> TeamDeviceSnapshot {
        let (raw, old) = try read(); var index = old
        guard let position = index.records.firstIndex(where: { $0.snapshot.scope == expected.scope }),
              index.records[position].snapshot.generation == expected.generation else { throw TeamDeviceCustodyError.staleOperation }
        _ = try now(since: row.snapshot.observedAt)
        index.records[position] = row; index.revision = UUID()
        try storage.replace(expected: raw, next: index.encoded())
        return try current(row.snapshot).snapshot
    }
    private func changed(_ row: TeamDeviceRecord, phase: TeamDevicePhase, at: Int64, deadline: Int64? = nil, challenge: String? = nil, enrollment: String? = nil) -> TeamDeviceRecord {
        .init(snapshot: .init(scope: row.snapshot.scope, deviceID: row.snapshot.deviceID, generation: UUID(), phase: phase,
            observedAt: at, publicKey: row.snapshot.publicKey, proofExpiresAt: deadline, enrollmentID: enrollment), sealedKey: row.sealedKey, challengeID: challenge)
    }
    func prepare(scope: TeamDeviceScope, consent: Bool) throws -> TeamDeviceSnapshot {
        guard consent else { throw TeamDeviceCustodyError.consentRequired }
        let (raw, old) = try read(); var index = old
        let reserved: TeamDeviceSnapshot
        if let row = index.records.first(where: { $0.snapshot.scope == scope }) {
            if row.snapshot.phase != .reserved { try checkedKey(row); return row.snapshot }
            reserved = row.snapshot
        } else {
            guard index.records.count < 8 else { throw TeamDeviceCustodyError.capacity }
            reserved = .init(scope: scope, deviceID: UUID().uuidString, generation: UUID(), phase: .reserved,
                observedAt: try now(), publicKey: nil, proofExpiresAt: nil, enrollmentID: nil)
            index.records.append(.init(snapshot: reserved, sealedKey: nil, challengeID: nil)); index.revision = UUID()
            try storage.replace(expected: raw, next: index.encoded())
        }
        _ = try current(reserved)
        // No permanent keychain key alias: only the winning CAS retains this
        // opaque SecureEnclave representation. Losing candidates never sign.
        let material = try keys.generate()
        guard (1...4096).contains(material.sealed.count), try keys.publicKey(sealed: material.sealed).thumbprint == material.publicKey.thumbprint else { throw TeamDeviceCustodyError.keyUnavailable }
        let ready = TeamDeviceSnapshot(scope: scope, deviceID: reserved.deviceID, generation: UUID(), phase: .ready,
            observedAt: try now(since: reserved.observedAt), publicKey: material.publicKey, proofExpiresAt: nil, enrollmentID: nil)
        return try replace(reserved, row: .init(snapshot: ready, sealedKey: material.sealed, challengeID: nil))
    }
    func signForSubmission(_ expected: TeamDeviceSnapshot, challenge: TeamPreparedDeviceChallenge,
                           binding: TeamDeviceEnrollmentWire.Binding) throws -> TeamDeviceSubmission {
        let row = try current(expected)
        guard row.snapshot.phase == .ready, let sealed = row.sealedKey, let key = row.snapshot.publicKey else { throw TeamDeviceCustodyError.invalidPhase }
        try match(binding, row: row.snapshot)
        let instant = try now(since: row.snapshot.observedAt)
        let message = try challenge.message(expected: binding, now: instant)
        // Reserve the single proof attempt BEFORE signing. Any failure afterward
        // leaves uncertainty, not permission to sign/send again automatically.
        let pending = try replace(row.snapshot, row: changed(row, phase: .submitPending, at: instant, deadline: challenge.expiresAt, challenge: challenge.challengeID))
        _ = try challenge.message(expected: binding, now: now(since: instant))
        let signature = try keys.sign(sealed: sealed, message: message)
        guard signature.count == 64, let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature), key.key.isValidSignature(parsed, for: message) else { throw TeamDeviceCustodyError.keyUnavailable }
        _ = try current(pending)
        _ = try challenge.message(expected: binding, now: now(since: instant))
        return .init(pending: pending, signature: signature)
    }
    /// Read-only request proof from one exact REGISTERED generation. The caller's
    /// account check runs inside this custody operation before and after signing.
    func signRequest<Request: TeamDeviceRequestPayload>(_ expected: TeamDeviceSnapshot,
                     challenge: TeamPreparedDeviceRequestChallenge,
                     binding: TeamDeviceRequestWire.Binding, request: Request,
                     checkAuthority: @escaping @Sendable () throws -> Void) throws -> Data {
        try checkAuthority()
        let row = try current(expected)
        guard row.snapshot.phase == .registered, row.snapshot.enrollmentID == binding.enrollmentID,
              let sealed = row.sealedKey, let key = row.snapshot.publicKey else {
            throw TeamDeviceCustodyError.invalidPhase
        }
        guard binding.audience == row.snapshot.scope.audience,
              binding.accountID == row.snapshot.scope.accountID,
              binding.authorityEpoch == row.snapshot.scope.authorityEpoch,
              binding.deviceID == row.snapshot.deviceID,
              binding.keyThumbprint == key.thumbprint else { throw TeamDeviceCustodyError.bindingMismatch }
        let instant = try now(since: row.snapshot.observedAt)
        var message = try challenge.message(expected: binding, publicKey: key, request: request, now: instant)
        defer { message.resetBytes(in: message.startIndex..<message.endIndex) }
        try checkAuthority(); _ = try current(expected)
        let signature = try keys.sign(sealed: sealed, message: message)
        guard signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature),
              key.key.isValidSignature(parsed, for: message) else { throw TeamDeviceCustodyError.keyUnavailable }
        try checkAuthority(); _ = try current(expected)
        _ = try challenge.message(expected: binding, publicKey: key, request: request,
            now: now(since: instant))
        return signature
    }
    private func match(_ binding: TeamDeviceEnrollmentWire.Binding, row: TeamDeviceSnapshot) throws {
        guard binding.audience == row.scope.audience, binding.accountID == row.scope.accountID,
              binding.authorityEpoch == row.scope.authorityEpoch, binding.deviceID == row.deviceID,
              binding.keyThumbprint == row.publicKey?.thumbprint else { throw TeamDeviceCustodyError.bindingMismatch }
    }
    func beginRecovery(_ expected: TeamDeviceSnapshot) throws -> TeamDeviceSnapshot {
        let row = try current(expected)
        guard [.submitPending, .recovering].contains(row.snapshot.phase), let deadline = row.snapshot.proofExpiresAt else { throw TeamDeviceCustodyError.invalidPhase }
        let instant = try now(since: row.snapshot.observedAt)
        guard instant >= deadline else { throw TeamDeviceCustodyError.recoveryWait }
        return try replace(row.snapshot, row: changed(row, phase: .recovering, at: instant, deadline: deadline, challenge: row.challengeID))
    }
    func recordRegistration(_ expected: TeamDeviceSnapshot, registration: TeamRegisteredDevice) throws -> TeamDeviceSnapshot {
        let row = try current(expected)
        guard row.snapshot.phase != .reserved else { throw TeamDeviceCustodyError.invalidPhase }
        guard TeamAuthWire.identifier(registration.enrollmentID), registration.accountID == row.snapshot.scope.accountID,
              registration.authorityEpoch == row.snapshot.scope.authorityEpoch, registration.deviceID == row.snapshot.deviceID,
              registration.keyThumbprint == row.snapshot.publicKey?.thumbprint,
              row.snapshot.enrollmentID == nil || row.snapshot.enrollmentID == registration.enrollmentID else { throw TeamDeviceCustodyError.bindingMismatch }
        return try replace(row.snapshot, row: changed(row, phase: .registered, at: now(since: row.snapshot.observedAt), enrollment: registration.enrollmentID))
    }
    /// Call ONLY for an explicit successful current exact-key lookup. Errors are
    /// not represented by nil. The same identity survives an absent recovery result.
    func recordRecoveryAbsence(_ expected: TeamDeviceSnapshot) throws -> TeamDeviceSnapshot {
        let row = try current(expected)
        guard row.snapshot.phase == .recovering else { throw TeamDeviceCustodyError.invalidPhase }
        return try replace(row.snapshot, row: changed(row, phase: .ready, at: now(since: row.snapshot.observedAt)))
    }
}
