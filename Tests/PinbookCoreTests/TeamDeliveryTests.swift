import Foundation
import SQLite3
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class FixtureBundleMarker {}
private struct TeamVectors: Decodable {
    let contract: String
    let validEnvelope: TeamNoteEnvelope
    let targets: [DeliveryTarget]
    let retentionCases: [RetentionCase]
    struct RetentionCase: Decodable {
        let now: Int64
        let acknowledgedUsers: [String]
        let revokedUsers: [String]
        let expected: String
    }
}

private func vectors() throws -> TeamVectors {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: FixtureBundleMarker.self)
    #endif
    let url = try #require(bundle.url(forResource: "team-delivery-v1-vectors", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(TeamVectors.self, from: Data(contentsOf: url))
}

private func changed(_ original: TeamNoteEnvelope, _ fields: [String: Any]) throws -> TeamNoteEnvelope {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    json.merge(fields) { _, new in new }
    return try TeamNoteEnvelope.decodeLocalJSON(JSONSerialization.data(withJSONObject: json))
}

private func withStore(_ body: (TeamInboxStore, URL, TeamNoteEnvelope) throws -> Void) throws {
    let envelope = try vectors().validEnvelope
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-team-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
    try body(store, root, envelope)
}

private func rawSQL(_ url: URL, _ sql: String) throws {
    var handle: OpaquePointer?
    #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
        throw TeamDeliveryError.storage(sqlite3_errcode(handle))
    }
}

@Test func teamSharedCrossPlatformVectors() throws {
    let fixture = try vectors()
    #expect(fixture.contract == "pinbook-team-delivery-local-v1-draft2")
    let envelope = fixture.validEnvelope
    try envelope.validate(for: envelope.recipient, expectedTeamId: envelope.teamId)
    let retention = try DeliveryRetention(acceptedAt: envelope.acceptedAt, targets: Set(fixture.targets), authorUserId: envelope.authorUserId)
    #expect(retention.expiresAt == envelope.expiresAt)
    for test in fixture.retentionCases {
        let result = try retention.deletionReason(serverNow: test.now,
            acknowledged: Set(fixture.targets.filter { test.acknowledgedUsers.contains($0.userId) }),
            cancelled: Set(fixture.targets.filter { test.revokedUsers.contains($0.userId) }))
        #expect((result?.rawValue ?? "KEEP") == test.expected)
    }
}

@Test func teamRetentionRejectsEmptySenderDuplicateDevicesAndOverflow() throws {
    let alice = try DeliveryTarget(userId: "alice", deviceId: "phone", enrollmentId: "alice-enrollment")
    #expect(throws: TeamDeliveryError.invalidTargets) {
        try DeliveryRetention(acceptedAt: 1, targets: [], authorUserId: "author")
    }
    #expect(throws: TeamDeliveryError.invalidTargets) {
        try DeliveryRetention(acceptedAt: 1, targets: [alice], authorUserId: "alice")
    }
    for other in [try DeliveryTarget(userId: "alice", deviceId: "other", enrollmentId: "other-enrollment"),
                  try DeliveryTarget(userId: "bob", deviceId: "phone", enrollmentId: "other-enrollment"),
                  try DeliveryTarget(userId: "bob", deviceId: "other", enrollmentId: "alice-enrollment")] {
        #expect(throws: TeamDeliveryError.invalidTargets) {
            try DeliveryRetention(acceptedAt: 1, targets: [alice, other], authorUserId: "author")
        }
    }
    for time in [Int64(-1), Int64.max, Int64.max - TeamDeliveryRules.retentionMilliseconds + 1] {
        #expect(throws: TeamDeliveryError.invalidTime) { try TeamDeliveryRules.expiresAt(acceptedAt: time) }
    }
    #expect(try TeamDeliveryRules.expiresAt(acceptedAt: Int64.max - TeamDeliveryRules.retentionMilliseconds) == Int64.max)
}

