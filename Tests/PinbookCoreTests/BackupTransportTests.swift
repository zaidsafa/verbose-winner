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

private final class BackupUploadStateStub: BackupUploadStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    private(set) var replacements = 0

    init(_ value: Data? = nil) { self.value = value }

    func load() -> Data? { lock.withLock { value } }

    func replace(expected: Data?, next: Data?) throws {
        try lock.withLock {
            guard value == expected else { throw PersonalCloudUploadError.staleOperation }
            value = next
            replacements += 1
        }
    }
}

private enum BackupUploadFixtureError: Error { case unavailable }

private actor BackupUploadTransport: BackupTransport {
    enum Mode { case success, failure, blocked }
    let mode: Mode
    private(set) var appendCalls = 0
    private(set) var appendedOperationID: String?
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ mode: Mode) { self.mode = mode }

    func list(after cursor: String?) throws -> RemoteBackupPage {
        try RemoteBackupPage(snapshots: [], nextCursor: nil)
    }

    func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) throws -> Data { Data() }

    func append(_ backup: Data, operationID: String, createdAt: Int64,
                sha256: String) async throws -> RemoteBackupSnapshot {
        appendCalls += 1
        appendedOperationID = operationID
        if mode == .failure { throw BackupUploadFixtureError.unavailable }
        if mode == .blocked {
            await withCheckedContinuation { continuation = $0 }
        }
        return try RemoteBackupSnapshot(
            objectID: "file_" + operationID,
            operationID: operationID,
            createdAt: createdAt,
            byteCount: backup.count,
            sha256: sha256
        )
    }

    func isBlocked() -> Bool { appendCalls == 1 && continuation != nil }

    func release() {
        continuation?.resume()
        continuation = nil
    }
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

    @Test func uploadReservationPersistsBeforeAppendAndClearsOnlyAfterExactReceipt() async throws {
        let state = BackupUploadStateStub()
        let owner = PersonalCloudUploadOwner(
            state: state,
            makeOperationID: { "google_file_1" }
        )
        let backup = Data("backup-v8".utf8)
        let ticket = try owner.reserve(backup, createdAt: 10)

        #expect(state.replacements == 1)
        #expect(try owner.pendingUpload() == ticket)
        #expect(String(describing: ticket) == "PendingBackupUpload(<redacted>)")
        #expect(Mirror(reflecting: ticket).children.isEmpty)

        let transport = BackupUploadTransport(.success)
        let receipt = try await owner.append(backup, ticket: ticket, using: transport)
        #expect(receipt.operationID == ticket.operationID)
        #expect(await transport.appendedOperationID == "google_file_1")
        #expect(try owner.pendingUpload() == nil)
        #expect(state.replacements == 2)
    }

    @Test func ambiguousFailureRetainsAndReusesOnlyTheExactUploadIdentity() async throws {
        let state = BackupUploadStateStub()
        let owner = PersonalCloudUploadOwner(
            state: state,
            makeOperationID: { "google_file_2" }
        )
        let backup = Data("same-backup-v8".utf8)
        let ticket = try owner.reserve(backup, createdAt: 20)
        let failed = BackupUploadTransport(.failure)

        await #expect(throws: BackupUploadFixtureError.unavailable) {
            try await owner.append(backup, ticket: ticket, using: failed)
        }
        #expect(try owner.pendingUpload() == ticket)
        #expect(try owner.reserve(backup, createdAt: 20) == ticket)
        #expect(throws: PersonalCloudUploadError.unresolvedUpload) {
            try owner.reserve(Data("newer-backup".utf8), createdAt: 21)
        }

        let reopened = PersonalCloudUploadOwner(
            state: state,
            makeOperationID: { "must_not_be_used" }
        )
        #expect(try reopened.reserve(backup, createdAt: 20) == ticket)
        let success = BackupUploadTransport(.success)
        _ = try await reopened.append(backup, ticket: ticket, using: success)
        #expect(await success.appendedOperationID == "google_file_2")
        #expect(try reopened.pendingUpload() == nil)
    }

    @Test func uploadOwnerRejectsChangedBytesAndConcurrentDispatch() async throws {
        let state = BackupUploadStateStub()
        let owner = PersonalCloudUploadOwner(
            state: state,
            makeOperationID: { "google_file_3" }
        )
        let backup = Data("backup-v8".utf8)
        let ticket = try owner.reserve(backup, createdAt: 30)

        await #expect(throws: PersonalCloudUploadError.staleOperation) {
            try await owner.append(Data("changed".utf8), ticket: ticket,
                                   using: BackupUploadTransport(.success))
        }

        let blocked = BackupUploadTransport(.blocked)
        let first = Task { try await owner.append(backup, ticket: ticket, using: blocked) }
        for _ in 0..<1_000 {
            if await blocked.isBlocked() { break }
            await Task.yield()
        }
        #expect(await blocked.isBlocked())
        await #expect(throws: PersonalCloudUploadError.busy) {
            try await owner.append(backup, ticket: ticket, using: blocked)
        }
        await blocked.release()
        _ = try await first.value
        #expect(await blocked.appendCalls == 1)
        #expect(try owner.pendingUpload() == nil)
    }

    @Test func malformedPersistedUploadAuthorityFailsClosed() {
        let state = BackupUploadStateStub(Data("not-json".utf8))
        let owner = PersonalCloudUploadOwner(state: state)
        #expect(throws: PersonalCloudUploadError.invalidRecord) {
            try owner.pendingUpload()
        }
        #expect(throws: PersonalCloudUploadError.invalidRecord) {
            try owner.reserve(Data("backup".utf8), createdAt: 1)
        }
    }

    #if os(iOS)
    @Test func protectedKeychainReservationSurvivesReopenAndClearsAfterReceipt() async throws {
        let service = "pinbook.cloud-upload-test." + UUID().uuidString
        let backup = Data("keychain-backup-v8".utf8)
        let owner = try PersonalCloudUploadOwner(
            testService: service,
            makeOperationID: { "google_file_keychain" }
        )
        let ticket = try owner.reserve(backup, createdAt: 40)
        let reopened = try PersonalCloudUploadOwner(testService: service)
        #expect(try reopened.pendingUpload() == ticket)
        _ = try await reopened.append(
            backup,
            ticket: ticket,
            using: BackupUploadTransport(.success)
        )
        #expect(try reopened.pendingUpload() == nil)
    }
    #endif
}
