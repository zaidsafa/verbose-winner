import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private actor BackupTransportStub: BackupTransport {
    let first: RemoteBackupPage
    let following: [String: RemoteBackupPage]
    let downloads: [String: Data]
    let appendResult: RemoteBackupSnapshot?
    private(set) var requestedMaximum: Int?

    init(first: RemoteBackupPage, following: [String: RemoteBackupPage] = [:],
         downloads: [String: Data] = [:], appendResult: RemoteBackupSnapshot? = nil) {
        self.first = first
        self.following = following
        self.downloads = downloads
        self.appendResult = appendResult
    }

    func list(after cursor: String?) throws -> RemoteBackupPage {
        guard let cursor else { return first }
        return try #require(following[cursor])
    }

    func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) throws -> Data {
        requestedMaximum = maximumBytes
        return try #require(downloads[snapshot.objectID])
    }

    func append(_ backup: Data, operationID: String, createdAt: Int64,
                sha256: String) throws -> RemoteBackupSnapshot {
        try #require(appendResult)
    }
}

private func backupDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func snapshot(_ suffix: String, data: Data, createdAt: Int64) throws
    -> RemoteBackupSnapshot {
    try RemoteBackupSnapshot(objectID: "object_" + suffix,
        operationID: "operation_" + suffix, createdAt: createdAt,
        byteCount: data.count, sha256: backupDigest(data))
}

struct BackupTransportTests {
    @Test func inventoryFollowsEveryPageAndSortsDeterministically() async throws {
        let firstObject = try snapshot("one", data: Data("one".utf8), createdAt: 20)
        let secondObject = try snapshot("two", data: Data("two".utf8), createdAt: 10)
        let transport = BackupTransportStub(
            first: try RemoteBackupPage(snapshots: [firstObject], nextCursor: "page_2"),
            following: ["page_2": try RemoteBackupPage(snapshots: [secondObject], nextCursor: nil)])
        let result = try await BackupTransportGuard.inventory(using: transport)
        #expect(result.map(\.objectID) == [secondObject.objectID, firstObject.objectID])
    }

    @Test func inventoryRejectsCursorLoopsDuplicatesAndCaps() async throws {
        let data = Data("backup".utf8)
        let item = try snapshot("one", data: data, createdAt: 1)
        let loop = BackupTransportStub(
            first: try RemoteBackupPage(snapshots: [], nextCursor: "again"),
            following: ["again": try RemoteBackupPage(snapshots: [], nextCursor: "again")])
        await #expect(throws: BackupTransportError.repeatedCursor) {
            try await BackupTransportGuard.inventory(using: loop)
        }
        let duplicate = BackupTransportStub(
            first: try RemoteBackupPage(snapshots: [item], nextCursor: "next"),
            following: ["next": try RemoteBackupPage(snapshots: [item], nextCursor: nil)])
        await #expect(throws: BackupTransportError.duplicateSnapshot) {
            try await BackupTransportGuard.inventory(using: duplicate)
        }
        await #expect(throws: BackupTransportError.inventoryLimit) {
            try await BackupTransportGuard.inventory(using: duplicate, maximumPages: 1)
        }
    }

    @Test func downloadsAreExactBoundedAndHashVerified() async throws {
        let data = Data("private-backup".utf8)
        let item = try snapshot("download", data: data, createdAt: 2)
        let good = BackupTransportStub(first: try RemoteBackupPage(snapshots: [], nextCursor: nil),
                                       downloads: [item.objectID: data])
        #expect(try await BackupTransportGuard.downloadVerified(item, using: good) == data)
        #expect(await good.requestedMaximum == data.count)
        let bad = BackupTransportStub(first: try RemoteBackupPage(snapshots: [], nextCursor: nil),
                                      downloads: [item.objectID: Data("changed".utf8)])
        await #expect(throws: BackupTransportError.integrityMismatch) {
            try await BackupTransportGuard.downloadVerified(item, using: bad)
        }
    }

    @Test func appendReceiptMustMatchExactPersistedOperationAndBytes() async throws {
        let data = Data("backup".utf8)
        let receipt = try snapshot("append", data: data, createdAt: 3)
        let good = BackupTransportStub(first: try RemoteBackupPage(snapshots: [], nextCursor: nil),
                                       appendResult: receipt)
        #expect(try await BackupTransportGuard.appendVerified(data,
            operationID: receipt.operationID, createdAt: receipt.createdAt,
            using: good) == receipt)
        let wrong = try RemoteBackupSnapshot(objectID: "object_wrong",
            operationID: "operation_wrong", createdAt: 3, byteCount: data.count,
            sha256: backupDigest(data))
        let bad = BackupTransportStub(first: try RemoteBackupPage(snapshots: [], nextCursor: nil),
                                      appendResult: wrong)
        await #expect(throws: BackupTransportError.appendMismatch) {
            try await BackupTransportGuard.appendVerified(data,
                operationID: receipt.operationID, createdAt: receipt.createdAt,
                using: bad)
        }
        #expect(Mirror(reflecting: receipt).children.isEmpty)
    }

    @Test func invalidRemoteMetadataFailsBeforeProviderUse() {
        #expect(throws: BackupTransportError.invalidMetadata) {
            try RemoteBackupSnapshot(objectID: "bad/id", operationID: "operation",
                createdAt: 0, byteCount: 1, sha256: String(repeating: "a", count: 64))
        }
        #expect(throws: BackupTransportError.invalidMetadata) {
            try RemoteBackupPage(snapshots: [], nextCursor: "contains space")
        }
    }
}