@Test func teamTargetsAreFrozenAndForeignACKsFailClosed() throws {
    let fixture = try vectors()
    var targets = Set(fixture.targets)
    let retention = try DeliveryRetention(acceptedAt: 1, targets: targets, authorUserId: "author")
    targets.remove(fixture.targets[1])
    #expect(try retention.deletionReason(serverNow: 1, acknowledged: targets) == nil)
    let foreign = try DeliveryTarget(userId: "alice", deviceId: "replacement", enrollmentId: "replacement-enrollment")
    #expect(throws: TeamDeliveryError.invalidTargets) { try retention.deletionReason(serverNow: 1, acknowledged: [foreign]) }
    #expect(throws: TeamDeliveryError.invalidTargets) { try retention.deletionReason(serverNow: 1, acknowledged: [], cancelled: [foreign]) }
    #expect(throws: TeamDeliveryError.invalidTime) { try retention.deletionReason(serverNow: 0, acknowledged: []) }
    #expect(try retention.deletionReason(serverNow: retention.expiresAt, acknowledged: retention.targets) == .expired)
    let alice = fixture.targets[0]
    #expect(throws: TeamDeliveryError.invalidTargets) {
        try retention.deletionReason(serverNow: 1, acknowledged: [alice], cancelled: [alice])
    }
    let rotated = try DeliveryTarget(userId: alice.userId, deviceId: alice.deviceId, enrollmentId: "rotated")
    #expect(throws: TeamDeliveryError.invalidTargets) {
        try retention.deletionReason(serverNow: 1, acknowledged: [rotated])
    }
}

@Test func teamPayloadRejectsWrongScopeVersionChecksumIDsDeadlineAndAllMedia() throws {
    try withStore { store, _, good in
        let invalid: [[String: Any]] = [
            ["protocolVersion": 2], ["teamId": "foreign"], ["teamId": "../other"],
            ["body": "changed"], ["bodySha256": good.bodySha256.uppercased()],
            ["expiresAt": good.expiresAt + 1], ["acceptedAt": -1],
            ["attachmentCount": 1], ["attachmentCount": -1], ["authorUserId": "alice"],
            ["recipient": ["userId": "alice", "deviceId": "replacement", "enrollmentId": "alice-phone-enrollment"]],
            ["recipient": ["userId": "bob", "deviceId": "alice-phone", "enrollmentId": "alice-phone-enrollment"]],
            ["recipient": ["userId": "alice", "deviceId": "alice-phone", "enrollmentId": "replacement-enrollment"]],
            ["noteId": String(repeating: "a", count: 129)], ["deliveryId": "含义"]
        ]
        for fields in invalid {
            let envelope = try changed(good, fields)
            #expect(throws: (any Error).self) { try store.receive(envelope, savedAt: 2000) }
        }
        #expect(try store.archived(deliveryId: good.deliveryId) == nil)
        #expect(try store.pendingReceipts().isEmpty)
    }
}

@Test func teamTextUsesExactUTF8NotNormalizationAndRejectsInvalidUnicode() throws {
    let good = try vectors().validEnvelope
    for body in [String(repeating: "a", count: 32768), "مرحبا 中文 اردو", "a\u{0}b", "é", "e\u{301}"] {
        let envelope = try changed(good, ["body": body, "bodySha256": TeamDeliveryRules.textSHA256(body)])
        try envelope.validate(for: good.recipient, expectedTeamId: good.teamId)
    }
    #expect(TeamDeliveryRules.textSHA256("é") != TeamDeliveryRules.textSHA256("e\u{301}"))
    for body in ["", " \n\t\u{A0}", String(repeating: "a", count: 32769), String(repeating: "中", count: 11000)] {
        let envelope = try changed(good, ["body": body, "bodySha256": TeamDeliveryRules.textSHA256(body)])
        #expect(throws: TeamDeliveryError.invalidBody) { try envelope.validate(for: good.recipient, expectedTeamId: good.teamId) }
    }
    let original = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
    let unpaired = original.replacingOccurrences(of: "\"abc\"", with: "\"\\ud800\"")
    #expect(throws: (any Error).self) { try TeamNoteEnvelope.decodeLocalJSON(Data(unpaired.utf8)) }
    #expect(throws: TeamDeliveryError.invalidBody) { try TeamNoteEnvelope.decodeLocalJSON(Data([0xFF])) }
    #expect(throws: TeamDeliveryError.invalidBody) { try TeamNoteEnvelope.decodeLocalJSON(Data(repeating: 32, count: 262145)) }
}

@Test func teamArchiveAndReceiptPersistAcrossConnectionRestartAndRetirementPreservesArchive() throws {
    try withStore { store, root, envelope in
        try store.receive(envelope, savedAt: envelope.expiresAt + 1)
        let reopened = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
        let receipt = try #require(reopened.pendingReceipts().first)
        #expect(try reopened.archived(deliveryId: envelope.deliveryId)?.envelope == envelope)
        try reopened.retireReceiptAfterAuthenticatedResponse(receipt)
        try reopened.retireReceiptAfterAuthenticatedResponse(receipt)
        #expect(try store.pendingReceipts().isEmpty)
        #expect(try store.archived(deliveryId: envelope.deliveryId)?.savedAt == envelope.expiresAt + 1)
        // A retry requeues its receipt, but never resets the saved or accepted timestamps.
        try store.receive(envelope, savedAt: envelope.expiresAt + 10)
        #expect(try store.pendingReceipts().count == 1)
        #expect(try store.archived(deliveryId: envelope.deliveryId)?.savedAt == envelope.expiresAt + 1)
    }
}

