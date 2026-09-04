import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private struct DriveHTTPPlan: Sendable {
    let result: Result<TeamAuthResponse, Error>
    init(status: Int, body: Data) { result = .success(.init(status: status, body: body)) }
    init(error: Error) { result = .failure(error) }
}

private struct CapturedDriveRequest: @unchecked Sendable {
    let request: URLRequest
    let maximumResponseBytes: Int
    let kind: GoogleDriveResponseKind
}

private actor DriveHTTPStub: GoogleDriveHTTPExecuting {
    private var plans: [DriveHTTPPlan]
    private(set) var requests: [CapturedDriveRequest] = []
    init(_ plans: [DriveHTTPPlan]) { self.plans = plans }
    func execute(_ request: URLRequest, maximumResponseBytes: Int,
                 kind: GoogleDriveResponseKind) throws -> TeamAuthResponse {
        requests.append(.init(request: request, maximumResponseBytes: maximumResponseBytes,
                              kind: kind))
        guard !plans.isEmpty else { throw GoogleDriveBackupError.transport }
        return try plans.removeFirst().result.get()
    }
}

private func driveJSON(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func driveProperties(id: String, data: Data, createdAt: Int64) -> [String: Any] {
    ["id": id, "mimeType": "application/octet-stream", "appProperties": [
        "pinbookSchema": "backup-v8", "operationID": id,
        "createdAt": String(createdAt), "byteCount": String(data.count),
        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
    ]]
}

private func driveTransport(_ plans: [DriveHTTPPlan]) throws
    -> (GoogleDriveBackupTransport, DriveHTTPStub) {
    let stub = DriveHTTPStub(plans)
    let token = try GoogleDriveAccessToken(String(repeating: "t", count: 32))
    return (GoogleDriveBackupTransport(accessToken: { token }, executor: stub,
                                       boundary: { "pinbook_test_boundary_123456" }), stub)
}

@Suite(.serialized)
struct GoogleDriveBackupTransportTests {
    @Test func reservesDriveIDAndListsStrictAppDataMetadataWithCursor() async throws {
        let data = Data("backup-v8".utf8), id = "drive_file_123"
        let (transport, stub) = try driveTransport([
            .init(status: 200, body: try driveJSON([
                "ids": [id], "kind": "drive#generatedIds", "space": "appDataFolder"])),
            .init(status: 200, body: try driveJSON([
                "files": [driveProperties(id: id, data: data, createdAt: 12)],
                "nextPageToken": "next_page_1"])),
        ])
        #expect(try await transport.reserveOperationID() == id)
        let page = try await transport.list(after: "current_page_1")
        #expect(page.snapshots.count == 1 && page.snapshots[0].objectID == id)
        #expect(page.nextCursor == "next_page_1")

        let requests = await stub.requests
        #expect(requests.count == 2)
        #expect(requests[0].request.url?.path == "/drive/v3/files/generateIds")
        #expect(requests[1].request.url?.path == "/drive/v3/files")
        let items = URLComponents(url: try #require(requests[1].request.url),
                                  resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(.init(name: "spaces", value: "appDataFolder")))
        #expect(items.contains(.init(name: "pageToken", value: "current_page_1")))
        #expect(items.contains { $0.name == "q" && $0.value?.contains("appProperties") == true })
        for captured in requests {
            #expect(captured.request.url?.scheme == "https")
            #expect(captured.request.url?.host == "www.googleapis.com")
            #expect(captured.request.value(forHTTPHeaderField: "Authorization") ==
                    "Bearer " + String(repeating: "t", count: 32))
            #expect(captured.request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(captured.request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        }
        #expect(requests[1].maximumResponseBytes == 256 * 1024)
    }

    @Test func multipartCreateBindsReservedIDAndExactSnapshotAuthority() async throws {
        let data = Data("exact-backup-v8".utf8), id = "drive_file_456"
        let response = driveProperties(id: id, data: data, createdAt: 20)
        let (transport, stub) = try driveTransport([
            .init(status: 200, body: try driveJSON(response)),
        ])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let result = try await transport.append(data, operationID: id,
                                                createdAt: 20, sha256: digest)
        #expect(result.objectID == id && result.operationID == id)
        let request = try #require(await stub.requests.first?.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/upload/drive/v3/files")
        #expect(request.value(forHTTPHeaderField: "Content-Type") ==
                "multipart/related; boundary=pinbook_test_boundary_123456")
        let body = try #require(request.httpBody)
        #expect(request.value(forHTTPHeaderField: "Content-Length") == String(body.count))
        #expect(body.range(of: data) != nil)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("\"id\":\"drive_file_456\""))
        #expect(text.contains("\"parents\":[\"appDataFolder\"]"))
        #expect(text.contains("\"operationID\":\"drive_file_456\""))
        #expect(text.contains("\"sha256\":\"\(digest)\""))
    }

    @Test func conflictIsSuccessOnlyAfterExactMetadataAndMediaVerification() async throws {
        let data = Data("already-created-backup".utf8), id = "drive_file_retry"
        let fields = driveProperties(id: id, data: data, createdAt: 30)
        let (transport, stub) = try driveTransport([
            .init(status: 409, body: try driveJSON(["error": "conflict"])),
            .init(status: 200, body: try driveJSON(fields)),
            .init(status: 200, body: data),
        ])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(try await transport.append(data, operationID: id,
                                           createdAt: 30, sha256: digest).objectID == id)
        let requests = await stub.requests
        #expect(requests.map { $0.request.url?.path } == [
            "/upload/drive/v3/files", "/drive/v3/files/drive_file_retry",
            "/drive/v3/files/drive_file_retry"])
        #expect(URLComponents(url: try #require(requests[2].request.url),
                              resolvingAgainstBaseURL: false)?.queryItems == [
            .init(name: "alt", value: "media")])
        #expect(requests[2].maximumResponseBytes == data.count)
    }

    @Test func malformedMetadataWrongConflictBytesAndHTTPFailuresFailClosed() async throws {
        let data = Data("backup".utf8), id = "drive_file_bad"
        var wrong = driveProperties(id: id, data: data, createdAt: 40)
        var properties = wrong["appProperties"] as! [String: String]
        properties["byteCount"] = "0"; wrong["appProperties"] = properties
        let (badList, _) = try driveTransport([
            .init(status: 200, body: try driveJSON(["files": [wrong]])),
        ])
        await #expect(throws: GoogleDriveBackupError.invalidResponse) {
            try await badList.list(after: nil)
        }

        let exact = driveProperties(id: id, data: data, createdAt: 40)
        let (conflict, _) = try driveTransport([
            .init(status: 409, body: try driveJSON([:])),
            .init(status: 200, body: try driveJSON(exact)),
            .init(status: 200, body: Data("wrong".utf8)),
        ])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        await #expect(throws: BackupTransportError.integrityMismatch) {
            try await conflict.append(data, operationID: id, createdAt: 40, sha256: digest)
        }

        for (status, expected) in [(401, GoogleDriveBackupError.unauthorized),
                                   (403, GoogleDriveBackupError.forbidden),
                                   (500, GoogleDriveBackupError.invalidResponse)] {
            let (transport, _) = try driveTransport([
                .init(status: status, body: try driveJSON([:])),
            ])
            await #expect(throws: expected) { try await transport.reserveOperationID() }
        }
        let (oversize, _) = try driveTransport([
            .init(error: TeamAuthHTTPError.responseTooLarge),
        ])
        await #expect(throws: GoogleDriveBackupError.responseTooLarge) {
            try await oversize.reserveOperationID()
        }
    }

    @Test func tokenAndPublicValuesAreRedactedAndInvalidInputsNeverDispatch() async throws {
        #expect(throws: GoogleDriveBackupError.invalidCredential) {
            try GoogleDriveAccessToken("contains space")
        }
        let token = try GoogleDriveAccessToken(String(repeating: "s", count: 32))
        #expect(String(reflecting: token) == "GoogleDriveAccessToken(<redacted>)")
        #expect(Mirror(reflecting: token).children.isEmpty)
        #expect(GoogleDriveBackupTransport.scope ==
                "https://www.googleapis.com/auth/drive.appdata")
        let stub = DriveHTTPStub([])
        let transport = GoogleDriveBackupTransport(accessToken: { token }, executor: stub,
                                                    boundary: { "bad boundary" })
        let data = Data("backup".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        await #expect(throws: GoogleDriveBackupError.invalidRequest) {
            try await transport.append(data, operationID: "reserved_id",
                                       createdAt: 1, sha256: digest)
        }
        #expect(await stub.requests.isEmpty)
    }
}
