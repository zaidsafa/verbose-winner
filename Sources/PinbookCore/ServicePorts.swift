import CryptoKit
import Foundation

public enum BackupTransportError: Error, Equatable, Sendable {
    case invalidMetadata
    case invalidLimit
    case repeatedCursor
    case duplicateSnapshot
    case inventoryLimit
    case integrityMismatch
    case appendMismatch
}

/// Immutable provider metadata. It contains no filename, account or financial data.
public struct RemoteBackupSnapshot: Equatable, Hashable, Sendable,
                                    CustomStringConvertible, CustomDebugStringConvertible,
                                    CustomReflectable {
    public let objectID: String
    public let operationID: String
    public let createdAt: Int64
    public let byteCount: Int
    public let sha256: String

    public init(objectID: String, operationID: String, createdAt: Int64,
                byteCount: Int, sha256: String) throws {
        guard Self.opaqueID(objectID), Self.opaqueID(operationID),
              (0...BackupTransportGuard.maximumSafeTime).contains(createdAt),
              (1...BackupTransportGuard.maximumBackupBytes).contains(byteCount),
              Self.hexDigest(sha256) else { throw BackupTransportError.invalidMetadata }
        self.objectID = objectID
        self.operationID = operationID
        self.createdAt = createdAt
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public var description: String { "RemoteBackupSnapshot(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    fileprivate func verify(_ data: Data) throws {
        guard data.count == byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256
        else { throw BackupTransportError.integrityMismatch }
    }

    static func opaqueID(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 95
        }
    }

    static func hexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

public struct RemoteBackupPage: Equatable, Sendable, CustomStringConvertible,
                                CustomDebugStringConvertible, CustomReflectable {
    public let snapshots: [RemoteBackupSnapshot]
    public let nextCursor: String?

    public init(snapshots: [RemoteBackupSnapshot], nextCursor: String?) throws {
        guard snapshots.count <= BackupTransportGuard.maximumPageObjects,
              nextCursor.map(Self.validCursor) ?? true else {
            throw BackupTransportError.invalidMetadata
        }
        self.snapshots = snapshots
        self.nextCursor = nextCursor
    }

    public var description: String { "RemoteBackupPage(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    private static func validCursor(_ value: String) -> Bool {
        (1...BackupTransportGuard.maximumCursorBytes).contains(value.utf8.count)
            && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }
}

/// Provider adapters expose immutable append only. There is deliberately no blind
/// update/delete surface. Authentication, scheduling and user consent stay outside.
public protocol BackupTransport: Sendable {
    func list(after cursor: String?) async throws -> RemoteBackupPage
    func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) async throws -> Data
    func append(_ backup: Data, operationID: String, createdAt: Int64,
                sha256: String) async throws -> RemoteBackupSnapshot
}

public enum BackupTransportGuard {
    public static let maximumBackupBytes = 128 * 1024 * 1024
    public static let maximumPageObjects = 100
    public static let maximumInventoryObjects = 10_000
    public static let maximumInventoryPages = 100
    public static let maximumCursorBytes = 2_048
    public static let maximumSafeTime: Int64 = 9_007_199_254_740_991

    public static func inventory(using transport: any BackupTransport,
                                 maximumPages: Int = maximumInventoryPages,
                                 maximumObjects: Int = maximumInventoryObjects) async throws
        -> [RemoteBackupSnapshot] {
        guard (1...maximumInventoryPages).contains(maximumPages),
              (1...maximumInventoryObjects).contains(maximumObjects) else {
            throw BackupTransportError.invalidLimit
        }
        var result: [RemoteBackupSnapshot] = []
        var objectIDs = Set<String>()
        var operationIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?

        for _ in 0..<maximumPages {
            let page = try await transport.list(after: cursor)
            guard result.count <= maximumObjects - page.snapshots.count else {
                throw BackupTransportError.inventoryLimit
            }
            for snapshot in page.snapshots {
                guard objectIDs.insert(snapshot.objectID).inserted,
                      operationIDs.insert(snapshot.operationID).inserted else {
                    throw BackupTransportError.duplicateSnapshot
                }
                result.append(snapshot)
            }
            guard let next = page.nextCursor else {
                return result.sorted {
                    $0.createdAt == $1.createdAt ? $0.objectID < $1.objectID
                        : $0.createdAt < $1.createdAt
                }
            }
            guard seenCursors.insert(next).inserted else {
                throw BackupTransportError.repeatedCursor
            }
            cursor = next
        }
        throw BackupTransportError.inventoryLimit
    }

    public static func downloadVerified(_ snapshot: RemoteBackupSnapshot,
                                        using transport: any BackupTransport) async throws -> Data {
        let data = try await transport.download(snapshot, maximumBytes: snapshot.byteCount)
        try snapshot.verify(data)
        return data
    }

    public static func appendVerified(_ backup: Data, operationID: String,
                                      createdAt: Int64,
                                      using transport: any BackupTransport) async throws
        -> RemoteBackupSnapshot {
        guard RemoteBackupSnapshot.opaqueID(operationID),
              (0...maximumSafeTime).contains(createdAt),
              (1...maximumBackupBytes).contains(backup.count) else {
            throw BackupTransportError.invalidMetadata
        }
        let digest = SHA256.hash(data: backup).map { String(format: "%02x", $0) }.joined()
        let result = try await transport.append(backup, operationID: operationID,
                                                createdAt: createdAt, sha256: digest)
        guard result.operationID == operationID, result.createdAt == createdAt,
              result.byteCount == backup.count, result.sha256 == digest else {
            throw BackupTransportError.appendMismatch
        }
        return result
    }
}

public protocol ReceiptStoring: Sendable {
    func save(data: Data, preferredFileName: String) async throws -> String
    func load(fileName: String) async throws -> Data
    func remove(fileName: String) async throws
}

public protocol StatementGenerating: Sendable {
    func pdf(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data
    func csv(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data
}

public protocol ReminderScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func schedule(expenseID: String, at date: Date, title: String) async throws
    func cancel(expenseID: String) async
}

public protocol ReceiptTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [String]
}