@Test func teamImmutableRedeliveryRejectsContentAndMetadataChanges() throws {
    try withStore { store, _, good in
        try store.receive(good, savedAt: 2000)
        try store.receive(good, savedAt: 3000)
        for fields: [String: Any] in [
            ["body": "changed", "bodySha256": TeamDeliveryRules.textSHA256("changed")],
            ["noteId": "other-note"], ["authorUserId": "other-author"],
            ["acceptedAt": good.acceptedAt + 1, "expiresAt": good.expiresAt + 1]
        ] {
            let changed = try changed(good, fields)
            #expect(throws: TeamDeliveryError.immutableConflict) { try store.receive(changed, savedAt: 4000) }
        }
        #expect(try store.archived(deliveryId: good.deliveryId)?.envelope == good)
        #expect(try store.archived(deliveryId: good.deliveryId)?.savedAt == 2000)
        #expect(try store.pendingReceipts().count == 1)
    }
}

@Test func teamReceiptInsertFailureRollsBackArchiveDurably() throws {
    try withStore { store, root, envelope in
        try rawSQL(store.databaseURL, "CREATE TRIGGER reject_receipt BEFORE INSERT ON receipt_outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        #expect(throws: (any Error).self) { try store.receive(envelope, savedAt: 2000) }
        let reopened = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
        #expect(try reopened.archived(deliveryId: envelope.deliveryId) == nil)
        #expect(try reopened.pendingReceipts().isEmpty)
        try rawSQL(store.databaseURL, "DROP TRIGGER reject_receipt")
        try reopened.receive(envelope, savedAt: 3000)
        #expect(try reopened.pendingReceipts().count == 1)
    }
}

@Test func teamScopeIsolationAndForeignReceiptCannotRetireLocalReceipt() throws {
    try withStore { store, root, envelope in
        try store.receive(envelope, savedAt: 2000)
        let bob = try DeliveryTarget(userId: "bob", deviceId: "bob-phone", enrollmentId: "bob-enrollment")
        let otherAccount = try TeamInboxStore(applicationSupportDirectory: root, target: bob, teamId: envelope.teamId)
        let otherTeam = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: "other")
        for other in [otherAccount, otherTeam] {
            #expect(try other.archived(deliveryId: envelope.deliveryId) == nil)
            #expect(try other.pendingReceipts().isEmpty)
            let receipt = try #require(store.pendingReceipts().first)
            #expect(throws: TeamDeliveryError.invalidScope) { try other.retireReceiptAfterAuthenticatedResponse(receipt) }
        }
        let wrongHash = PendingTeamReceipt(accountId: envelope.recipient.userId, teamId: envelope.teamId,
            deliveryId: envelope.deliveryId, deviceId: envelope.recipient.deviceId,
            enrollmentId: envelope.recipient.enrollmentId, bodySha256: "stale")
        try store.retireReceiptAfterAuthenticatedResponse(wrongHash)
        #expect(try store.pendingReceipts().count == 1)
        for limit in [-1, 0, 101] {
            #expect(throws: TeamDeliveryError.invalidLimit) { try store.pendingReceipts(limit: limit) }
        }
    }
}

@Test func teamStoreIsSeparateBackupExcludedAndRestricted() throws {
    try withStore { store, root, envelope in
        #expect(store.databaseURL.deletingLastPathComponent().lastPathComponent == "PinbookTeamInbox")
        let personal = root.appendingPathComponent("personal-fixture")
        let bytes = Data("unchanged-personal".utf8)
        try bytes.write(to: personal)
        try store.receive(envelope, savedAt: 2000)
        for url in [store.directoryURL, store.databaseURL] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
        #expect(try FileManager.default.attributesOfItem(atPath: store.directoryURL.path)[.posixPermissions] as? Int == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: store.databaseURL.path)[.posixPermissions] as? Int == 0o600)
        #expect(try Data(contentsOf: personal) == bytes)
    }
}

#if os(iOS)
#if targetEnvironment(simulator)
@Test(.disabled("Simulator returns no hardware file-protection attribute; physical-device gate remains open."))
#else
@Test
#endif
func teamHardwareFileProtectionRequiresPhysicalDevice() throws {
    try withStore { store, _, envelope in
        try store.receive(envelope, savedAt: 2000)
        for url in [store.directoryURL, store.databaseURL] {
            let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? String
            #expect(protection == FileProtectionType.complete.rawValue)
        }
    }
}
#endif

