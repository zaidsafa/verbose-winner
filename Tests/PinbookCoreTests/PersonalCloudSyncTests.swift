import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor PersonalCloudSyncTransportStub: BackupTransport {
    let snapshots: [RemoteBackupSnapshot]
    let payloads: [String: Data]
    private(set) var downloads = 0

    init(payloads: [(String, Int64, Data)]) throws {
        var snapshots: [RemoteBackupSnapshot] = []
        var dataByID: [String: Data] = [:]
        for (id, createdAt, data) in payloads {
            let digest = SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
            snapshots.append(try RemoteBackupSnapshot(
                objectID: id, operationID: id, createdAt: createdAt,
                byteCount: data.count, sha256: digest
            ))
            dataByID[id] = data
        }
        self.snapshots = snapshots
        self.payloads = dataByID
    }

    func reserveOperationID() async throws -> String { "reserved" }

    func list(after cursor: String?) async throws -> RemoteBackupPage {
        try RemoteBackupPage(snapshots: cursor == nil ? snapshots : [], nextCursor: nil)
    }

    func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) async throws -> Data {
        downloads += 1
        return payloads[snapshot.objectID] ?? Data()
    }

    func append(_ backup: Data, operationID: String, createdAt: Int64,
                sha256: String) async throws -> RemoteBackupSnapshot {
        try RemoteBackupSnapshot(
            objectID: operationID, operationID: operationID,
            createdAt: createdAt, byteCount: backup.count, sha256: sha256
        )
    }
}

@Suite(.serialized)
struct PersonalCloudSyncTests {
    private func encoded(_ backup: PinbookBackup) throws -> Data {
        try PersonalCloudSyncEngine.encode(backup)
    }

    @Test func mergesEveryVerifiedImmutableSnapshotAndLocalWinsEqualTie() async throws {
        let localBook = BookRecord(
            id: "local", name: "Local", createdAt: 10, updatedAt: 20,
            isArchived: false
        )
        let tiedLocal = ExpenseRecord(
            id: "tie", amountMinor: 100, currency: "USD", purpose: "local",
            counterparty: "Local", bookId: "local", occurredAt: 10,
            createdAt: 10, updatedAt: 30, isNoted: false
        )
        let remoteBook = BookRecord(
            id: "remote", name: "Remote", createdAt: 11, updatedAt: 21,
            isArchived: false
        )
        let tiedRemote = ExpenseRecord(
            id: "tie", amountMinor: 200, currency: "USD", purpose: "remote",
            counterparty: "Remote", bookId: "remote", occurredAt: 10,
            createdAt: 10, updatedAt: 30, isNoted: false
        )
        let remoteExpense = ExpenseRecord(
            id: "added", amountMinor: 300, currency: "EUR", purpose: "expense",
            counterparty: "A", bookId: "remote", privateNote: "shared note",
            occurredAt: 12, createdAt: 12, updatedAt: 40,
            isNoted: true, notedAt: 40
        )
        let local = try PinbookBackup(expenses: [tiedLocal], books: [localBook])
        let remote = try PinbookBackup(
            expenses: [tiedRemote, remoteExpense], books: [remoteBook]
        )
        let bytes = try encoded(remote)
        let transport = try PersonalCloudSyncTransportStub(
            payloads: [("snapshotA", 100, bytes), ("snapshotB", 101, bytes)]
        )

        let result = try await PersonalCloudSyncEngine.reconcile(
            local: local, using: transport
        )
        #expect(result.remoteSnapshotCount == 2)
        #expect(result.downloadedSnapshotCount == 1)
        #expect(await transport.downloads == 1)
        #expect(result.merged.expenses.first(where: { $0.id == "tie" }) == tiedLocal)
        #expect(result.merged.expenses.contains(remoteExpense))
        #expect(result.merged.books.contains(remoteBook))
        #expect(result.alreadyContains(bytes))
    }

    @Test func corruptedRemoteBytesFailBeforeDecodeOrMerge() async throws {
        let valid = try encoded(PinbookBackup())
        let transport = try PersonalCloudSyncTransportStub(
            payloads: [("snapshotC", 100, valid)]
        )
        let snapshot = try #require(transport.snapshots.first)
        let corrupt = PersonalCloudCorruptTransport(
            snapshot: snapshot, bytes: Data("corrupt".utf8)
        )
        await #expect(throws: BackupTransportError.integrityMismatch) {
            try await PersonalCloudSyncEngine.reconcile(
                local: PinbookBackup(), using: corrupt
            )
        }
    }
}

private struct PersonalCloudCorruptTransport: BackupTransport {
    let snapshot: RemoteBackupSnapshot
    let bytes: Data

    func reserveOperationID() async throws -> String { "reserved" }
    func list(after cursor: String?) async throws -> RemoteBackupPage {
        try RemoteBackupPage(snapshots: cursor == nil ? [snapshot] : [], nextCursor: nil)
    }
    func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) async throws -> Data {
        bytes
    }
    func append(_ backup: Data, operationID: String, createdAt: Int64,
                sha256: String) async throws -> RemoteBackupSnapshot {
        snapshot
    }
}
