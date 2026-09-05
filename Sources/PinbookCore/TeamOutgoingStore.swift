import Darwin
import Foundation
import SQLite3

public enum TeamOutgoingEventKind: String, Codable, CaseIterable, Sendable {
    case noteSubmission = "NOTE_SUBMISSION"
    case noteCorrection = "NOTE_CORRECTION"
    case reviewApproval = "REVIEW_APPROVAL"
    case reviewChangesRequested = "REVIEW_CHANGES_REQUESTED"
}

public enum TeamOutgoingError: Error, Equatable {
    case invalidTime
    case invalidRevision
    case invalidBody
    case invalidLimit
    case invalidScope
    case notFound
    case staleDraft
    case immutableConflict
    case queueFull
    case storage(Int32)
    case unsupportedSchema
}

/// Local editable work. This is never a delivery, review decision, or server mutation.
public struct TeamOutgoingDraft: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                                 CustomReflectable {
    public let accountId: String
    public let teamId: String
    public let deviceId: String
    public let enrollmentId: String
    public let draftId: String
    public let noteId: String
    public let kind: TeamOutgoingEventKind
    public let baseRevision: Int64?
    public let body: String
    public let createdAt: Int64
    public let updatedAt: Int64
    public let version: Int64

    public var description: String { "TeamOutgoingDraft(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Immutable local event awaiting future authenticated/encrypted submission.
public struct PendingTeamOutgoingEvent: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                                        CustomReflectable {
    public let accountId: String
    public let teamId: String
    public let deviceId: String
    public let enrollmentId: String
    public let eventId: String
    public let sourceDraftId: String
    public let noteId: String
    public let kind: TeamOutgoingEventKind
    public let baseRevision: Int64?
    public let body: String
    public let createdAt: Int64

    public var description: String { "PendingTeamOutgoingEvent(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Exact encrypted submission retained for retry. Re-encrypting a pending event
/// would change its immutable JWE, so retries must reuse these exact bytes.
public struct PendingTeamEncryptedSubmission: Equatable, Sendable, CustomStringConvertible,
                                              CustomDebugStringConvertible, CustomReflectable {
    public let accountId: String
    public let teamId: String
    public let deviceId: String
    public let enrollmentId: String
    public let eventId: String
    let canonicalIntent: Data
    let canonicalJWE: String
    let bodySHA256: String
    public let createdAt: Int64

    public var description: String { "PendingTeamEncryptedSubmission(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Inactive local foundation. No production screen, transport, or crypto route instantiates it.
/// Draft finalization atomically creates one immutable event and removes the editable draft.
public final class TeamOutgoingStore: @unchecked Sendable {
    public static let maximumDrafts = 100
    public static let maximumPendingEvents = 1_000

    public let sender: DeliveryTarget
    public let teamId: String
    public let directoryURL: URL
    public let databaseURL: URL

    private let lock = NSLock()
    private var database: OpaquePointer?

    public init(applicationSupportDirectory: URL, sender: DeliveryTarget, teamId: String) throws {
        try sender.validate()
        try TeamDeliveryRules.requireID(teamId)
        guard applicationSupportDirectory.isFileURL else { throw TeamOutgoingError.invalidScope }
        self.sender = sender
        self.teamId = teamId
        directoryURL = applicationSupportDirectory.appendingPathComponent("PinbookTeamOutbox", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("team-outbox.sqlite")

        let fm = FileManager.default
        var directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        var fileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        directoryAttributes[.protectionKey] = FileProtectionType.complete
        fileAttributes[.protectionKey] = FileProtectionType.complete
        #endif
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: directoryAttributes)
        guard try directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamOutgoingError.invalidScope
        }
        try fm.setAttributes(directoryAttributes, ofItemAtPath: directoryURL.path)
        try Self.excludeFromBackup(directoryURL)
        let descriptor = Darwin.open(databaseURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        if descriptor >= 0 { Darwin.close(descriptor) }
        else if errno != EEXIST { throw TeamOutgoingError.storage(SQLITE_CANTOPEN) }
        guard try databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamOutgoingError.invalidScope
        }
        try fm.setAttributes(fileAttributes, ofItemAtPath: databaseURL.path)
        try Self.excludeFromBackup(databaseURL)
        #if os(iOS) && !targetEnvironment(simulator)
        for url in [directoryURL, databaseURL] {
            guard try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? String
                    == FileProtectionType.complete.rawValue else {
                throw TeamOutgoingError.storage(SQLITE_PERM)
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
            throw TeamOutgoingError.storage(result)
        }
        database = handle
        do {
            sqlite3_busy_timeout(database, 2_000)
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=EXTRA")
            try execute("PRAGMA fullfsync=ON")
            try execute("PRAGMA temp_store=MEMORY")
            try transaction {
                let version = try scalar("PRAGMA user_version")
                guard (0...2).contains(version) else { throw TeamOutgoingError.unsupportedSchema }
                if version == 0 {
                    try execute("""
                    CREATE TABLE draft (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL,
                        draft_id TEXT NOT NULL, note_id TEXT NOT NULL, kind TEXT NOT NULL,
                        base_revision INTEGER, body TEXT NOT NULL,
                        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, version INTEGER NOT NULL,
                        PRIMARY KEY(account_id, team_id, draft_id));
                    CREATE TABLE pending_event (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL,
                        event_id TEXT NOT NULL, source_draft_id TEXT NOT NULL,
                        note_id TEXT NOT NULL, kind TEXT NOT NULL, base_revision INTEGER,
                        body TEXT NOT NULL, created_at INTEGER NOT NULL,
                        PRIMARY KEY(account_id, team_id, event_id));
                    CREATE TABLE encrypted_submission (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL,
                        event_id TEXT NOT NULL, canonical_intent BLOB NOT NULL,
                        canonical_jwe TEXT NOT NULL, body_sha256 TEXT NOT NULL,
                        created_at INTEGER NOT NULL,
                        PRIMARY KEY(account_id, team_id, event_id));
                    PRAGMA user_version=2;
                    """)
                } else if version == 1 {
                    try execute("""
                    CREATE TABLE encrypted_submission (
                        account_id TEXT NOT NULL, team_id TEXT NOT NULL,
                        device_id TEXT NOT NULL, enrollment_id TEXT NOT NULL,
                        event_id TEXT NOT NULL, canonical_intent BLOB NOT NULL,
                        canonical_jwe TEXT NOT NULL, body_sha256 TEXT NOT NULL,
                        created_at INTEGER NOT NULL,
                        PRIMARY KEY(account_id, team_id, event_id));
                    PRAGMA user_version=2;
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

    public func createDraft(draftId: String, noteId: String, kind: TeamOutgoingEventKind,
                            baseRevision: Int64?, body: String, createdAt: Int64) throws -> TeamOutgoingDraft {
        try Self.validate(draftId: draftId, noteId: noteId, kind: kind,
                          baseRevision: baseRevision, body: body, time: createdAt)
        return try lock.withLock {
            try transaction {
                guard try draftUnlocked(draftId: draftId) == nil else { throw TeamOutgoingError.immutableConflict }
                guard try scalar("""
                    SELECT count(*) FROM pending_event
                    WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=? AND source_draft_id=?
                    """, scopeValues + [.text(draftId)]) == 0 else {
                    throw TeamOutgoingError.immutableConflict
                }
                guard try scopedCount(table: "draft") < Self.maximumDrafts else { throw TeamOutgoingError.queueFull }
                try execute("""
                    INSERT INTO draft VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                    """, scopeValues + [.text(draftId), .text(noteId), .text(kind.rawValue),
                                         baseRevision.map(Value.integer) ?? .null, .text(body),
                                         .integer(createdAt), .integer(createdAt), .integer(1)])
            }
            return try requiredDraftUnlocked(draftId: draftId)
        }
    }

    /// Compare-and-swap prevents two editors from silently overwriting one another.
    public func updateDraft(draftId: String, expectedVersion: Int64, body: String,
                            updatedAt: Int64) throws -> TeamOutgoingDraft {
        try Self.validateID(draftId)
        return try lock.withLock {
            try transaction {
                let current = try requiredDraftUnlocked(draftId: draftId)
                guard current.version == expectedVersion else { throw TeamOutgoingError.staleDraft }
                try Self.validate(draftId: draftId, noteId: current.noteId, kind: current.kind,
                                  baseRevision: current.baseRevision, body: body, time: updatedAt)
                guard updatedAt >= current.updatedAt, expectedVersion < Int64.max else {
                    throw TeamOutgoingError.invalidTime
                }
                try execute("""
                    UPDATE draft SET body=?, updated_at=?, version=?
                    WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=?
                    AND draft_id=? AND version=?
                    """, [.text(body), .integer(updatedAt), .integer(expectedVersion + 1)]
                        + scopeValues + [.text(draftId), .integer(expectedVersion)])
                guard sqlite3_changes(database) == 1 else { throw TeamOutgoingError.staleDraft }
            }
            return try requiredDraftUnlocked(draftId: draftId)
        }
    }

    /// This explicit call is the only path that turns a draft into a pending event.
    /// Retrying the same event ID after a committed-but-unobserved result is idempotent.
    public func finalizeDraft(draftId: String, expectedVersion: Int64, eventId: String,
                              finalizedAt: Int64) throws -> PendingTeamOutgoingEvent {
        try Self.validateID(draftId)
        try Self.validateID(eventId)
        return try lock.withLock {
            var result: PendingTeamOutgoingEvent?
            try transaction {
                if let existing = try eventUnlocked(eventId: eventId) {
                    guard existing.sourceDraftId == draftId else { throw TeamOutgoingError.immutableConflict }
                    result = existing
                    return
                }
                let draft = try requiredDraftUnlocked(draftId: draftId)
                guard draft.version == expectedVersion else { throw TeamOutgoingError.staleDraft }
                guard finalizedAt >= draft.updatedAt else { throw TeamOutgoingError.invalidTime }
                guard try scopedCount(table: "pending_event") < Self.maximumPendingEvents else {
                    throw TeamOutgoingError.queueFull
                }
                try execute("""
                    INSERT INTO pending_event VALUES (?,?,?,?,?,?,?,?,?,?,?)
                    """, scopeValues + [.text(eventId), .text(draftId), .text(draft.noteId),
                                         .text(draft.kind.rawValue),
                                         draft.baseRevision.map(Value.integer) ?? .null,
                                         .text(draft.body), .integer(finalizedAt)])
                try execute("""
                    DELETE FROM draft WHERE account_id=? AND team_id=? AND device_id=?
                    AND enrollment_id=? AND draft_id=? AND version=?
                    """, scopeValues + [.text(draftId), .integer(expectedVersion)])
                guard sqlite3_changes(database) == 1 else { throw TeamOutgoingError.staleDraft }
                result = try eventUnlocked(eventId: eventId)
            }
            return try result ?? { throw TeamOutgoingError.storage(SQLITE_CORRUPT) }()
        }
    }

    public func discardDraft(draftId: String, expectedVersion: Int64) throws {
        try Self.validateID(draftId)
        try lock.withLock {
            try transaction {
                let current = try requiredDraftUnlocked(draftId: draftId)
                guard current.version == expectedVersion else { throw TeamOutgoingError.staleDraft }
                try execute("""
                    DELETE FROM draft WHERE account_id=? AND team_id=? AND device_id=?
                    AND enrollment_id=? AND draft_id=? AND version=?
                    """, scopeValues + [.text(draftId), .integer(expectedVersion)])
                guard sqlite3_changes(database) == 1 else { throw TeamOutgoingError.staleDraft }
            }
        }
    }

    public func drafts(limit: Int = 100) throws -> [TeamOutgoingDraft] {
        guard (1...100).contains(limit) else { throw TeamOutgoingError.invalidLimit }
        return try lock.withLock {
            let statement = try prepare("""
                SELECT draft_id,note_id,kind,base_revision,body,created_at,updated_at,version
                FROM draft WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=?
                ORDER BY updated_at DESC,draft_id DESC LIMIT ?
                """, scopeValues + [.integer(Int64(limit))])
            defer { sqlite3_finalize(statement) }
            var values: [TeamOutgoingDraft] = []
            while try step(statement) == SQLITE_ROW { values.append(try readDraft(statement)) }
            return values
        }
    }

    public func pendingEvents(limit: Int = 100) throws -> [PendingTeamOutgoingEvent] {
        guard (1...100).contains(limit) else { throw TeamOutgoingError.invalidLimit }
        return try lock.withLock {
            let statement = try prepare("""
                SELECT event_id,source_draft_id,note_id,kind,base_revision,body,created_at
                FROM pending_event WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=?
                ORDER BY created_at,event_id LIMIT ?
                """, scopeValues + [.integer(Int64(limit))])
            defer { sqlite3_finalize(statement) }
            var values: [PendingTeamOutgoingEvent] = []
            while try step(statement) == SQLITE_ROW { values.append(try readEvent(statement)) }
            return values
        }
    }

    /// Atomically freezes the exact encrypted form for one already-durable event.
    /// Exact repeats are idempotent; any changed encryption is rejected.
    func saveEncryptedSubmission(event: PendingTeamOutgoingEvent,
                                 intent: TeamDeliverySubmitIntent,
                                 canonicalJWE: String,
                                 createdAt: Int64) throws -> PendingTeamEncryptedSubmission {
        guard event.accountId == sender.userId, event.teamId == teamId,
              event.deviceId == sender.deviceId, event.enrollmentId == sender.enrollmentId,
              event.eventId == intent.deliveryId, createdAt >= event.createdAt else {
            throw TeamOutgoingError.invalidScope
        }
        let canonicalIntent = try TeamDeliverySubmitIntentCodec.encode(intent)
        try intent.verifyCanonicalJWE(canonicalJWE)
        return try lock.withLock {
            try transaction {
                guard try eventUnlocked(eventId: event.eventId) == event else {
                    throw TeamOutgoingError.staleDraft
                }
                if let existing = try encryptedSubmissionUnlocked(eventId: event.eventId) {
                    guard existing.canonicalIntent == canonicalIntent,
                          existing.canonicalJWE == canonicalJWE else {
                        throw TeamOutgoingError.immutableConflict
                    }
                    return
                }
                try execute("""
                    INSERT INTO encrypted_submission VALUES (?,?,?,?,?,?,?,?,?)
                    """, scopeValues + [.text(event.eventId), .blob(canonicalIntent),
                                           .text(canonicalJWE),
                                           .text(TeamDeliveryRules.textSHA256(event.body)),
                                           .integer(createdAt)])
            }
            return try encryptedSubmissionUnlocked(eventId: event.eventId)
                ?? { throw TeamOutgoingError.storage(SQLITE_CORRUPT) }()
        }
    }

    func encryptedSubmission(eventId: String) throws -> PendingTeamEncryptedSubmission? {
        try Self.validateID(eventId)
        return try lock.withLock { try encryptedSubmissionUnlocked(eventId: eventId) }
    }

    /// Only exact authoritative ACCEPTED status may remove an outbox item.
    func retireAcceptedSubmission(eventId: String, expectedJWESHA256: String) throws {
        try Self.validateID(eventId)
        guard expectedJWESHA256.utf8.count == 64,
              expectedJWESHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw TeamOutgoingError.invalidScope
        }
        try lock.withLock {
            try transaction {
                guard let submission = try encryptedSubmissionUnlocked(eventId: eventId),
                      let event = try eventUnlocked(eventId: eventId) else {
                    throw TeamOutgoingError.notFound
                }
                let intent = try TeamDeliverySubmitIntentCodec.decode(submission.canonicalIntent,
                    expectedDeliveryId: eventId,
                    expectedMembershipRevision: try TeamAuthWire.time(
                        TeamStrictJSON.object(submission.canonicalIntent,
                            maximumBytes: TeamDeliverySubmitIntentCodec.maximumIntentBytes),
                        "membershipRevision"),
                    expectedAudienceDigest: try TeamAuthWire.string(
                        TeamStrictJSON.object(submission.canonicalIntent,
                            maximumBytes: TeamDeliverySubmitIntentCodec.maximumIntentBytes),
                        "audienceDigest"))
                guard event.eventId == intent.deliveryId,
                      submission.bodySHA256 == TeamDeliveryRules.textSHA256(event.body),
                      intent.jweSha256 == expectedJWESHA256 else {
                    throw TeamOutgoingError.immutableConflict
                }
                try execute("""
                    DELETE FROM encrypted_submission WHERE account_id=? AND team_id=?
                    AND device_id=? AND enrollment_id=? AND event_id=?
                    """, scopeValues + [.text(eventId)])
                guard sqlite3_changes(database) == 1 else { throw TeamOutgoingError.staleDraft }
                try execute("""
                    DELETE FROM pending_event WHERE account_id=? AND team_id=?
                    AND device_id=? AND enrollment_id=? AND event_id=?
                    """, scopeValues + [.text(eventId)])
                guard sqlite3_changes(database) == 1 else { throw TeamOutgoingError.staleDraft }
            }
        }
    }

    private static func validate(draftId: String, noteId: String, kind: TeamOutgoingEventKind,
                                 baseRevision: Int64?, body: String, time: Int64) throws {
        try validateID(draftId)
        try validateID(noteId)
        guard time >= 0 else { throw TeamOutgoingError.invalidTime }
        switch kind {
        case .noteSubmission:
            guard baseRevision == nil else { throw TeamOutgoingError.invalidRevision }
            guard !TeamDeliveryRules.isBlank(body) else { throw TeamOutgoingError.invalidBody }
        case .noteCorrection:
            guard let baseRevision, baseRevision >= 0 else { throw TeamOutgoingError.invalidRevision }
            guard !TeamDeliveryRules.isBlank(body) else { throw TeamOutgoingError.invalidBody }
        case .reviewApproval, .reviewChangesRequested:
            guard let baseRevision, baseRevision >= 0 else { throw TeamOutgoingError.invalidRevision }
        }
        guard body.utf8.count <= TeamDeliveryRules.maximumTextBytes else {
            throw TeamOutgoingError.invalidBody
        }
    }

    private static func validateID(_ value: String) throws {
        do { try TeamDeliveryRules.requireID(value) }
        catch { throw TeamOutgoingError.invalidScope }
    }

    private var scopeValues: [Value] {
        [.text(sender.userId), .text(teamId), .text(sender.deviceId), .text(sender.enrollmentId)]
    }

    private func scopedCount(table: String) throws -> Int {
        Int(try scalar("SELECT count(*) FROM \(table) WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=?",
                       scopeValues))
    }

    private func draftUnlocked(draftId: String) throws -> TeamOutgoingDraft? {
        let statement = try prepare("""
            SELECT draft_id,note_id,kind,base_revision,body,created_at,updated_at,version
            FROM draft WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=? AND draft_id=?
            """, scopeValues + [.text(draftId)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        return try readDraft(statement)
    }

    private func requiredDraftUnlocked(draftId: String) throws -> TeamOutgoingDraft {
        guard let draft = try draftUnlocked(draftId: draftId) else { throw TeamOutgoingError.notFound }
        return draft
    }

    private func eventUnlocked(eventId: String) throws -> PendingTeamOutgoingEvent? {
        let statement = try prepare("""
            SELECT event_id,source_draft_id,note_id,kind,base_revision,body,created_at
            FROM pending_event WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=? AND event_id=?
            """, scopeValues + [.text(eventId)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        return try readEvent(statement)
    }

    private func encryptedSubmissionUnlocked(eventId: String) throws -> PendingTeamEncryptedSubmission? {
        let statement = try prepare("""
            SELECT canonical_intent,canonical_jwe,body_sha256,created_at FROM encrypted_submission
            WHERE account_id=? AND team_id=? AND device_id=? AND enrollment_id=? AND event_id=?
            """, scopeValues + [.text(eventId)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        let intent = try readData(statement, column: 0,
            maximumBytes: TeamDeliverySubmitIntentCodec.maximumIntentBytes)
        let jwe = try readText(statement, column: 1,
            maximumBytes: TeamDeliveryJWE.maximumSerializedBytes)
        let bodySHA256 = try readText(statement, column: 2, maximumBytes: 64)
        let createdAt = sqlite3_column_int64(statement, 3)
        guard createdAt >= 0, bodySHA256.utf8.count == 64,
              bodySHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw TeamOutgoingError.storage(SQLITE_CORRUPT)
        }
        return .init(accountId: sender.userId, teamId: teamId,
            deviceId: sender.deviceId, enrollmentId: sender.enrollmentId,
            eventId: eventId, canonicalIntent: intent, canonicalJWE: jwe,
            bodySHA256: bodySHA256,
            createdAt: createdAt)
    }

    private func readDraft(_ statement: OpaquePointer) throws -> TeamOutgoingDraft {
        let kind = try readKind(statement, column: 2)
        let draftId = try readText(statement, column: 0)
        let noteId = try readText(statement, column: 1)
        let base = readOptionalInteger(statement, column: 3)
        let body = try readText(statement, column: 4, maximumBytes: TeamDeliveryRules.maximumTextBytes)
        let created = sqlite3_column_int64(statement, 5)
        let updated = sqlite3_column_int64(statement, 6)
        let version = sqlite3_column_int64(statement, 7)
        try Self.validate(draftId: draftId, noteId: noteId, kind: kind, baseRevision: base, body: body, time: created)
        guard updated >= created, version > 0 else { throw TeamOutgoingError.storage(SQLITE_CORRUPT) }
        return TeamOutgoingDraft(accountId: sender.userId, teamId: teamId, deviceId: sender.deviceId,
                                 enrollmentId: sender.enrollmentId, draftId: draftId, noteId: noteId,
                                 kind: kind, baseRevision: base, body: body, createdAt: created,
                                 updatedAt: updated, version: version)
    }

    private func readEvent(_ statement: OpaquePointer) throws -> PendingTeamOutgoingEvent {
        let eventId = try readText(statement, column: 0)
        let sourceDraftId = try readText(statement, column: 1)
        let noteId = try readText(statement, column: 2)
        let kind = try readKind(statement, column: 3)
        let base = readOptionalInteger(statement, column: 4)
        let body = try readText(statement, column: 5, maximumBytes: TeamDeliveryRules.maximumTextBytes)
        let created = sqlite3_column_int64(statement, 6)
        try Self.validateID(eventId)
        try Self.validate(draftId: sourceDraftId, noteId: noteId, kind: kind,
                          baseRevision: base, body: body, time: created)
        return PendingTeamOutgoingEvent(accountId: sender.userId, teamId: teamId,
                                        deviceId: sender.deviceId, enrollmentId: sender.enrollmentId,
                                        eventId: eventId, sourceDraftId: sourceDraftId, noteId: noteId,
                                        kind: kind, baseRevision: base, body: body, createdAt: created)
    }

    private func readKind(_ statement: OpaquePointer, column: Int32) throws -> TeamOutgoingEventKind {
        guard let kind = TeamOutgoingEventKind(rawValue: try readText(statement, column: column, maximumBytes: 64)) else {
            throw TeamOutgoingError.storage(SQLITE_CORRUPT)
        }
        return kind
    }

    private func readText(_ statement: OpaquePointer, column: Int32, maximumBytes: Int = 128) throws -> String {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              count >= 0, count <= maximumBytes else {
            throw TeamOutgoingError.storage(SQLITE_CORRUPT)
        }
        if count == 0 { return "" }
        guard let text = sqlite3_column_text(statement, column),
              let value = String(bytes: UnsafeBufferPointer(start: text, count: count), encoding: .utf8) else {
            throw TeamOutgoingError.storage(SQLITE_CORRUPT)
        }
        return value
    }

    private func readData(_ statement: OpaquePointer, column: Int32,
                          maximumBytes: Int) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB,
              (1...maximumBytes).contains(count),
              let pointer = sqlite3_column_blob(statement, column) else {
            throw TeamOutgoingError.storage(SQLITE_CORRUPT)
        }
        return Data(bytes: pointer, count: count)
    }

    private func readOptionalInteger(_ statement: OpaquePointer, column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw TeamOutgoingError.storage(SQLITE_PERM)
        }
    }

    private enum Value {
        case text(String)
        case blob(Data)
        case integer(Int64)
        case null
    }

    private func prepare(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw TeamOutgoingError.storage(result) }
        do {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .text(let text): result = text.withCString {
                    sqlite3_bind_text(statement, index, $0, Int32(text.utf8.count), transient)
                }
                case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
                case .blob(let data): result = data.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient)
                }
                case .null: result = sqlite3_bind_null(statement, index)
                }
                guard result == SQLITE_OK else { throw TeamOutgoingError.storage(result) }
            }
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw TeamOutgoingError.storage(result) }
        return result
    }

    private func execute(_ sql: String, _ values: [Value] = []) throws {
        if values.isEmpty {
            let result = sqlite3_exec(database, sql, nil, nil, nil)
            guard result == SQLITE_OK else { throw TeamOutgoingError.storage(result) }
        } else {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            _ = try step(statement)
        }
    }

    private func scalar(_ sql: String, _ values: [Value] = []) throws -> Int64 {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { throw TeamOutgoingError.storage(SQLITE_ERROR) }
        return sqlite3_column_int64(statement, 0)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            do { try execute("ROLLBACK") }
            catch {
                sqlite3_close_v2(database)
                database = nil
            }
            throw error
        }
    }
}