@Test func teamFutureSchemaFailsClosedWithoutDestructiveMigration() throws {
    try withStore { store, root, envelope in
        try store.receive(envelope, savedAt: 2000)
        try rawSQL(store.databaseURL, "PRAGMA user_version=2")
        #expect(throws: TeamDeliveryError.unsupportedSchema) {
            try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
        }
        #expect(try store.archived(deliveryId: envelope.deliveryId)?.envelope == envelope)
    }
}

@Test func teamMissingEnrollmentIsNotDefaultedAndReplacementCannotACKOldDelivery() throws {
    try withStore { store, root, envelope in
        #expect(throws: (any Error).self) {
            try changed(envelope, ["recipient": ["userId": "alice", "deviceId": "alice-phone"]])
        }
        try store.receive(envelope, savedAt: 2000)
        let replacement = try DeliveryTarget(userId: envelope.recipient.userId,
            deviceId: envelope.recipient.deviceId, enrollmentId: "replacement")
        let rotated = try TeamInboxStore(applicationSupportDirectory: root, target: replacement, teamId: envelope.teamId)
        #expect(try rotated.pendingReceipts().isEmpty)
        let oldReceipt = try #require(store.pendingReceipts().first)
        #expect(throws: TeamDeliveryError.invalidScope) { try rotated.retireReceiptAfterAuthenticatedResponse(oldReceipt) }
        #expect(throws: TeamDeliveryError.invalidScope) { try rotated.receive(envelope, savedAt: 3000) }
        let changedTarget = try changed(envelope, ["recipient": ["userId": replacement.userId,
            "deviceId": replacement.deviceId, "enrollmentId": replacement.enrollmentId]])
        #expect(throws: TeamDeliveryError.immutableConflict) { try rotated.receive(changedTarget, savedAt: 3000) }
        #expect(try rotated.archived(deliveryId: envelope.deliveryId)?.envelope == envelope)
        #expect(try store.pendingReceipts().count == 1)
    }
}

@Test func teamDurableReopenAfterAllConnectionsClose() throws {
    let envelope = try vectors().validEnvelope
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-team-reopen-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func saveAndClose() throws {
        let store = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
        try store.receive(envelope, savedAt: 2000)
    }
    try saveAndClose()
    let reopened = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
    #expect(try reopened.archived(deliveryId: envelope.deliveryId)?.envelope == envelope)
    #expect(try reopened.pendingReceipts().count == 1)
}

@Test func teamConcurrentRedeliveryFromIndependentConnectionsIsIdempotent() async throws {
    let envelope = try vectors().validEnvelope
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-team-concurrent-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
    let second = try TeamInboxStore(applicationSupportDirectory: root, target: envelope.recipient, teamId: envelope.teamId)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<16 {
            group.addTask { try (index.isMultiple(of: 2) ? first : second).receive(envelope, savedAt: Int64(2000 + index)) }
        }
        try await group.waitForAll()
    }
    #expect(try first.pendingReceipts().count == 1)
    #expect(try second.archived(deliveryId: envelope.deliveryId)?.envelope == envelope)
}

@Test func teamQueueCapacityRejectsAtomicallyWithoutDiscardingArchives() throws {
    try withStore { store, root, envelope in
        for index in 0..<TeamInboxStore.maximumPendingReceipts {
            try store.receive(changed(envelope, ["deliveryId": "delivery-\(index)"]), savedAt: 2000)
        }
        #expect(try store.pendingReceipts().count == 100)
        // Already queued retries remain idempotent even when the queue is full.
        try store.receive(changed(envelope, ["deliveryId": "delivery-0"]), savedAt: 3000)
        #expect(throws: TeamDeliveryError.queueFull) { try store.receive(envelope, savedAt: 3000) }
        #expect(try store.archived(deliveryId: envelope.deliveryId) == nil)
        // A different account/device/enrollment has its own bound; personal data is unrelated.
        let bob = try DeliveryTarget(userId: "bob", deviceId: "bob-phone", enrollmentId: "bob-enrollment")
        let other = try TeamInboxStore(applicationSupportDirectory: root, target: bob, teamId: envelope.teamId)
        try other.receive(changed(envelope, ["recipient": ["userId": bob.userId,
            "deviceId": bob.deviceId, "enrollmentId": bob.enrollmentId]]), savedAt: 3000)
        #expect(try other.pendingReceipts().count == 1)
        let receipt = try #require(store.pendingReceipts().first)
        try store.retireReceiptAfterAuthenticatedResponse(receipt)
        try store.receive(envelope, savedAt: 4000)
        #expect(try store.archived(deliveryId: receipt.deliveryId) != nil)
        #expect(try store.archived(deliveryId: envelope.deliveryId)?.savedAt == 4000)
    }
}
