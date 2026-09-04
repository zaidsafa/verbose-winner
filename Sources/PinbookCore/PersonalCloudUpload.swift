import CryptoKit
import Foundation
import Security

public enum PersonalCloudUploadError: Error, Equatable, Sendable {
    case invalidRecord
    case unresolvedUpload
    case staleOperation
    case busy
    case unavailable(OSStatus)
}

/// Content-free durable authority for one immutable backup append. The backup
/// bytes, provider account, filename and credentials are deliberately excluded.
public struct PendingBackupUpload: Equatable, Sendable, CustomStringConvertible,
                                   CustomDebugStringConvertible, CustomReflectable {
    public let operationID: String
    public let createdAt: Int64
    public let byteCount: Int
    public let sha256: String

    public var description: String { "PendingBackupUpload(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol BackupUploadStateStoring: Sendable {
    func load() throws -> Data?
    /// Atomic compare-and-swap. A thrown result may have committed, so callers
    /// must reload rather than inventing a new operation identity.
    func replace(expected: Data?, next: Data?) throws
}

private protocol BackupUploadKeychainAPI: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemBackupUploadKeychainAPI: BackupUploadKeychainAPI {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

private struct KeychainBackupUploadStateStore: BackupUploadStateStoring {
    private static let maximumBytes = 2_048
    private let service: String
    private let account = "pending-immutable-backup"
    private let keychain: any BackupUploadKeychainAPI = SystemBackupUploadKeychainAPI()

    init() {
        service = "com.zaidsafa.pinbook.ios.personal-cloud-upload.v1"
    }

    init(testService: String) throws {
        guard testService.hasPrefix("pinbook.cloud-upload-test."),
              testService.utf8.count <= 128 else {
            throw PersonalCloudUploadError.invalidRecord
        }
        service = testService
    }

    private var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() throws -> Data? {
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        let (status, result) = keychain.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw PersonalCloudUploadError.unavailable(status)
        }
        guard let fields = result as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == account,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
              let data = fields[kSecValueData as String] as? Data,
              (1...Self.maximumBytes).contains(data.count),
              fields[kSecAttrGeneric as String] as? Data == Data(SHA256.hash(data: data)) else {
            throw PersonalCloudUploadError.invalidRecord
        }
        return data
    }

    func replace(expected: Data?, next: Data?) throws {
        guard expected.map({ (1...Self.maximumBytes).contains($0.count) }) ?? true,
              next.map({ (1...Self.maximumBytes).contains($0.count) }) ?? true else {
            throw PersonalCloudUploadError.invalidRecord
        }
        let status: OSStatus
        if let next {
            guard expected == nil else { throw PersonalCloudUploadError.invalidRecord }
            var attributes = base
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecValueData as String] = next
            attributes[kSecAttrGeneric as String] = Data(SHA256.hash(data: next))
            status = keychain.add(attributes)
        } else if let expected {
            var query = base
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrGeneric as String] = Data(SHA256.hash(data: expected))
            status = keychain.delete(query)
        } else {
            return
        }
        if status == errSecDuplicateItem || status == errSecItemNotFound {
            throw PersonalCloudUploadError.staleOperation
        }
        guard status == errSecSuccess else {
            throw PersonalCloudUploadError.unavailable(status)
        }
    }
}

private struct EncodedPendingBackupUpload: Codable {
    let version: Int
    let operationID: String
    let createdAt: Int64
    let byteCount: Int
    let sha256: String
}

/// Inactive provider-neutral upload owner. Reservation is durable before the
/// first provider await; failure or cancellation retains the same retry identity.
public final class PersonalCloudUploadOwner: @unchecked Sendable {
    private let lock = NSLock()
    private let state: any BackupUploadStateStoring
    private var activeFlight: UUID?

    public convenience init() {
        self.init(state: KeychainBackupUploadStateStore())
    }

    init(state: any BackupUploadStateStoring) {
        self.state = state
    }

    init(testService: String) throws {
        self.state = try KeychainBackupUploadStateStore(testService: testService)
    }

    public func pendingUpload() throws -> PendingBackupUpload? {
        try lock.withLock {
            guard let raw = try state.load() else { return nil }
            return try Self.decode(raw)
        }
    }

