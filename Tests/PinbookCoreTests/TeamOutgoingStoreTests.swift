import Foundation
import SQLite3
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private func withOutgoingStore(_ body: (TeamOutgoingStore, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pinbook-outgoing-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sender = try DeliveryTarget(userId: "alice", deviceId: "alice-phone", enrollmentId: "alice-enrollment")
    try body(TeamOutgoingStore(applicationSupportDirectory: root, sender: sender, teamId: "team"), root)
}

private func executeOutgoingSQL(_ url: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
        throw TeamOutgoingError.storage(SQLITE_CANTOPEN)
    }
    defer { sqlite3_close(database) }
    let result = sqlite3_exec(database, sql, nil, nil, nil)
    guard result == SQLITE_OK else { throw TeamOutgoingError.storage(result) }
}

@Test func teamOutgoingDraftDoesNotBecomeAnEventUntilExplicitFinalization() throws {
    try withOutgoingStore { store, _ in
        let initialBody = "مرحبا\u{0}中文"
        let first = try store.createDraft(draftId: "draft-1", noteId: "note-1",
                                          kind: .noteSubmission, baseRevision: nil,
                                          body: initialBody, createdAt: 10)
        #expect(first.version == 1)
        #expect(first.body == initialBody)
        #expect(try store.drafts().map(\.draftId) == ["draft-1"])
        #expect(try store.pendingEvents().isEmpty)

        let updated = try store.updateDraft(draftId: "draft-1", expectedVersion: 1,
                                            body: "exact\u{0}updated", updatedAt: 11)
        #expect(updated.version == 2)
        #expect(throws: TeamOutgoingError.staleDraft) {
            try store.updateDraft(draftId: "draft-1", expectedVersion: 1, body: "lost edit", updatedAt: 12)
        }
        #expect(try store.pendingEvents().isEmpty)

        let event = try store.finalizeDraft(draftId: "draft-1", expectedVersion: 2,
                                            eventId: "event-1", finalizedAt: 12)
        #expect(event.kind == .noteSubmission)
        #expect(event.body == "exact\u{0}updated")
        #expect(try store.drafts().isEmpty)
        #expect(try store.pendingEvents() == [event])
        #expect(try store.finalizeDraft(draftId: "draft-1", expectedVersion: 2,
                                       eventId: "event-1", finalizedAt: 13) == event)
        #expect(!event.description.contains("updated"))
        #expect(!first.description.contains("draft-1"))
    }
}

@Test func teamOutgoingKindsEnforceDistinctRevisionAndBodyRules() throws {
    try withOutgoingStore { store, _ in
        #expect(throws: TeamOutgoingError.invalidRevision) {
            try store.createDraft(draftId: "bad-1", noteId: "note", kind: .noteSubmission,
                                  baseRevision: 1, body: "text", createdAt: 1)
        }
        #expect(throws: TeamOutgoingError.invalidBody) {
            try store.createDraft(draftId: "bad-2", noteId: "note", kind: .noteSubmission,
                                  baseRevision: nil, body: " \n", createdAt: 1)
        }
        #expect(throws: TeamOutgoingError.invalidRevision) {
            try store.createDraft(draftId: "bad-3", noteId: "note", kind: .noteCorrection,
                                  baseRevision: nil, body: "text", createdAt: 1)
        }
        #expect(throws: TeamOutgoingError.invalidBody) {
            try store.createDraft(draftId: "bad-4", noteId: "note", kind: .noteCorrection,
                                  baseRevision: 2, body: "\t", createdAt: 1)
        }
        #expect(throws: TeamOutgoingError.invalidRevision) {
            try store.createDraft(draftId: "bad-5", noteId: "note", kind: .reviewApproval,
                                  baseRevision: -1, body: "", createdAt: 1)
        }

        for (offset, kind) in [TeamOutgoingEventKind.noteCorrection, .reviewApproval, .reviewChangesRequested].enumerated() {
            let id = "draft-\(offset)"
            let body = kind == .noteCorrection ? "corrected" : ""
            let draft = try store.createDraft(draftId: id, noteId: "note", kind: kind,
                                              baseRevision: 4, body: body, createdAt: Int64(10 + offset))
            let event = try store.finalizeDraft(draftId: id, expectedVersion: draft.version,
                                                eventId: "event-\(offset)", finalizedAt: Int64(20 + offset))
            #expect(event.kind == kind)
            #expect(event.baseRevision == 4)
        }
        #expect(try store.pendingEvents().map(\.kind) == [.noteCorrection, .reviewApproval, .reviewChangesRequested])
    }
}

@Test func teamOutgoingStaleFinalizeAndDiscardPreserveCurrentWork() throws {
    try withOutgoingStore { store, _ in
        _ = try store.createDraft(draftId: "draft", noteId: "note", kind: .noteSubmission,
                                  baseRevision: nil, body: "one", createdAt: 1)
        let current = try store.updateDraft(draftId: "draft", expectedVersion: 1, body: "two", updatedAt: 2)
        #expect(throws: TeamOutgoingError.staleDraft) {
            try store.finalizeDraft(draftId: "draft", expectedVersion: 1, eventId: "event", finalizedAt: 3)
        }
        #expect(try store.pendingEvents().isEmpty)
        #expect(try store.drafts().first?.body == "two")
        #expect(throws: TeamOutgoingError.staleDraft) {
            try store.discardDraft(draftId: "draft", expectedVersion: 1)
        }
        try store.discardDraft(draftId: "draft", expectedVersion: current.version)
        #expect(try store.drafts().isEmpty)
        #expect(throws: TeamOutgoingError.notFound) {
            try store.discardDraft(draftId: "draft", expectedVersion: current.version)
        }
    }
}

