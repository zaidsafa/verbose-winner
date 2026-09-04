import CryptoKit
import Foundation
import Darwin
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class ArchiveFixtureBundleMarker {}
private struct PublicArchiveVector: Decodable {
    let profile: String
    let keyHex: String
    let nonceHex: String?
    let protectedHeader: String
    let plaintext: String
    let compact: String
}

private func publicArchiveVector(name: String = "team-archive-v1-vector") throws -> PublicArchiveVector {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: ArchiveFixtureBundleMarker.self)
    #endif
    let url = try #require(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(PublicArchiveVector.self, from: Data(contentsOf: url))
}

private func publicHexBytes(_ hex: String) -> Data {
    let chars = Array(hex)
    return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
}

// PUBLIC conformance key only, never runtime key custody.
private func publicTestKey() -> SymmetricKey { SymmetricKey(data: Data(0..<32)) }

private func portableNote(delivery: String = "delivery", team: String = "team", body: String = "abc",
                          savedAt: Int64 = 1500) throws -> ArchivedTeamNote {
    let target = try DeliveryTarget(userId: "alice", deviceId: "old-phone", enrollmentId: "old-enrollment")
    return ArchivedTeamNote(envelope: TeamNoteEnvelope(protocolVersion: 1, teamId: team, deliveryId: delivery,
        noteId: "note", authorUserId: "sender", recipient: target, body: body,
        bodySha256: TeamDeliveryRules.textSHA256(body), acceptedAt: 1000,
        expiresAt: 2_592_001_000, attachmentCount: 0), savedAt: savedAt)
}

private func withPortableStore(_ body: (TeamInboxStore, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-archive-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try DeliveryTarget(userId: "alice", deviceId: "current-phone", enrollmentId: "current-enrollment")
    let store = try TeamInboxStore(applicationSupportDirectory: root, target: target, teamId: "team")
    try body(store, root)
}

/// Produces authenticated malformed test payloads to exercise validation after successful decryption.
private func sealedPublicTestPayload(_ data: Data) throws -> String {
    let header = TeamArchiveJWE.encodedHeader
    let nonce = try AES.GCM.Nonce(data: Data(0..<12)) // PUBLIC fixture nonce, test code only.
    let box = try AES.GCM.seal(data, using: publicTestKey(), nonce: nonce, authenticating: Data(header.utf8))
    return [header, "", TeamArchiveJWE.base64URL(Data(0..<12)), TeamArchiveJWE.base64URL(box.ciphertext),
            TeamArchiveJWE.base64URL(box.tag)].joined(separator: ".")
}

private final class FakeTeamRecoveryKeychain: TeamRecoveryKeychain, @unchecked Sendable {
    var addStatus: OSStatus = errSecSuccess
    var copyStatus: OSStatus = errSecItemNotFound
    var copyResult: CFTypeRef?
    var added: [[String: Any]] = []
    var copied: [[String: Any]] = []
    func add(_ query: [String: Any]) -> OSStatus { added.append(query); return addStatus }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        copied.append(query)
        return (copyStatus, copyResult)
    }
}

