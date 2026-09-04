import CryptoKit
import Foundation
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

@Suite(.serialized)
struct TeamPortableArchiveTests {
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