@Test func teamOutgoingPersistsAndExactEnrollmentOwnsItsQueue() throws {
    try withOutgoingStore { store, root in
        let draft = try store.createDraft(draftId: "draft", noteId: "note", kind: .reviewApproval,
                                          baseRevision: 7, body: "approved", createdAt: 1)
        let event = try store.finalizeDraft(draftId: draft.draftId, expectedVersion: draft.version,
                                            eventId: "event", finalizedAt: 2)
        let reopened = try TeamOutgoingStore(applicationSupportDirectory: root, sender: store.sender, teamId: "team")
        #expect(try reopened.pendingEvents() == [event])

        let rotated = try DeliveryTarget(userId: "alice", deviceId: "alice-phone", enrollmentId: "new-enrollment")
        let rotatedStore = try TeamOutgoingStore(applicationSupportDirectory: root, sender: rotated, teamId: "team")
        let otherTeam = try TeamOutgoingStore(applicationSupportDirectory: root, sender: store.sender, teamId: "other-team")
        #expect(try rotatedStore.pendingEvents().isEmpty)
        #expect(try otherTeam.pendingEvents().isEmpty)
        #expect(throws: TeamOutgoingError.notFound) {
            try rotatedStore.finalizeDraft(draftId: "draft", expectedVersion: 1,
                                           eventId: "event", finalizedAt: 3)
        }
    }
}

@Test func teamOutgoingIndependentConnectionsUseDraftCompareAndSwap() throws {
    try withOutgoingStore { first, root in
        _ = try first.createDraft(draftId: "draft", noteId: "note", kind: .noteSubmission,
                                  baseRevision: nil, body: "initial", createdAt: 1)
        let second = try TeamOutgoingStore(applicationSupportDirectory: root, sender: first.sender, teamId: "team")
        _ = try first.updateDraft(draftId: "draft", expectedVersion: 1, body: "winner", updatedAt: 2)
        #expect(throws: TeamOutgoingError.staleDraft) {
            try second.updateDraft(draftId: "draft", expectedVersion: 1, body: "loser", updatedAt: 2)
        }
        #expect(try second.drafts().first?.body == "winner")
    }
}

@Test func teamOutgoingEventIdRetryCannotAliasAnotherDraft() throws {
    try withOutgoingStore { store, _ in
        let one = try store.createDraft(draftId: "one", noteId: "note-1", kind: .noteSubmission,
                                        baseRevision: nil, body: "one", createdAt: 1)
        _ = try store.finalizeDraft(draftId: one.draftId, expectedVersion: one.version,
                                    eventId: "event", finalizedAt: 2)
        _ = try store.createDraft(draftId: "two", noteId: "note-2", kind: .noteSubmission,
                                  baseRevision: nil, body: "two", createdAt: 3)
        #expect(throws: TeamOutgoingError.immutableConflict) {
            try store.finalizeDraft(draftId: "two", expectedVersion: 1,
                                    eventId: "event", finalizedAt: 4)
        }
        #expect(try store.drafts().map(\.draftId) == ["two"])
        #expect(try store.pendingEvents().count == 1)
    }
}

@Test func teamOutgoingRejectsBadInputLimitsAndCorruptRows() throws {
    try withOutgoingStore { store, _ in
        for (draftId, noteId, time) in [("../bad", "note", Int64(1)), ("draft", "含义", 1), ("draft", "note", -1)] {
            #expect(throws: (any Error).self) {
                try store.createDraft(draftId: draftId, noteId: noteId, kind: .noteSubmission,
                                      baseRevision: nil, body: "body", createdAt: time)
            }
        }
        #expect(throws: TeamOutgoingError.invalidBody) {
            try store.createDraft(draftId: "large", noteId: "note", kind: .noteSubmission,
                                  baseRevision: nil, body: String(repeating: "a", count: 32_769), createdAt: 1)
        }
        #expect(throws: TeamOutgoingError.invalidLimit) { try store.drafts(limit: 0) }
        #expect(throws: TeamOutgoingError.invalidLimit) { try store.pendingEvents(limit: 101) }

        _ = try store.createDraft(draftId: "draft", noteId: "note", kind: .noteSubmission,
                                  baseRevision: nil, body: "body", createdAt: 1)
        try executeOutgoingSQL(store.databaseURL, "UPDATE draft SET kind='UNKNOWN' WHERE draft_id='draft'")
        #expect(throws: TeamOutgoingError.storage(SQLITE_CORRUPT)) { try store.drafts() }
    }
}

@Test func teamOutgoingDraftCapFailsWithoutCreatingAnEvent() throws {
    try withOutgoingStore { store, _ in
        for index in 0..<TeamOutgoingStore.maximumDrafts {
            _ = try store.createDraft(draftId: "draft-\(index)", noteId: "note-\(index)",
                                      kind: .noteSubmission, baseRevision: nil,
                                      body: "body", createdAt: Int64(index))
        }
        #expect(throws: TeamOutgoingError.queueFull) {
            try store.createDraft(draftId: "overflow", noteId: "overflow", kind: .noteSubmission,
                                  baseRevision: nil, body: "body", createdAt: 101)
        }
        #expect(try store.drafts().count == 100)
        #expect(try store.pendingEvents().isEmpty)
    }
}

@Test func teamOutgoingStoreUsesRestrictedExcludedFiles() throws {
    try withOutgoingStore { store, _ in
        for url in [store.directoryURL, store.databaseURL] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
            let permissions = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            #expect((permissions.intValue & 0o077) == 0)
        }
    }
}