@Suite(.serialized)
struct TeamPortableArchiveTests {
    @Test func recoveryKeyCustodyUsesDeviceOnlyProtectionAndRefusesReplacement() throws {
        let backend = FakeTeamRecoveryKeychain()
        let store = TeamRecoveryKeyStore(testService: "public-policy-test", keychain: backend)
        try store.storeNew(publicTestKey(), accountId: "alice")
        let attributes = try #require(backend.added.first)
        #expect(attributes[kSecAttrService as String] as? String == "public-policy-test")
        #expect(attributes[kSecAttrAccount as String] as? String == "alice")
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(attributes[kSecValueData as String] as? Data == Data(0..<32))
        #expect(attributes[kSecAttrAccessGroup as String] == nil)
        backend.addStatus = errSecDuplicateItem
        #expect(throws: TeamRecoveryKeyError.alreadyExists) { try store.storeNew(publicTestKey(), accountId: "alice") }
        backend.addStatus = errSecInteractionNotAllowed
        #expect(throws: TeamRecoveryKeyError.unavailable(errSecInteractionNotAllowed)) {
            try store.storeNew(publicTestKey(), accountId: "alice")
        }
    }

    @Test func recoveryKeyLoadSeparatesMissingFromLockedAndNeverCreatesAKey() throws {
        let backend = FakeTeamRecoveryKeychain()
        let store = TeamRecoveryKeyStore(testService: "public-policy-test", keychain: backend)
        #expect(try store.load(accountId: "alice") == nil)
        let query = try #require(backend.copied.first)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecReturnAttributes as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecDecode, errSecNotAvailable] {
            backend.copyStatus = status
            #expect(throws: TeamRecoveryKeyError.unavailable(status)) { try store.load(accountId: "alice") }
        }
        #expect(backend.added.isEmpty)
    }

    @Test func recoveryKeyLoadValidatesStoredScopeProtectionAndKeyLength() throws {
        let backend = FakeTeamRecoveryKeychain()
        let store = TeamRecoveryKeyStore(testService: "public-policy-test", keychain: backend)
        try store.storeNew(publicTestKey(), accountId: "alice")
        let valid = try #require(backend.added.first)
        backend.copyStatus = errSecSuccess
        backend.copyResult = valid as CFDictionary
        #expect(try store.load(accountId: "alice") == publicTestKey())
        let invalid: [(String, Any)] = [
            (kSecAttrService as String, "other-service"), (kSecAttrAccount as String, "bob"),
            (kSecAttrSynchronizable as String, true),
            (kSecAttrAccessible as String, kSecAttrAccessibleAfterFirstUnlock),
            (kSecValueData as String, Data(repeating: 0, count: 16))]
        for (field, value) in invalid {
            var changed = valid
            changed[field] = value
            backend.copyResult = changed as CFDictionary
            #expect(throws: TeamRecoveryKeyError.invalidStoredItem) { try store.load(accountId: "alice") }
        }
        backend.copyResult = nil
        #expect(throws: TeamRecoveryKeyError.invalidStoredItem) { try store.load(accountId: "alice") }
    }

    @Test func recoveryKeyRejectsInvalidInputBeforeKeychainAccess() throws {
        let backend = FakeTeamRecoveryKeychain()
        let store = TeamRecoveryKeyStore(testService: "public-policy-test", keychain: backend)
        #expect(throws: TeamRecoveryKeyError.invalidKey) {
            try store.storeNew(SymmetricKey(size: .bits128), accountId: "alice")
        }
        for account in ["", "foreign/account", String(repeating: "a", count: 129)] {
            #expect(throws: TeamDeliveryError.invalidIdentifier) { try store.storeNew(publicTestKey(), accountId: account) }
            #expect(throws: TeamDeliveryError.invalidIdentifier) { try store.load(accountId: account) }
        }
        #expect(backend.added.isEmpty && backend.copied.isEmpty)
    }

    #if os(iOS)
    @Test func recoveryKeyRoundTripsInIsolatedSystemKeychainWithoutOverwriting() throws {
        // Known PUBLIC test key in a unique service; never query/delete the app's real service.
        let service = "com.zaidsafa.pinbook.tests.recovery.\(UUID().uuidString)"
        defer {
            let cleanup = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service,
                               kSecAttrAccount as String: "alice",
                               kSecAttrSynchronizable as String: false,
                               kSecUseDataProtectionKeychain as String: true] as CFDictionary)
            #expect(cleanup == errSecSuccess || cleanup == errSecItemNotFound)
        }
        let store = TeamRecoveryKeyStore(testService: service)
        #expect(try store.load(accountId: "alice") == nil)
        try store.storeNew(publicTestKey(), accountId: "alice")
        let reopened = TeamRecoveryKeyStore(testService: service)
        #expect(try reopened.load(accountId: "alice") == publicTestKey())
        #expect(try reopened.load(accountId: "bob") == nil)
        #expect(throws: TeamRecoveryKeyError.alreadyExists) {
            try reopened.storeNew(SymmetricKey(data: Data(repeating: 99, count: 32)), accountId: "alice")
        }
        #expect(try reopened.load(accountId: "alice") == publicTestKey())
    }
    #endif

    @Test func inboxPagingIsBoundedStableAndPreservesHistoricalNotesWithoutACKs() throws {
        try withPortableStore { store, _ in
            let notes = try [portableNote(delivery: "a", savedAt: 100), portableNote(delivery: "b", savedAt: 200),
                             portableNote(delivery: "c", savedAt: 200), portableNote(delivery: "d", savedAt: 300)]
            let archive = try TeamPortableArchive(accountId: "alice", exportedAt: 400, notes: notes)
            _ = try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(archive, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let first = try store.archivePage(limit: 2)
            #expect(first.notes.map(\.envelope.deliveryId) == ["d", "c"])
            let cursor = try #require(first.nextCursor)
            let second = try store.archivePage(before: cursor, limit: 2)
            #expect(second.notes.map(\.envelope.deliveryId) == ["b", "a"])
            #expect(second.nextCursor == nil)
            #expect(try store.archivePage(before: cursor, limit: 2) == second)
            #expect(first.notes[0].envelope.recipient.enrollmentId == "old-enrollment")
            #expect(try store.pendingReceipts().isEmpty)
            for badLimit in [0, -1, 101, Int.max] {
                #expect(throws: TeamDeliveryError.invalidLimit) { try store.archivePage(limit: badLimit) }
            }
        }
    }

    @Test func inboxPageAndCursorRemainAccountAndTeamScoped() throws {
        try withPortableStore { store, root in
            let archive = try TeamPortableArchive(accountId: "alice", exportedAt: 400,
                notes: [portableNote(delivery: "a"), portableNote(delivery: "b"), portableNote(team: "other-team")])
            _ = try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(archive, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let cursor = try #require(try store.archivePage(limit: 1).nextCursor)
            let otherTeam = try TeamInboxStore(applicationSupportDirectory: root, target: store.target, teamId: "other-team")
            #expect(try otherTeam.archivePage().notes.count == 1)
            #expect(throws: TeamDeliveryError.invalidScope) { try otherTeam.archivePage(before: cursor) }
            let bob = try DeliveryTarget(userId: "bob", deviceId: "bob-phone", enrollmentId: "bob-enrollment")
            let otherAccount = try TeamInboxStore(applicationSupportDirectory: root, target: bob, teamId: "team")
            #expect(try otherAccount.archivePage().notes.isEmpty)
            #expect(try otherAccount.archivePage().nextCursor == nil)
            #expect(throws: TeamDeliveryError.invalidScope) { try otherAccount.archivePage(before: cursor) }
        }
    }

    @Test func inboxPageDoesNotRepeatOldRowsAfterNewerInsertionAndWorksAfterReopen() throws {
        try withPortableStore { store, root in
            let initial = try TeamPortableArchive(accountId: "alice", exportedAt: 400,
                notes: [portableNote(delivery: "a", savedAt: 100), portableNote(delivery: "b", savedAt: 200)])
            _ = try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(initial, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let cursor = try #require(try store.archivePage(limit: 1).nextCursor)
            let reopened = try TeamInboxStore(applicationSupportDirectory: root, target: store.target, teamId: "team")
            let newer = try TeamPortableArchive(accountId: "alice", exportedAt: 400,
                notes: [portableNote(delivery: "c", savedAt: 300)])
            _ = try reopened.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(newer, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let next = try reopened.archivePage(before: cursor, limit: 1)
            #expect(next.notes.map(\.envelope.deliveryId) == ["a"])
            #expect(next.nextCursor == nil)
            #expect(try reopened.archivePage(limit: 1).notes.map(\.envelope.deliveryId) == ["c"])
            #expect(try reopened.pendingReceipts().isEmpty)
        }
    }

    @Test func boundedImportReaderAcceptsShortReadsAndExactLimit() throws {
        let bytes = Array("abc.def".utf8)
        var offset = 0
        let result = try TeamArchiveImport.readBoundedCompact(maximumBytes: bytes.count) { requested in
            #expect(requested > 0 && requested <= 64 * 1024)
            let end = min(offset + 2, bytes.count)
            defer { offset = end }
            return Data(bytes[offset..<end])
        }
        #expect(result == "abc.def")
        #expect(try TeamArchiveImport.readBoundedCompact(maximumBytes: 0) { _ in Data() } == "")
    }

    @Test func boundedImportReaderRejectsGrowthNonASCIIAndReadFailures() throws {
        var calls = 0
        #expect(throws: TeamArchiveError.tooLarge) {
            try TeamArchiveImport.readBoundedCompact(maximumBytes: 3) { requested in
                calls += 1
                return Data(repeating: 65, count: min(requested, 3))
            }
        }
        #expect(calls == 2) // Includes the one-byte EOF probe after reaching the bound.
        #expect(throws: TeamArchiveError.tooLarge) {
            try TeamArchiveImport.readBoundedCompact(maximumBytes: 1) { _ in Data(repeating: 65, count: 3) }
        }
        #expect(throws: TeamArchiveError.invalidFormat) {
            try TeamArchiveImport.readBoundedCompact { _ in Data([0xff]) }
        }
        var partialReads = 0
        #expect(throws: TeamArchiveError.fileUnavailable) {
            try TeamArchiveImport.readBoundedCompact { _ in
                partialReads += 1
                if partialReads == 1 { return Data("partial".utf8) }
                throw TeamArchiveError.fileUnavailable
            }
        }
    }

    @Test func importFileRejectsUnsupportedInputsAndOversizeBeforeLoading() throws {
        try withPortableStore { _, root in
            for url in [root, root.appendingPathComponent("missing"), URL(string: "https://example.invalid/archive")!,
                        URL(string: "file:///tmp/pinbook%00other-file")!] {
                #expect(throws: TeamArchiveError.fileUnavailable) { try TeamArchiveImport.readCompactFile(url) }
            }
            let file = root.appendingPathComponent("oversized.jwe")
            #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(TeamArchiveJWE.maximumCompactBytes + 1))
            #expect(throws: TeamArchiveError.tooLarge) { try TeamArchiveImport.readCompactFile(file) }
            let link = root.appendingPathComponent("link.jwe")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            #expect(throws: TeamArchiveError.fileUnavailable) { try TeamArchiveImport.readCompactFile(link) }
            let fifo = root.appendingPathComponent("fifo.jwe")
            #expect(mkfifo(fifo.path, 0o600) == 0)
            #expect(throws: TeamArchiveError.fileUnavailable) { try TeamArchiveImport.readCompactFile(fifo) }
        }
    }

    @Test func preparedFileIsAuthenticatedAndUnaffectedByLaterFileReplacement() throws {
        try withPortableStore { store, root in
            let file = root.appendingPathComponent("backup.jwe")
            let vector = try publicArchiveVector()
            try Data(vector.compact.utf8).write(to: file)
            #expect(throws: TeamArchiveError.authenticationFailed) {
                try TeamArchiveImport.prepare(fileURL: file, recoveryKey: SymmetricKey(size: .bits256), expectedAccountId: "alice")
            }
            #expect(throws: TeamArchiveError.invalidAccount) {
                try TeamArchiveImport.prepare(fileURL: file, recoveryKey: publicTestKey(), expectedAccountId: "bob")
            }
            let prepared = try TeamArchiveImport.prepare(fileURL: file, recoveryKey: publicTestKey(), expectedAccountId: "alice")
            #expect(prepared.accountId == "alice" && prepared.exportedAt == 2000)
            #expect(prepared.recordCount == 1 && prepared.teamCount == 1)
            #expect(String(describing: prepared) == "TeamArchiveImport(<redacted>)")
            #expect(String(reflecting: prepared) == "TeamArchiveImport(<redacted>)")
            #expect(try store.previewArchiveRestore(prepared).newRecords == 1)
            try Data("replaced file must not change confirmation".utf8).write(to: file, options: .atomic)
            #expect(try store.restorePreparedArchive(prepared).inserted == 1)
            #expect(try store.pendingReceipts().isEmpty)
        }
    }

    @Test func previewCountsNewIdenticalAndConflictingWithoutChangingStore() throws {
        try withPortableStore { store, _ in
            let baseline = try TeamPortableArchive(accountId: "alice", exportedAt: 2000,
                notes: [portableNote(delivery: "same"), portableNote(delivery: "conflict")])
            _ = try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(baseline, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let archive = try TeamPortableArchive(accountId: "alice", exportedAt: 3000, notes: [
                portableNote(delivery: "same", savedAt: 9999), portableNote(delivery: "conflict", body: "changed"),
                portableNote(delivery: "new"), portableNote(delivery: "new", team: "second-team")])
            let candidate = try TeamArchiveImport.prepare(TeamArchiveJWE.encrypt(archive, recoveryKey: publicTestKey()),
                                                          recoveryKey: publicTestKey(), expectedAccountId: "alice")
            let before = try store.exportEncryptedAccountArchive(exportedAt: 4000, recoveryKey: publicTestKey())
            let preview = try store.previewArchiveRestore(candidate)
            #expect(candidate.recordCount == 4 && candidate.teamCount == 2)
            #expect(preview.newRecords == 2 && preview.unchangedRecords == 1 && preview.conflictingRecords == 1)
            #expect(!preview.canRestore)
            let after = try store.exportEncryptedAccountArchive(exportedAt: 4000, recoveryKey: publicTestKey())
            #expect(try TeamArchiveJWE.decrypt(before, recoveryKey: publicTestKey(), expectedAccountId: "alice") ==
                    TeamArchiveJWE.decrypt(after, recoveryKey: publicTestKey(), expectedAccountId: "alice"))
            #expect(try store.pendingReceipts().isEmpty)
        }
    }

    @Test func stalePreviewRevalidatesConflictsAcrossConnectionsAndRollsBack() throws {
        try withPortableStore { store, root in
            let archive = try TeamPortableArchive(accountId: "alice", exportedAt: 2000,
                notes: [portableNote(delivery: "new-first"), portableNote(delivery: "raced")])
            let candidate = try TeamArchiveImport.prepare(TeamArchiveJWE.encrypt(archive, recoveryKey: publicTestKey()),
                                                          recoveryKey: publicTestKey(), expectedAccountId: "alice")
            #expect(try store.previewArchiveRestore(candidate).canRestore)
            let other = try TeamInboxStore(applicationSupportDirectory: root, target: store.target, teamId: "team")
            let raced = try TeamPortableArchive(accountId: "alice", exportedAt: 2100,
                notes: [portableNote(delivery: "raced", body: "different")])
            _ = try other.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(raced, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            #expect(throws: TeamDeliveryError.immutableConflict) { try store.restorePreparedArchive(candidate) }
            #expect(try store.archived(deliveryId: "new-first") == nil)
            #expect(try store.archived(deliveryId: "raced")?.envelope.body == "different")
            #expect(try store.pendingReceipts().isEmpty)
        }
    }

    @Test func preparedImportRejectsForeignStoreAndHandlesEmptyAndIdempotentRestore() throws {
        try withPortableStore { store, _ in
            let foreign = try TeamPortableArchive(accountId: "bob", exportedAt: 0, notes: [])
            let candidate = try TeamArchiveImport.prepare(TeamArchiveJWE.encrypt(foreign, recoveryKey: publicTestKey()),
                                                          recoveryKey: publicTestKey(), expectedAccountId: "bob")
            #expect(throws: TeamArchiveError.invalidAccount) { try store.previewArchiveRestore(candidate) }
            #expect(throws: TeamArchiveError.invalidAccount) { try store.restorePreparedArchive(candidate) }
            let empty = try TeamPortableArchive(accountId: "alice", exportedAt: 0, notes: [])
            let emptyCandidate = try TeamArchiveImport.prepare(TeamArchiveJWE.encrypt(empty, recoveryKey: publicTestKey()),
                                                               recoveryKey: publicTestKey(), expectedAccountId: "alice")
            #expect(emptyCandidate.recordCount == 0 && emptyCandidate.teamCount == 0)
            #expect(try store.previewArchiveRestore(emptyCandidate).canRestore)
            #expect(try store.restorePreparedArchive(emptyCandidate).inserted == 0)
            let prepared = try TeamArchiveImport.prepare(publicArchiveVector().compact, recoveryKey: publicTestKey(), expectedAccountId: "alice")
            #expect(try store.previewArchiveRestore(prepared).newRecords == 1)
            _ = try store.restorePreparedArchive(prepared)
            #expect(try store.previewArchiveRestore(prepared).unchangedRecords == 1)
            #expect(try store.restorePreparedArchive(prepared).unchanged == 1)
        }
    }

    @Test func sharedIndependentNodeVectorDecryptsAndMatchesCryptoKitEncryption() throws {
        for name in ["team-archive-v1-vector", "team-archive-v1-ios-vector", "team-archive-v1-android-vector"] {
        let vector = try publicArchiveVector(name: name)
        #expect(vector.profile == TeamPortableArchive.marker)
        #expect(vector.protectedHeader == TeamArchiveJWE.protectedHeader)
        let key = SymmetricKey(data: publicHexBytes(vector.keyHex))
        let archive = try TeamArchiveJWE.decrypt(vector.compact, recoveryKey: key, expectedAccountId: "alice")
        #expect(archive.notes.count == 1)
        #expect(archive.notes[0].envelope.body == "Team note: مرحباً — 你好 🌍")
        #expect(archive.notes[0].envelope.recipient.enrollmentId == "alice-enrollment")
        #expect(archive.notes[0].savedAt == 1500)
        #expect(try archive.encodePlaintext() == Data(vector.plaintext.utf8))
        let parts = vector.compact.split(separator: ".", omittingEmptySubsequences: false)
        let nonceBytes = try TeamArchiveJWE.decodeBase64URL(parts[2], maximumBytes: 12)
        if let hex = vector.nonceHex { #expect(nonceBytes == publicHexBytes(hex)) }
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let box = try AES.GCM.seal(Data(vector.plaintext.utf8), using: key, nonce: nonce,
                                   authenticating: Data(TeamArchiveJWE.encodedHeader.utf8))
        let compact = [TeamArchiveJWE.encodedHeader, "", TeamArchiveJWE.base64URL(nonceBytes),
                       TeamArchiveJWE.base64URL(box.ciphertext), TeamArchiveJWE.base64URL(box.tag)].joined(separator: ".")
        #expect(compact == vector.compact)
        try withPortableStore { store, root in
            #expect(try store.restoreEncryptedAccountArchive(vector.compact, recoveryKey: key).inserted == 1)
            #expect(try store.pendingReceipts().isEmpty)
            let target = try DeliveryTarget(userId: "alice", deviceId: "current-phone", enrollmentId: "current-enrollment")
            let reopened = try TeamInboxStore(applicationSupportDirectory: root, target: target, teamId: "team-1")
            #expect(try reopened.archived(deliveryId: "delivery-1") == archive.notes[0])
            #expect(try reopened.pendingReceipts().isEmpty)
            #expect(try reopened.restoreEncryptedAccountArchive(vector.compact, recoveryKey: key).unchanged == 1)
            let exported = try reopened.exportEncryptedAccountArchive(exportedAt: 7000, recoveryKey: key)
            #expect(try TeamArchiveJWE.decrypt(exported, recoveryKey: key, expectedAccountId: "alice").notes == archive.notes)
        }
        }
    }

    @Test func freshNoncesEmptyArchiveAndUTF8RoundTrip() throws {
        let key = TeamArchiveJWE.generateRecoveryKey()
        #expect(key.bitCount == 256)
        let archive = try TeamPortableArchive(accountId: "alice", exportedAt: Int64.max,
            notes: [portableNote(body: "a\u{0}b / e\u{301} é مرحبا\n🌍")])
        var nonces: Set<String> = []
        for _ in 0..<16 {
            let compact = try TeamArchiveJWE.encrypt(archive, recoveryKey: key)
            let parts = compact.split(separator: ".", omittingEmptySubsequences: false)
            #expect(parts.count == 5)
            #expect(parts[1].isEmpty)
            nonces.insert(String(parts[2]))
            let decoded = try TeamArchiveJWE.decrypt(compact, recoveryKey: key, expectedAccountId: "alice")
            #expect(decoded == archive)
            #expect(Data(decoded.notes[0].envelope.body.utf8) == Data(archive.notes[0].envelope.body.utf8))
        }
        #expect(nonces.count == 16)
        let empty = try TeamPortableArchive(accountId: "alice", exportedAt: 0, notes: [])
        #expect(try TeamArchiveJWE.decrypt(TeamArchiveJWE.encrypt(empty, recoveryKey: key),
                                         recoveryKey: key, expectedAccountId: "alice") == empty)
    }

    @Test func authenticationRejectsWrongKeyAndTamperedNonceCiphertextTag() throws {
        let vector = try publicArchiveVector()
        #expect(throws: TeamArchiveError.authenticationFailed) {
            try TeamArchiveJWE.decrypt(vector.compact, recoveryKey: SymmetricKey(data: Data(repeating: 99, count: 32)), expectedAccountId: "alice")
        }
        for index in [2, 3, 4] {
            var pieces = vector.compact.components(separatedBy: ".")
            pieces[index] = (pieces[index].first == "A" ? "B" : "A") + pieces[index].dropFirst()
            #expect(throws: TeamArchiveError.authenticationFailed) {
                try TeamArchiveJWE.decrypt(pieces.joined(separator: "."), recoveryKey: publicTestKey(), expectedAccountId: "alice")
            }
        }
        #expect(throws: TeamArchiveError.invalidKey) {
            try TeamArchiveJWE.decrypt(vector.compact, recoveryKey: SymmetricKey(size: .bits128), expectedAccountId: "alice")
        }
        #expect(throws: TeamArchiveError.invalidAccount) {
            try TeamArchiveJWE.decrypt(vector.compact, recoveryKey: publicTestKey(), expectedAccountId: "bob")
        }
    }

    @Test func strictJWEHeaderSegmentsBase64AndLengths() throws {
        let vector = try publicArchiveVector()
        let pieces = vector.compact.components(separatedBy: ".")
        var bad: [String] = [vector.compact + ".extra", vector.compact + "\n", String(vector.compact.dropLast()), " "+vector.compact]
        for header in [#"{"enc":"A256GCM","alg":"dir","typ":"pinbook-team-archive-v1"}"#,
                       #"{"alg":"dir","enc":"A128GCM","typ":"pinbook-team-archive-v1"}"#,
                       #"{"alg":"dir","enc":"A256GCM","typ":"pinbook-team-archive-v1","zip":"DEF"}"#] {
            var changed = pieces
            changed[0] = TeamArchiveJWE.base64URL(Data(header.utf8))
            bad.append(changed.joined(separator: "."))
        }
        for (index, value) in [(1, "AA"), (2, "AA"), (2, pieces[2] + "="), (3, "!"),
                               (4, "AA"), (4, pieces[4] + "="), (4, String(pieces[4].dropLast()) + "h")] {
            var changed = pieces
            changed[index] = value
            bad.append(changed.joined(separator: "."))
        }
        for compact in bad {
            #expect(throws: (any Error).self) { try TeamArchiveJWE.decrypt(compact, recoveryKey: publicTestKey(), expectedAccountId: "alice") }
        }
    }

    @Test func strictPlaintextTupleTypesUTF8BOMAndTrailingSyntax() throws {
        let vector = try publicArchiveVector()
        let valid = vector.plaintext
        let malformed = [valid + "[]", valid + " true", valid.replacingOccurrences(of: "\"2000\"", with: "2000"),
            valid.replacingOccurrences(of: "\"2000\"", with: "null"), valid.replacingOccurrences(of: "\"2000\"", with: "{}"),
            valid.replacingOccurrences(of: "\"2000\"", with: "true"),
            valid.replacingOccurrences(of: "\"alice\"", with: "\"\\ud800\""),
            valid.replacingOccurrences(of: "\"alice\"", with: "\"\\udc00\""),
            "[\"pinbook-team-archive-v1\",\"alice\",\"0\",[],\"extra\"]",
            "[\"pinbook-team-archive-v1\",\"alice\",\"0\",[[]]]",
            "{\"accountId\":\"alice\"}", "//comment\n" + valid,
            String(valid.dropLast()) + ",]"
        ]
        for text in malformed {
            #expect(throws: (any Error).self) { try TeamPortableArchive.decodePlaintext(Data(text.utf8), expectedAccountId: "alice") }
        }
        for data in [Data([0xFF]), Data([0xEF, 0xBB, 0xBF]) + Data(valid.utf8)] {
            #expect(throws: TeamArchiveError.invalidFormat) { try TeamPortableArchive.decodePlaintext(data, expectedAccountId: "alice") }
        }
        #expect(try TeamPortableArchive.decodePlaintext(Data((" \n" + valid + "\t ").utf8), expectedAccountId: "alice").notes.count == 1)
    }

    @Test func timestampsRequireCanonicalNonnegativeInt64Strings() throws {
        let valid = try publicArchiveVector().plaintext
        for value in ["", "+1", "-1", "00", "01", "1.0", "1e3", "١", "9223372036854775808", " 1"] {
            let text = valid.replacingOccurrences(of: "\"2000\"", with: "\"\(value)\"")
            #expect(throws: TeamArchiveError.invalidTimestamp) { try TeamPortableArchive.decodePlaintext(Data(text.utf8), expectedAccountId: "alice") }
        }
        #expect(try TeamPortableArchive.timestamp("9223372036854775807") == Int64.max)
        #expect(try TeamPortableArchive.timestamp("0") == 0)
        let invalidExpiry = valid.replacingOccurrences(of: "2592001000", with: "2592001001")
        #expect(throws: (any Error).self) { try TeamPortableArchive.decodePlaintext(Data(invalidExpiry.utf8), expectedAccountId: "alice") }
    }

    @Test func duplicatesRejectAndRecordCountIsBounded() throws {
        let note = try portableNote()
        #expect(throws: TeamArchiveError.duplicateDelivery) {
            try TeamPortableArchive(accountId: "alice", exportedAt: 2000, notes: [note, note])
        }
        var root = try #require(JSONSerialization.jsonObject(with: Data(publicArchiveVector().plaintext.utf8)) as? [Any])
        let row = try #require((root[3] as? [Any])?.first)
        root[3] = Array(repeating: row, count: 10_001)
        let data = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: TeamArchiveError.tooLarge) { try TeamPortableArchive.decodePlaintext(data, expectedAccountId: "alice") }
        let notes = try (0..<10_000).map { try portableNote(delivery: "d-\($0)") }
        let maximum = try TeamPortableArchive(accountId: "alice", exportedAt: 2000, notes: notes)
        #expect(try TeamPortableArchive.decodePlaintext(maximum.encodePlaintext(), expectedAccountId: "alice").notes.count == 10_000)
    }

    @Test func independentPlaintextCiphertextAndCompactBounds() throws {
        let oversized = Data(repeating: 32, count: TeamPortableArchive.maximumPlaintextBytes + 1)
        #expect(throws: TeamArchiveError.tooLarge) { try TeamPortableArchive.decodePlaintext(oversized, expectedAccountId: "alice") }
        var pieces = try publicArchiveVector().compact.components(separatedBy: ".")
        pieces[3] = TeamArchiveJWE.base64URL(oversized)
        let compact = pieces.joined(separator: ".")
        #expect(compact.utf8.count < TeamArchiveJWE.maximumCompactBytes)
        #expect(throws: (any Error).self) { try TeamArchiveJWE.decrypt(compact, recoveryKey: publicTestKey(), expectedAccountId: "alice") }
        #expect(throws: TeamArchiveError.tooLarge) {
            try TeamArchiveJWE.decrypt(String(repeating: ".", count: TeamArchiveJWE.maximumCompactBytes + 1), recoveryKey: publicTestKey(), expectedAccountId: "alice")
        }
        let body = String(repeating: "a", count: 32768)
        let notes = try (0..<520).map { try portableNote(delivery: "large-\($0)", body: body) }
        #expect(throws: TeamArchiveError.tooLarge) { try TeamPortableArchive(accountId: "alice", exportedAt: 0, notes: notes) }
    }

    @Test func restorePreservesHistoricalEnrollmentNeverCreatesACKsAndReopens() throws {
        try withPortableStore { store, root in
            let vector = try publicArchiveVector()
            #expect(try store.restoreEncryptedAccountArchive(vector.compact, recoveryKey: publicTestKey()).inserted == 1)
            #expect(try store.pendingReceipts().isEmpty)
            let oldTeam = try TeamInboxStore(applicationSupportDirectory: root, target: store.target, teamId: "team-1")
            let saved = try #require(try oldTeam.archived(deliveryId: "delivery-1"))
            #expect(saved.envelope.recipient.enrollmentId == "alice-enrollment")
            #expect(saved.savedAt == 1500)
            #expect(try oldTeam.pendingReceipts().isEmpty)
            #expect(try oldTeam.restoreEncryptedAccountArchive(vector.compact, recoveryKey: publicTestKey()).unchanged == 1)
            #expect(throws: TeamDeliveryError.invalidScope) { try oldTeam.receive(saved.envelope, savedAt: 3000) }
            let exported = try store.exportEncryptedAccountArchive(exportedAt: 4000, recoveryKey: publicTestKey())
            let decoded = try TeamArchiveJWE.decrypt(exported, recoveryKey: publicTestKey(), expectedAccountId: "alice")
            #expect(decoded.notes == [saved])
            #expect(decoded.exportedAt == 4000)
            #if SWIFT_PACKAGE
            if let output = ProcessInfo.processInfo.environment["PINBOOK_TEAM_PUBLIC_VECTOR_OUTPUT"] {
                // Explicit developer conformance export: known PUBLIC fixture only, no user data/keys.
                guard output == "/private/tmp/pinbook-team-archive-ios-public-vector.json" else {
                    throw TeamArchiveError.invalidFormat
                }
                let parts = exported.split(separator: ".", omittingEmptySubsequences: false)
                let nonce = try TeamArchiveJWE.decodeBase64URL(parts[2], maximumBytes: 12)
                let fixture = [
                    "warning": "PUBLIC TEST KEY ONLY; CryptoKit-generated nonce; never use for real archives",
                    "profile": TeamPortableArchive.marker, "keyHex": vector.keyHex,
                    "nonceHex": nonce.map { String(format: "%02x", $0) }.joined(),
                    "protectedHeader": TeamArchiveJWE.protectedHeader,
                    "plaintext": String(decoding: try decoded.encodePlaintext(), as: UTF8.self), "compact": exported
                ]
                try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    .write(to: URL(fileURLWithPath: output), options: .atomic)
            }
            #endif
        }
    }

    @Test func immutableConflictRollsBackEntireImportAndKeepsExistingSavedAt() throws {
        try withPortableStore { store, _ in
            let original = try portableNote(delivery: "existing", savedAt: 1500)
            let first = try TeamPortableArchive(accountId: "alice", exportedAt: 2000, notes: [original])
            _ = try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(first, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            let conflict = try TeamPortableArchive(accountId: "alice", exportedAt: 2000,
                notes: [portableNote(delivery: "new-first"), portableNote(delivery: "existing", body: "changed")])
            #expect(throws: TeamDeliveryError.immutableConflict) {
                try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(conflict, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            }
            #expect(try store.archived(deliveryId: "new-first") == nil)
            #expect(try store.archived(deliveryId: "existing") == original)
            let duplicate = try TeamPortableArchive(accountId: "alice", exportedAt: 9000,
                notes: [portableNote(delivery: "existing", savedAt: 8000)])
            #expect(try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(duplicate, recoveryKey: publicTestKey()), recoveryKey: publicTestKey()).unchanged == 1)
            #expect(try store.archived(deliveryId: "existing")?.savedAt == 1500)
            #expect(try store.pendingReceipts().isEmpty)
        }
    }

    @Test func authenticatedInvalidArchiveAndWrongKeyLeaveStoreUntouched() throws {
        try withPortableStore { store, _ in
            let vector = try publicArchiveVector()
            let tamperedPlaintext = vector.plaintext.replacingOccurrences(of: "2592001000", with: "2592001001")
            let compact = try sealedPublicTestPayload(Data(tamperedPlaintext.utf8))
            #expect(throws: (any Error).self) { try store.restoreEncryptedAccountArchive(compact, recoveryKey: publicTestKey()) }
            #expect(throws: TeamArchiveError.authenticationFailed) {
                try store.restoreEncryptedAccountArchive(vector.compact, recoveryKey: SymmetricKey(data: Data(repeating: 1, count: 32)))
            }
            let exported = try store.exportEncryptedAccountArchive(exportedAt: 2000, recoveryKey: publicTestKey())
            #expect(try TeamArchiveJWE.decrypt(exported, recoveryKey: publicTestKey(), expectedAccountId: "alice").notes.isEmpty)
            #expect(try store.pendingReceipts().isEmpty)
        }
    }

    @Test func restoreLeavesLiveReceiptsAndPersonalFilesUnchanged() throws {
        try withPortableStore { store, root in
            let live = TeamNoteEnvelope(protocolVersion: 1, teamId: "team", deliveryId: "live", noteId: "live-note",
                authorUserId: "sender", recipient: store.target, body: "live", bodySha256: TeamDeliveryRules.textSHA256("live"),
                acceptedAt: 1000, expiresAt: 2_592_001_000, attachmentCount: 0)
            try store.receive(live, savedAt: 1500)
            let before = try store.pendingReceipts()
            let personal = root.appendingPathComponent("personal-backup-fixture")
            let originalBytes = Data("personal records remain unchanged".utf8)
            try originalBytes.write(to: personal)
            _ = try store.restoreEncryptedAccountArchive(publicArchiveVector().compact, recoveryKey: publicTestKey())
            #expect(try store.pendingReceipts() == before)
            #expect(try store.archived(deliveryId: "live")?.envelope == live)
            #expect(try Data(contentsOf: personal) == originalBytes)
            let foreign = try TeamPortableArchive(accountId: "bob", exportedAt: 2000, notes: [])
            #expect(throws: TeamArchiveError.invalidAccount) {
                try store.restoreEncryptedAccountArchive(TeamArchiveJWE.encrypt(foreign, recoveryKey: publicTestKey()), recoveryKey: publicTestKey())
            }
            #expect(try store.pendingReceipts() == before)
        }
    }
}
