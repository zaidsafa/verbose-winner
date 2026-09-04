import Foundation
import SQLite3
import Darwin

public struct ArchivedTeamNote: Equatable, Sendable {
    public let envelope: TeamNoteEnvelope
    public let savedAt: Int64
}

/// Local outbox identity only. The plaintext digest MUST NOT be serialized to the relay.
public struct PendingTeamReceipt: Equatable, Sendable {
    public let accountId: String
    public let teamId: String
    public let deliveryId: String
    public let deviceId: String
    public let enrollmentId: String
    public let bodySha256: String
}

/// Inactive local foundation: no app entry point instantiates this store.
/// A private lock serializes the entire transaction, not just individual SQLite calls.
/// No database handle escapes; independent instances serialize through BEGIN IMMEDIATE.
public final class TeamInboxStore: @unchecked Sendable {
    public static let maximumPendingReceipts = 1_000
    public let target: DeliveryTarget
    public let teamId: String
    public let directoryURL: URL
    public let databaseURL: URL
    private let lock = NSLock()
    private var database: OpaquePointer?

    public init(applicationSupportDirectory: URL, target: DeliveryTarget, teamId: String) throws {
        try target.validate()
        try TeamDeliveryRules.requireID(teamId)
        guard applicationSupportDirectory.isFileURL else { throw TeamDeliveryError.invalidScope }
        self.target = target
        self.teamId = teamId
        directoryURL = applicationSupportDirectory.appendingPathComponent("PinbookTeamInbox", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("team-inbox.sqlite")
        let fm = FileManager.default
        // Dedicated directory, never the personal SwiftData/backup directory itself.
        var directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        var fileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        directoryAttributes[.protectionKey] = FileProtectionType.complete
        fileAttributes[.protectionKey] = FileProtectionType.complete
        #endif
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: directoryAttributes)
        guard try directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamDeliveryError.invalidScope
        }
        try fm.setAttributes(directoryAttributes, ofItemAtPath: directoryURL.path)
        try Self.excludeFromBackup(directoryURL)
        // O_EXCL avoids truncating another connection's file during concurrent initialization.
        let descriptor = Darwin.open(databaseURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        if descriptor >= 0 { Darwin.close(descriptor) }
        else if errno != EEXIST { throw TeamDeliveryError.storage(SQLITE_CANTOPEN) }
        guard try databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamDeliveryError.invalidScope
        }
        try fm.setAttributes(fileAttributes, ofItemAtPath: databaseURL.path)
        try Self.excludeFromBackup(databaseURL)
        #if os(iOS) && !targetEnvironment(simulator)
        // Fail closed on hardware before writing content if the requested class was not applied.
        for url in [directoryURL, databaseURL] {
            guard try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? String
                    == FileProtectionType.complete.rawValue else {
                throw TeamDeliveryError.storage(SQLITE_PERM)
            }
        }
        #endif
        var handle: OpaquePointer?
        var flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        #if os(iOS)
        flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETE
        #endif
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw TeamDeliveryError.storage(result)
        }
        database = handle
        do {
            sqlite3_busy_timeout(database, 2_000)
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=EXTRA")
            try execute("PRAGMA fullfsync=ON")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA temp_store=MEMORY")
            try transaction {
                let version = try scalar("PRAGMA user_version")
                guard version == 0 || version == 1 else { throw TeamDeliveryError.unsupportedSchema }
                if version == 0 {
                    try execute("""
                    CREATE TABLE archive (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL, delivery_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL,
                        accepted_at INTEGER NOT NULL, saved_at INTEGER NOT NULL,
                        envelope BLOB NOT NULL, PRIMARY KEY(account_id, team_id, delivery_id));
                    CREATE TABLE receipt_outbox (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL, delivery_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL, body_sha256 TEXT NOT NULL,
                        PRIMARY KEY(account_id, team_id, delivery_id),
                        FOREIGN KEY(account_id, team_id, delivery_id)
                            REFERENCES archive(account_id, team_id, delivery_id));
                    PRAGMA user_version=1;
                    """)
                }
            }
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw TeamDeliveryError.storage(SQLITE_PERM)
        }
    }

    /// Successful return means archive AND local receipt committed, not that any server ACK was sent.
    /// Allows a verified in-flight download to finish after expiry; the server decides ACK eligibility.
    public func receive(_ envelope: TeamNoteEnvelope, savedAt: Int64) throws {
        try envelope.validate(for: target, expectedTeamId: teamId)
        guard savedAt >= 0 else { throw TeamDeliveryError.invalidTime }
        let data = try JSONEncoder().encode(envelope)
        try lock.withLock {
            try transaction {
                let previous = try archivedUnlocked(deliveryId: envelope.deliveryId)
                if let previous {
                    guard previous.envelope == envelope else { throw TeamDeliveryError.immutableConflict }
                }
                let key: [Value] = [.text(target.userId), .text(teamId), .text(envelope.deliveryId)]
                let alreadyQueued = try scalar(
                    "SELECT count(*) FROM receipt_outbox WHERE account_id=? AND team_id=? AND delivery_id=?", key
                ) != 0
                if !alreadyQueued {
                    guard try scalar("SELECT count(*) FROM receipt_outbox WHERE account_id=? AND device_id=? AND enrollment_id=?",
                                     [.text(target.userId), .text(target.deviceId), .text(target.enrollmentId)])
                            < Self.maximumPendingReceipts else {
                        throw TeamDeliveryError.queueFull
                    }
                }
                if previous == nil {
                    try execute("INSERT INTO archive VALUES (?,?,?,?,?,?,?,?)", key + [
                        .text(target.deviceId), .text(target.enrollmentId), .integer(envelope.acceptedAt), .integer(savedAt), .blob(data)
                    ])
                }
                if !alreadyQueued {
                    try execute("INSERT INTO receipt_outbox VALUES (?,?,?,?,?,?)", key + [
                        .text(target.deviceId), .text(target.enrollmentId), .text(envelope.bodySha256)
                    ])
                }
            }
        }
    }

    public func archived(deliveryId: String) throws -> ArchivedTeamNote? {
        try TeamDeliveryRules.requireID(deliveryId)
        return try lock.withLock { try archivedUnlocked(deliveryId: deliveryId) }
    }

    public func pendingReceipts(limit: Int = 100) throws -> [PendingTeamReceipt] {
        guard (1...100).contains(limit) else { throw TeamDeliveryError.invalidLimit }
        return try lock.withLock {
            let statement = try prepare("""
                SELECT delivery_id, body_sha256 FROM receipt_outbox
                WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=? ORDER BY delivery_id LIMIT ?
                """, [.text(target.userId), .text(teamId), .text(target.deviceId), .text(target.enrollmentId), .integer(Int64(limit))])
            defer { sqlite3_finalize(statement) }
            var results: [PendingTeamReceipt] = []
            while try step(statement) == SQLITE_ROW {
                results.append(PendingTeamReceipt(accountId: target.userId, teamId: teamId,
                    deliveryId: String(cString: sqlite3_column_text(statement, 0)), deviceId: target.deviceId,
                    enrollmentId: target.enrollmentId, bodySha256: String(cString: sqlite3_column_text(statement, 1))))
            }
            return results
        }
    }

    /// Call ONLY after future authenticated ACK acceptance or terminal response. Not authentication.
    /// Exact local receipt matching prevents stale/foreign responses from deleting other receipts.
    /// There is intentionally no archive deletion operation.
    public func retireReceiptAfterAuthenticatedResponse(_ receipt: PendingTeamReceipt) throws {
        guard receipt.accountId == target.userId, receipt.teamId == teamId,
              receipt.deviceId == target.deviceId, receipt.enrollmentId == target.enrollmentId else {
            throw TeamDeliveryError.invalidScope
        }
        try lock.withLock {
            try execute("""
                DELETE FROM receipt_outbox WHERE account_id=? AND team_id=? AND delivery_id=?
                AND device_id=? AND enrollment_id=? AND body_sha256=?
                """, [.text(receipt.accountId), .text(receipt.teamId), .text(receipt.deliveryId),
                      .text(receipt.deviceId), .text(receipt.enrollmentId), .text(receipt.bodySha256)])
        }
    }

    private func archivedUnlocked(deliveryId: String) throws -> ArchivedTeamNote? {
        let statement = try prepare("SELECT envelope, saved_at FROM archive WHERE account_id=? AND team_id=? AND delivery_id=?",
                                    [.text(target.userId), .text(teamId), .text(deliveryId)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        guard let bytes = sqlite3_column_blob(statement, 0) else { throw TeamDeliveryError.storage(SQLITE_CORRUPT) }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let envelope = try TeamNoteEnvelope.decodeLocalJSON(data)
        guard envelope.recipient.userId == target.userId else { throw TeamDeliveryError.invalidScope }
        // An own-account archive remains readable after enrollment changes. This does not
        // authorize sending its old-enrollment receipt or accessing remote content.
        try envelope.validate(for: envelope.recipient, expectedTeamId: teamId)
        guard envelope.deliveryId == deliveryId else { throw TeamDeliveryError.storage(SQLITE_CORRUPT) }
        return ArchivedTeamNote(envelope: envelope, savedAt: sqlite3_column_int64(statement, 1))
    }

    private enum Value { case text(String), integer(Int64), blob(Data) }

    private func prepare(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw TeamDeliveryError.storage(result) }
        do {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, transient)
                case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
                case .blob(let data): result = data.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
                }
                }
                guard result == SQLITE_OK else { throw TeamDeliveryError.storage(result) }
            }
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw TeamDeliveryError.storage(result) }
        return result
    }

    private func execute(_ sql: String, _ values: [Value] = []) throws {
        if values.isEmpty {
            let result = sqlite3_exec(database, sql, nil, nil, nil)
            guard result == SQLITE_OK else { throw TeamDeliveryError.storage(result) }
        } else {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            _ = try step(statement)
        }
    }

    private func scalar(_ sql: String, _ values: [Value] = []) throws -> Int64 {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { throw TeamDeliveryError.storage(SQLITE_ERROR) }
        return sqlite3_column_int64(statement, 0)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            do {
                try execute("ROLLBACK")
            } catch {
                // An indeterminate connection must never expose possibly uncommitted receipts.
                sqlite3_close_v2(database)
                database = nil
            }
            throw error
        }
    }
}