    /// Returns the existing ticket only when the exact bytes/time match. A
    /// different backup cannot replace an unresolved provider operation.
    public func reserve(_ backup: Data, createdAt: Int64,
                        using transport: any BackupTransport) async throws
        -> PendingBackupUpload {
        let candidate = try Self.fields(backup, operationID: nil, createdAt: createdAt)
        if let existing = try lock.withLock({ () throws -> PendingBackupUpload? in
            if let raw = try state.load() {
                let existing = try Self.decode(raw)
                guard Self.sameContent(existing, candidate) else {
                    throw PersonalCloudUploadError.unresolvedUpload
                }
                return existing
            }
            return nil
        }) {
            return existing
        }

        let reservedID = try await BackupTransportGuard.reserveOperationID(using: transport)
        let ticket = try Self.fields(backup, operationID: reservedID, createdAt: createdAt)
        return try lock.withLock {
            if let raw = try state.load() {
                let existing = try Self.decode(raw)
                guard Self.sameContent(existing, candidate) else {
                    throw PersonalCloudUploadError.unresolvedUpload
                }
                return existing
            }
            let encoded = try Self.encode(ticket)
            do {
                try state.replace(expected: nil, next: encoded)
            } catch {
                // A keychain/CAS error can be ambiguous. Accept only an exact
                // committed value; never allocate another logical upload here.
                if let raw = try? state.load(), let stored = try? Self.decode(raw),
                   stored == ticket || Self.sameContent(stored, candidate) {
                    return stored
                }
                throw error
            }
            return ticket
        }
    }

    public func append(_ backup: Data, ticket: PendingBackupUpload,
                       using transport: any BackupTransport) async throws
        -> RemoteBackupSnapshot {
        let expected = try Self.fields(
            backup,
            operationID: ticket.operationID,
            createdAt: ticket.createdAt
        )
        guard expected == ticket else { throw PersonalCloudUploadError.staleOperation }
        let flight = try beginFlight(ticket)
        defer { endFlight(flight) }

        let receipt = try await BackupTransportGuard.appendVerified(
            backup,
            operationID: ticket.operationID,
            createdAt: ticket.createdAt,
            using: transport
        )
        try lock.withLock {
            guard let raw = try state.load(), try Self.decode(raw) == ticket else {
                throw PersonalCloudUploadError.staleOperation
            }
            try state.replace(expected: raw, next: nil)
        }
        return receipt
    }

    private func beginFlight(_ ticket: PendingBackupUpload) throws -> UUID {
        try lock.withLock {
            guard activeFlight == nil else { throw PersonalCloudUploadError.busy }
            guard let raw = try state.load(), try Self.decode(raw) == ticket else {
                throw PersonalCloudUploadError.staleOperation
            }
            let id = UUID()
            activeFlight = id
            return id
        }
    }

    private func endFlight(_ id: UUID) {
        lock.withLock {
            if activeFlight == id { activeFlight = nil }
        }
    }

    private static func fields(_ backup: Data, operationID: String?, createdAt: Int64) throws
        -> PendingBackupUpload {
        let operationID = operationID ?? "pending"
        let digest = SHA256.hash(data: backup).map { String(format: "%02x", $0) }.joined()
        let value = PendingBackupUpload(
            operationID: operationID,
            createdAt: createdAt,
            byteCount: backup.count,
            sha256: digest
        )
        try validate(value)
        return value
    }

    private static func sameContent(_ lhs: PendingBackupUpload,
                                    _ rhs: PendingBackupUpload) -> Bool {
        lhs.createdAt == rhs.createdAt && lhs.byteCount == rhs.byteCount && lhs.sha256 == rhs.sha256
    }

    private static func validate(_ value: PendingBackupUpload) throws {
        guard RemoteBackupSnapshot.opaqueID(value.operationID),
              (0...BackupTransportGuard.maximumSafeTime).contains(value.createdAt),
              (1...BackupTransportGuard.maximumBackupBytes).contains(value.byteCount),
              RemoteBackupSnapshot.hexDigest(value.sha256) else {
            throw PersonalCloudUploadError.invalidRecord
        }
    }

    private static func encode(_ value: PendingBackupUpload) throws -> Data {
        try validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(EncodedPendingBackupUpload(
            version: 1,
            operationID: value.operationID,
            createdAt: value.createdAt,
            byteCount: value.byteCount,
            sha256: value.sha256
        ))
    }

    private static func decode(_ data: Data) throws -> PendingBackupUpload {
        guard data.count <= 2_048,
              let value = try? JSONDecoder().decode(EncodedPendingBackupUpload.self, from: data),
              value.version == 1 else {
            throw PersonalCloudUploadError.invalidRecord
        }
        let result = PendingBackupUpload(
            operationID: value.operationID,
            createdAt: value.createdAt,
            byteCount: value.byteCount,
            sha256: value.sha256
        )
        try validate(result)
        return result
    }
}
