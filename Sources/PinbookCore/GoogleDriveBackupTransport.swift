import Foundation

public enum GoogleDriveBackupError: Error, Equatable, Sendable {
    case invalidCredential
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case unauthorized
    case forbidden
    case transport
}

/// Ephemeral personal-Drive bearer material. It is deliberately redacted and is
/// never persisted by this adapter or included in requests outside the header.
public struct GoogleDriveAccessToken: Sendable, CustomStringConvertible,
                                      CustomDebugStringConvertible, CustomReflectable {
    fileprivate let value: String

    public init(_ value: String) throws {
        guard (20...16_384).contains(value.utf8.count),
              value.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw GoogleDriveBackupError.invalidCredential
        }
        self.value = value
    }

    public var description: String { "GoogleDriveAccessToken(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum GoogleDriveResponseKind: Sendable { case json, media }

protocol GoogleDriveHTTPExecuting: Sendable {
    func execute(_ request: URLRequest, maximumResponseBytes: Int,
                 kind: GoogleDriveResponseKind) async throws -> TeamAuthResponse
}

private struct GoogleDriveBoundedHTTPExecutor: GoogleDriveHTTPExecuting {
    func execute(_ request: URLRequest, maximumResponseBytes: Int,
                 kind: GoogleDriveResponseKind) async throws -> TeamAuthResponse {
        let profile: TeamAuthURLExchange.ResponseProfile = kind == .json
            ? .googleDriveJSON : .googleDriveMedia
        return try await TeamAuthURLExchange(
            request: request,
            configuration: TeamAuthHTTPClient.configuration(),
            localTestAnchor: nil,
            responseProfile: profile,
            maximumResponseBytes: maximumResponseBytes
        ).run()
    }
}

/// Inactive Drive v3 appDataFolder transport. Construction performs no network
/// request. OAuth consent, token refresh, scheduling and UI remain outside.
public final class GoogleDriveBackupTransport: BackupTransport, @unchecked Sendable {
    public static let scope = "https://www.googleapis.com/auth/drive.appdata"
    private static let metadataResponseLimit = 256 * 1024
    private static let origin = URL(string: "https://www.googleapis.com")!
    private static let schema = "backup-v8"
    private let token: @Sendable () async throws -> GoogleDriveAccessToken
    private let executor: any GoogleDriveHTTPExecuting
    private let boundary: @Sendable () -> String

    public convenience init(
        accessToken: @escaping @Sendable () async throws -> GoogleDriveAccessToken
    ) {
        self.init(accessToken: accessToken,
                  executor: GoogleDriveBoundedHTTPExecutor(),
                  boundary: { "pinbook_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") })
    }

    init(accessToken: @escaping @Sendable () async throws -> GoogleDriveAccessToken,
         executor: any GoogleDriveHTTPExecuting,
         boundary: @escaping @Sendable () -> String) {
        self.token = accessToken
        self.executor = executor
        self.boundary = boundary
    }

    public func reserveOperationID() async throws -> String {
        let response = try await send(
            path: "/drive/v3/files/generateIds",
            query: [
                URLQueryItem(name: "count", value: "1"),
                URLQueryItem(name: "space", value: "appDataFolder"),
                URLQueryItem(name: "type", value: "files"),
                URLQueryItem(name: "fields", value: "ids,kind,space"),
            ],
            maximumResponseBytes: 4_096,
            kind: .json
        )
        try requireSuccess(response.status)
        let object = try Self.strictObject(response.body, required: ["ids", "kind", "space"])
        guard let ids = object["ids"] as? [Any], ids.count == 1,
              let id = ids.first as? String, RemoteBackupSnapshot.opaqueID(id),
              object["kind"] as? String == "drive#generatedIds",
              object["space"] as? String == "appDataFolder" else {
            throw GoogleDriveBackupError.invalidResponse
        }
        return id
    }

    public func list(after cursor: String?) async throws -> RemoteBackupPage {
        if let cursor {
            _ = try RemoteBackupPage(snapshots: [], nextCursor: cursor)
        }
        var query = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "pageSize", value: String(BackupTransportGuard.maximumPageObjects)),
            URLQueryItem(name: "q", value: "trashed = false and appProperties has { key='pinbookSchema' and value='backup-v8' }"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,mimeType,appProperties)"),
        ]
        if let cursor { query.append(URLQueryItem(name: "pageToken", value: cursor)) }
        let response = try await send(path: "/drive/v3/files", query: query,
                                      maximumResponseBytes: Self.metadataResponseLimit,
                                      kind: .json)
        try requireSuccess(response.status)
        let object = try Self.strictObject(response.body, required: ["files"],
                                           optional: ["nextPageToken"])
        guard let files = object["files"] as? [Any],
              files.count <= BackupTransportGuard.maximumPageObjects else {
            throw GoogleDriveBackupError.invalidResponse
        }
        let snapshots = try files.map { value -> RemoteBackupSnapshot in
            guard let value = value as? [String: Any] else {
                throw GoogleDriveBackupError.invalidResponse
            }
            return try Self.snapshot(value)
        }
        guard object["nextPageToken"] == nil || object["nextPageToken"] is String else {
            throw GoogleDriveBackupError.invalidResponse
        }
        return try RemoteBackupPage(snapshots: snapshots,
                                    nextCursor: object["nextPageToken"] as? String)
    }

    public func download(_ snapshot: RemoteBackupSnapshot, maximumBytes: Int) async throws
        -> Data {
        guard maximumBytes == snapshot.byteCount,
              (1...BackupTransportGuard.maximumBackupBytes).contains(maximumBytes) else {
            throw GoogleDriveBackupError.invalidRequest
        }
        let response = try await send(
            path: "/drive/v3/files/" + snapshot.objectID,
            query: [URLQueryItem(name: "alt", value: "media")],
            maximumResponseBytes: maximumBytes,
            kind: .media
        )
        try requireSuccess(response.status)
        return response.body
    }

    public func append(_ backup: Data, operationID: String, createdAt: Int64,
                       sha256: String) async throws -> RemoteBackupSnapshot {
        let expected = try RemoteBackupSnapshot(
            objectID: operationID,
            operationID: operationID,
            createdAt: createdAt,
            byteCount: backup.count,
            sha256: sha256
        )
        let multipartBoundary = boundary()
        guard Self.validBoundary(multipartBoundary) else {
            throw GoogleDriveBackupError.invalidRequest
        }
        let metadataFields: [String: Any] = [
            "id": operationID,
            "name": "pinbook-backup-v8.json",
            "mimeType": "application/octet-stream",
            "parents": ["appDataFolder"],
            "appProperties": Self.properties(expected),
        ]
        let metadataBytes = try JSONSerialization.data(withJSONObject: metadataFields,
                                                       options: [.sortedKeys])
        let body = Self.multipart(metadata: metadataBytes, backup: backup,
                                  boundary: multipartBoundary)
        let response = try await send(
            path: "/upload/drive/v3/files",
            query: [
                URLQueryItem(name: "uploadType", value: "multipart"),
                URLQueryItem(name: "fields", value: "id,mimeType,appProperties"),
            ],
            method: "POST",
            contentType: "multipart/related; boundary=\(multipartBoundary)",
            body: body,
            maximumResponseBytes: Self.metadataResponseLimit,
            kind: .json
        )
        if response.status == 409 {
            let existing = try await metadata(for: operationID)
            guard existing == expected else { throw GoogleDriveBackupError.invalidResponse }
            _ = try await BackupTransportGuard.downloadVerified(existing, using: self)
            return existing
        }
        try requireSuccess(response.status)
        let result = try Self.snapshot(try Self.strictObject(
            response.body,
            required: ["id", "mimeType", "appProperties"]
        ))
        guard result == expected else { throw GoogleDriveBackupError.invalidResponse }
        return result
    }

    private func metadata(for objectID: String) async throws -> RemoteBackupSnapshot {
        guard RemoteBackupSnapshot.opaqueID(objectID) else {
            throw GoogleDriveBackupError.invalidRequest
        }
        let response = try await send(
            path: "/drive/v3/files/" + objectID,
            query: [URLQueryItem(name: "fields", value: "id,mimeType,appProperties")],
            maximumResponseBytes: 8_192,
            kind: .json
        )
        try requireSuccess(response.status)
        return try Self.snapshot(try Self.strictObject(
            response.body,
            required: ["id", "mimeType", "appProperties"]
        ))
    }

    private func send(path: String, query: [URLQueryItem], method: String = "GET",
                      contentType: String? = nil, body: Data? = nil,
                      maximumResponseBytes: Int, kind: GoogleDriveResponseKind) async throws
        -> TeamAuthResponse {
        try Task.checkCancellation()
        guard path.hasPrefix("/drive/v3/") || path.hasPrefix("/upload/drive/v3/"),
              (1...BackupTransportGuard.maximumBackupBytes).contains(maximumResponseBytes) else {
            throw GoogleDriveBackupError.invalidRequest
        }
        var components = URLComponents(url: Self.origin, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query
        guard let url = components.url, url.scheme == "https", url.host == "www.googleapis.com",
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw GoogleDriveBackupError.invalidRequest
        }
        let credential = try await token()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + credential.value, forHTTPHeaderField: "Authorization")
        request.setValue(kind == .json ? "application/json" : "application/octet-stream",
                         forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body {
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.httpBody = body
        }
        do {
            let response = try await executor.execute(
                request,
                maximumResponseBytes: maximumResponseBytes,
                kind: kind
            )
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GoogleDriveBackupError {
            throw error
        } catch TeamAuthHTTPError.responseTooLarge {
            throw GoogleDriveBackupError.responseTooLarge
        } catch {
            throw GoogleDriveBackupError.transport
        }
    }

    private func requireSuccess(_ status: Int) throws {
        switch status {
        case 200: return
        case 401: throw GoogleDriveBackupError.unauthorized
        case 403: throw GoogleDriveBackupError.forbidden
        default: throw GoogleDriveBackupError.invalidResponse
        }
    }

    private static func strictObject(_ data: Data, required: Set<String>,
                                     optional: Set<String> = []) throws -> [String: Any] {
        guard data.count <= metadataResponseLimit else {
            throw GoogleDriveBackupError.responseTooLarge
        }
        let object: [String: Any]
        do { object = try TeamStrictJSON.object(data) }
        catch { throw GoogleDriveBackupError.invalidResponse }
        let keys = Set(object.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
            throw GoogleDriveBackupError.invalidResponse
        }
        return object
    }

    private static func snapshot(_ object: [String: Any]) throws -> RemoteBackupSnapshot {
        guard Set(object.keys) == ["id", "mimeType", "appProperties"],
              let id = object["id"] as? String,
              object["mimeType"] as? String == "application/octet-stream",
              let properties = object["appProperties"] as? [String: Any],
              Set(properties.keys) == ["pinbookSchema", "operationID", "createdAt",
                                       "byteCount", "sha256"],
              properties["pinbookSchema"] as? String == schema,
              let operationID = properties["operationID"] as? String,
              id == operationID,
              let created = properties["createdAt"] as? String,
              let createdAt = Int64(created), String(createdAt) == created,
              let count = properties["byteCount"] as? String,
              let byteCount = Int(count), String(byteCount) == count,
              let sha256 = properties["sha256"] as? String else {
            throw GoogleDriveBackupError.invalidResponse
        }
        do {
            return try RemoteBackupSnapshot(objectID: id, operationID: operationID,
                                            createdAt: createdAt, byteCount: byteCount,
                                            sha256: sha256)
        } catch {
            throw GoogleDriveBackupError.invalidResponse
        }
    }

    private static func properties(_ value: RemoteBackupSnapshot) -> [String: String] {
        [
            "pinbookSchema": schema,
            "operationID": value.operationID,
            "createdAt": String(value.createdAt),
            "byteCount": String(value.byteCount),
            "sha256": value.sha256,
        ]
    }

    private static func validBoundary(_ value: String) -> Bool {
        (16...70).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 95
        }
    }

    private static func multipart(metadata: Data, backup: Data, boundary: String) -> Data {
        var result = Data()
        result.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        result.append(metadata)
        result.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        result.append(backup)
        result.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return result
    }
}
