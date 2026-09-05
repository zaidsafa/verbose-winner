import Foundation
import CoreFoundation
import Security

public enum TeamAuthServerError: String, Sendable {
    case invalidRequest = "invalid_request", jsonRequired = "json_required"
    case requestTooLarge = "request_too_large", notFound = "not_found"
    case requestTimeout = "request_timeout", invalidCredentials = "invalid_credentials"
    case capacity, unavailable, uncertain, terminal
}

/// No URLs, tokens, raw response bodies or underlying provider errors in diagnostics.
public enum TeamAuthHTTPError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidRequest, invalidResponse, responseTooLarge
    case redirectRefused, transport, busy, server(TeamAuthServerError)
}

public struct TeamAuthChallenge: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let challengeID: String
    public let nonce: String
    public let expiresAt: Int64
    public var description: String { "TeamAuthChallenge(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Account-session credentials only. Never place this value in a portable backup,
/// analytics, URL, clipboard or ordinary app persistence. Not device/team authority.
public struct TeamAuthSessionPair: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accountID: String
    public let sessionID: String
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresAt: Int64
    public let sessionExpiresAt: Int64
    public var description: String { "TeamAuthSessionPair(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct TeamAuthAccountSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accountID: String
    public let sessionID: String
    public let providerID: String
    public var description: String { "TeamAuthAccountSession(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum TeamAuthWire {
    static let maximumResponseBytes = 32 * 1024
    static let maximumDeliveryFetchResponseBytes = 140_000
    static let maximumRequestBytes = 20_000
    static let maximumDeliverySubmitRequestBytes = 140_000
    static let maximumSafeTime: Int64 = 9_007_199_254_740_991

    static func credential(_ value: String) -> Bool {
        guard value.utf8.count == 43, value.utf8.allSatisfy(urlByte),
              let data = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="), data.count == 32 else { return false }
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
    }
    static func urlByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }
    static func identifier(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy(urlByte)
    }
    static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        let object = try TeamStrictJSON.object(data)
        guard Set(object.keys) == keys else { throw TeamAuthHTTPError.invalidResponse }
        return object
    }
    static func string(_ object: [String: Any], _ key: String, secret: Bool = false) throws -> String {
        guard let value = object[key] as? String,
              secret ? credential(value) : identifier(value) else { throw TeamAuthHTTPError.invalidResponse }
        return value
    }
    static func time(_ object: [String: Any], _ key: String) throws -> Int64 {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { throw TeamAuthHTTPError.invalidResponse }
        let number = value.doubleValue
        guard number.isFinite, number >= 0, number <= Double(maximumSafeTime),
              number.rounded(.towardZero) == number else { throw TeamAuthHTTPError.invalidResponse }
        return Int64(number)
    }
    static func boolean(_ object: [String: Any], _ key: String) throws -> Bool {
        guard let value = object[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return value.boolValue
    }
    static func challenge(_ data: Data) throws -> TeamAuthChallenge {
        let object = try object(data, keys: ["challengeId", "nonce", "expiresAt"])
        return try TeamAuthChallenge(challengeID: string(object, "challengeId", secret: true),
            nonce: string(object, "nonce", secret: true), expiresAt: time(object, "expiresAt"))
    }
    static func pair(_ data: Data) throws -> TeamAuthSessionPair {
        let object = try object(data, keys: ["accountId", "sessionId", "accessToken", "refreshToken", "accessExpiresAt", "sessionExpiresAt"])
        let result = try TeamAuthSessionPair(accountID: string(object, "accountId"),
            sessionID: string(object, "sessionId"), accessToken: string(object, "accessToken", secret: true),
            refreshToken: string(object, "refreshToken", secret: true),
            accessExpiresAt: time(object, "accessExpiresAt"), sessionExpiresAt: time(object, "sessionExpiresAt"))
        guard result.accessExpiresAt <= result.sessionExpiresAt,
              result.accessToken != result.refreshToken else { throw TeamAuthHTTPError.invalidResponse }
        return result
    }
    static func account(_ data: Data) throws -> TeamAuthAccountSession {
        let object = try object(data, keys: ["accountId", "sessionId", "providerId"])
        return try TeamAuthAccountSession(accountID: string(object, "accountId"),
            sessionID: string(object, "sessionId"), providerID: string(object, "providerId"))
    }
    static func serverError(_ data: Data, status: Int) -> TeamAuthHTTPError {
        guard let object = try? object(data, keys: ["error"]), let raw = object["error"] as? String,
              let code = TeamAuthServerError(rawValue: raw) else { return .invalidResponse }
        let expected: Int
        switch code {
        case .invalidRequest: expected = 400
        case .jsonRequired: expected = 415
        case .requestTooLarge: expected = 413
        case .notFound: expected = 404
        case .requestTimeout: expected = 408
        case .invalidCredentials: expected = 401
        case .capacity: expected = 429
        case .unavailable, .uncertain: expected = 503
        case .terminal: expected = 410
        }
        return status == expected ? .server(code) : .invalidResponse
    }
}

struct TeamAuthResponse: Sendable {
    let status: Int
    let body: Data
}

/// Fixed non-secret diagnostic values, injectable only for private DEBUG TLS tests.
enum TeamAuthTestFailure: Sendable, Equatable {
    case url(Int), trust(Int), trustSetup, otherTransport
}
/// Mutable state is protected by lock, including task cancellation and delegate
/// callbacks. Each request owns a fresh ephemeral session and exactly one resume.
final class TeamAuthURLExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum ResponseProfile {
        case pinbook, googleToken, googleRevoke, googleDriveJSON, googleDriveMedia
    }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TeamAuthResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var bytes = Data()
    private var finished = false
    private var terminalResult: Result<TeamAuthResponse, Error>?
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let localTestAnchor: Data?
    private let responseProfile: ResponseProfile
    private let maximumResponseBytes: Int
    private let testTransportFailure: (@Sendable (TeamAuthTestFailure) -> Void)?

    init(request: URLRequest, configuration: URLSessionConfiguration, localTestAnchor: Data?,
         responseProfile: ResponseProfile = .pinbook, maximumResponseBytes: Int = TeamAuthWire.maximumResponseBytes,
         testTransportFailure: (@Sendable (TeamAuthTestFailure) -> Void)? = nil) {
        self.request = request
        self.configuration = configuration
        self.localTestAnchor = localTestAnchor
        self.responseProfile = responseProfile
        self.maximumResponseBytes = maximumResponseBytes
        #if DEBUG
        self.testTransportFailure = localTestAnchor != nil && request.url?.host == "localhost" ? testTransportFailure : nil
        #else
        self.testTransportFailure = nil
        #endif
    }

    func run() async throws -> TeamAuthResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session; self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    private func finish(_ result: Result<TeamAuthResponse, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, task = self.task, session = self.session
        terminalResult = result
        if session == nil { self.continuation = nil; terminalResult = nil }
        bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex)
        bytes = Data(); response = nil
        lock.unlock()
        task?.cancel(); session?.invalidateAndCancel()
        // Do not release the caller's single-flight slot while CFNetwork still
        // owns a cancelled request. Invalidation follows all task callbacks.
        if session == nil { continuation?.resume(with: result) }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        lock.lock()
        finished = true
        let continuation = self.continuation
        let result = terminalResult ?? .failure(TeamAuthHTTPError.transport)
        self.continuation = nil; self.task = nil; self.session = nil; terminalResult = nil
        bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex)
        bytes = Data(); response = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(TeamAuthHTTPError.redirectRefused))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(challenge, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(challenge, completionHandler: completionHandler)
    }

    private func authenticate(_ challenge: URLAuthenticationChallenge,
                              completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if DEBUG
        // Private loopback TLS fixtures only. Still evaluate the hostname, dates
        // and chain using Security; never install certificates in a trust store.
        if let localTestAnchor, request.url?.host == "localhost",
           challenge.protectionSpace.host == "localhost",
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let trust = challenge.protectionSpace.serverTrust,
                  let certificate = SecCertificateCreateWithData(nil, localTestAnchor as CFData),
                  SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, "localhost" as CFString)) == errSecSuccess,
                  SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
                  SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else {
                testTransportFailure?(.trustSetup)
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
            var trustError: CFError?
            guard SecTrustEvaluateWithError(trust, &trustError) else {
                testTransportFailure?(.trust(trustError.map { CFErrorGetCode($0) } ?? 0))
                completionHandler(.cancelAuthenticationChallenge, nil); return
            }
            completionHandler(.useCredential, URLCredential(trust: trust)); return
        }
        #endif
        completionHandler(TeamAuthHTTPClient.authenticationDisposition(challenge.protectionSpace.authenticationMethod), nil)
    }

    // The initial stream is attached to the data request. Never provide a second
    // stream after a recoverable error/auth challenge; rotating tokens are one-use.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64,
                    completionHandler: @escaping @Sendable (InputStream?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let drive = responseProfile == .googleDriveJSON || responseProfile == .googleDriveMedia
        let expectedMIME = responseProfile == .googleDriveMedia
            ? "application/octet-stream" : "application/json"
        let validMIME = responseProfile == .googleRevoke
            ? (response.mimeType?.lowercased() == expectedMIME || response.mimeType == nil)
            : response.mimeType?.lowercased() == expectedMIME
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              http.allHeaderFields.count <= 32,
              http.allHeaderFields.reduce(0, { $0 + String(describing: $1.key).utf8.count + String(describing: $1.value).utf8.count }) <= 8192,
              http.value(forHTTPHeaderField: "Set-Cookie") == nil,
              http.value(forHTTPHeaderField: "Content-Encoding") == nil,
              (drive || http.value(forHTTPHeaderField: "Cache-Control")?.lowercased().split(separator: ",")
                .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "no-store" }) == true),
              (responseProfile != .pinbook || http.value(forHTTPHeaderField: "X-Content-Type-Options")?.lowercased() == "nosniff"),
              validMIME else {
            completionHandler(.cancel)
            finish(.failure(TeamAuthHTTPError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= maximumResponseBytes else {
            completionHandler(.cancel)
            finish(.failure(TeamAuthHTTPError.responseTooLarge))
            return
        }
        lock.lock()
        let active = !finished
        if active { self.response = http }
        lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= maximumResponseBytes - bytes.count else {
            lock.unlock()
            finish(.failure(TeamAuthHTTPError.responseTooLarge))
            return
        }
        bytes.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let result: Result<TeamAuthResponse, Error>
        if error != nil { result = .failure(TeamAuthHTTPError.transport) }
        else if let response { result = .success(TeamAuthResponse(status: response.statusCode, body: bytes)) }
        else { result = .failure(TeamAuthHTTPError.invalidResponse) }
        lock.unlock()
        // Private DEBUG loopback fixtures only: fixed URL error number, never
        // localized text, userInfo, URLs, bodies or credentials.
        if let error = error as NSError? {
            testTransportFailure?(error.domain == NSURLErrorDomain ? .url(error.code) : .otherTransport)
        }
        finish(result)
    }
}

private final class TeamAuthRequestSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    func acquire() throws {
        try lock.withLock {
            guard !active else { throw TeamAuthHTTPError.busy }
            active = true
        }
    }
    func release() { lock.withLock { active = false } }
}

/// Inactive until an approved origin/provider setup and protected session custody
/// are supplied. Construction does not connect. No application retry loop.
public final class TeamAuthHTTPClient: @unchecked Sendable {
    // Immutable after init; protocol metatypes are injected only by isolated tests.
    private let origin: URL
    private let protocolClasses: [AnyClass]?
    private let localTestAnchor: Data?
    private let testTransportFailure: (@Sendable (TeamAuthTestFailure) -> Void)?
    private let clock: @Sendable () -> Int64
    private let slot = TeamAuthRequestSlot()

    public convenience init(origin: URL) throws { try self.init(origin: origin, protocolClasses: nil) }
    init(origin: URL, protocolClasses: [AnyClass]?, localTestAnchor: Data? = nil,
         testTransportFailure: (@Sendable (TeamAuthTestFailure) -> Void)? = nil,
         clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
        guard origin.scheme == "https", let host = origin.host, !host.isEmpty,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/", origin.port.map({ (1...65535).contains($0) }) ?? true else {
            throw TeamAuthHTTPError.invalidConfiguration
        }
        #if DEBUG
        guard (localTestAnchor == nil || (host == "localhost" && protocolClasses == nil)),
              testTransportFailure == nil || localTestAnchor != nil else {
            throw TeamAuthHTTPError.invalidConfiguration
        }
        #else
        guard localTestAnchor == nil, testTransportFailure == nil else { throw TeamAuthHTTPError.invalidConfiguration }
        #endif
        self.origin = origin; self.protocolClasses = protocolClasses; self.localTestAnchor = localTestAnchor
        self.testTransportFailure = testTransportFailure
        self.clock = clock
    }

    static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.urlCache = nil; value.httpCookieStorage = nil; value.urlCredentialStorage = nil
        value.httpShouldSetCookies = false; value.requestCachePolicy = .reloadIgnoringLocalCacheData
        value.timeoutIntervalForRequest = 10; value.timeoutIntervalForResource = 15
        value.waitsForConnectivity = false
        if let protocolClasses { value.protocolClasses = protocolClasses }
        return value
    }

    static func authenticationDisposition(_ method: String) -> URLSession.AuthChallengeDisposition {
        // Keep normal platform TLS validation; never supply ambient Basic/Digest,
        // proxy or client-certificate credentials in response to a server challenge.
        method == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge
    }

    public func challenge(providerID: String) async throws -> TeamAuthChallenge {
        guard TeamAuthWire.identifier(providerID) else { throw TeamAuthHTTPError.invalidRequest }
        return try TeamAuthWire.challenge(await send("challenge", fields: ["providerId": providerID]))
    }
    public func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair {
        guard TeamAuthWire.identifier(submission.providerID), TeamAuthWire.credential(submission.challengeID),
              (1...16_384).contains(submission.idToken.utf8.count),
              submission.idToken.utf8.allSatisfy({ TeamAuthWire.urlByte($0) || $0 == 46 }) else { throw TeamAuthHTTPError.invalidRequest }
        return try TeamAuthWire.pair(await send("exchange", fields: ["providerId": submission.providerID,
            "challengeId": submission.challengeID, "idToken": submission.idToken]))
    }
    /// Caller MUST persist the in-flight marker before this call and serialize
    /// refresh. On ANY ambiguous/unknown result, never replay the previous token.
    public func refresh(_ current: TeamAuthSessionPair) async throws -> TeamAuthSessionPair {
        guard TeamAuthWire.credential(current.refreshToken) else { throw TeamAuthHTTPError.invalidRequest }
        let next = try TeamAuthWire.pair(await send("refresh", fields: ["refreshToken": current.refreshToken]))
        guard next.accountID == current.accountID, next.sessionID == current.sessionID,
              next.sessionExpiresAt == current.sessionExpiresAt,
              ![current.accessToken, current.refreshToken].contains(next.accessToken),
              ![current.accessToken, current.refreshToken].contains(next.refreshToken) else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return next
    }
    public func logout(refreshToken: String) async throws {
        guard TeamAuthWire.credential(refreshToken) else { throw TeamAuthHTTPError.invalidRequest }
        _ = try await send("logout", fields: ["refreshToken": refreshToken], expectedStatus: 204)
    }
    public func logoutAll(accessToken: String) async throws {
        _ = try await send("logout-all", fields: [:], bearer: accessToken, expectedStatus: 204)
    }
    public func session(for pair: TeamAuthSessionPair) async throws -> TeamAuthAccountSession {
        let session = try TeamAuthWire.account(await send("session", fields: nil, bearer: pair.accessToken))
        guard session.accountID == pair.accountID, session.sessionID == pair.sessionID else { throw TeamAuthHTTPError.invalidResponse }
        return session
    }

    private func send(_ route: String, fields: [String: String]?, bearer: String? = nil,
                      expectedStatus: Int = 200) async throws -> Data {
        try await sendPath("auth/\(route)", fields: fields, bearer: bearer, expectedStatus: expectedStatus, maximumResponseBytes: 4096)
    }

    func onboarding(_ route: TeamOnboardingRoute, fields: [String: Any], session: TeamAccountSessionSnapshot? = nil) async throws -> (data: Data, receivedAt: Int64) {
        try await onboardingAccess(route, fields: fields, ticket: session.map { try TeamAccountAccessTicket(snapshot: $0) })
    }
    func onboarding(_ route: TeamOnboardingRoute, fields: [String: Any], ticket: TeamAccountAccessTicket) async throws -> (data: Data, receivedAt: Int64) {
        try await onboardingAccess(route, fields: fields, ticket: ticket)
    }
    private func onboardingAccess(_ route: TeamOnboardingRoute, fields: [String: Any], ticket: TeamAccountAccessTicket?) async throws -> (data: Data, receivedAt: Int64) {
        try Task.checkCancellation()
        let start = try onboardingTime()
        let bearer: String?
        if route.requiresSession {
            guard let ticket, ticket.scope.origin.absoluteString == origin.appendingPathComponent("").absoluteString else {
                throw TeamAuthHTTPError.invalidRequest
            }
            bearer = try ticket.usableToken(now: start)
        } else {
            guard ticket == nil else { throw TeamAuthHTTPError.invalidRequest }
            bearer = nil
        }
        let maximumResponseBytes: Int
        switch route {
        case .deliveryFetch, .deliverySubmitReserve:
            maximumResponseBytes = TeamAuthWire.maximumDeliveryFetchResponseBytes
        case .deliveryPending, .listInvitations, .deviceRequestExecute:
            maximumResponseBytes = TeamAuthWire.maximumResponseBytes
        default: maximumResponseBytes = 4096
        }
        let maximumRequestBytes = route == .deliverySubmitReserve
            ? TeamAuthWire.maximumDeliverySubmitRequestBytes : TeamAuthWire.maximumRequestBytes
        let data = try await sendPath(route.rawValue, fields: fields, bearer: bearer, expectedStatus: 200,
            maximumResponseBytes: maximumResponseBytes, maximumRequestBytes: maximumRequestBytes)
        let end = clock()
        guard end >= start, end <= TeamAuthWire.maximumSafeTime else { throw TeamAuthHTTPError.invalidResponse }
        if let ticket { _ = try ticket.usableToken(now: end) }
        return (data, end)
    }

    func onboardingTime() throws -> Int64 {
        let value = clock()
        guard value >= 0, value <= TeamAuthWire.maximumSafeTime else { throw TeamAuthHTTPError.invalidRequest }
        return value
    }

    func acceptsDeviceBinding(_ binding: TeamDeviceEnrollmentWire.Binding, ticket: TeamAccountAccessTicket) -> Bool {
        let raw = origin.absoluteString
        let canonical = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return TeamDeviceEnrollmentWire.canonicalAudience(binding.audience) && binding.audience == canonical &&
            binding.accountID == ticket.accountID && binding.sessionID == ticket.sessionID &&
            TeamAuthWire.identifier(binding.authorityEpoch) && TeamAuthWire.identifier(binding.deviceID) &&
            TeamAuthWire.credential(binding.keyThumbprint) && binding.accessExpiresAt == ticket.accessExpiresAt
    }

    private func sendPath(_ path: String, fields: [String: Any]?, bearer: String?,
                          expectedStatus: Int, maximumResponseBytes: Int,
                          maximumRequestBytes: Int = TeamAuthWire.maximumRequestBytes) async throws -> Data {
        try Task.checkCancellation()
        try slot.acquire()
        defer { slot.release() } // URL exchange does not return before native invalidation.
        try Task.checkCancellation()
        var request = URLRequest(url: origin.appendingPathComponent("api/v1/\(path)"))
        request.httpMethod = fields == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let bearer {
            guard TeamAuthWire.credential(bearer) else { throw TeamAuthHTTPError.invalidRequest }
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let fields {
            let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
            guard (1...TeamAuthWire.maximumDeliverySubmitRequestBytes).contains(maximumRequestBytes),
                  body.count <= maximumRequestBytes else { throw TeamAuthHTTPError.invalidRequest }
            request.httpBodyStream = InputStream(data: body)
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let result = try await TeamAuthURLExchange(request: request,
            configuration: Self.configuration(protocolClasses: protocolClasses), localTestAnchor: localTestAnchor,
            maximumResponseBytes: maximumResponseBytes, testTransportFailure: testTransportFailure).run()
        try Task.checkCancellation()
        guard result.status == expectedStatus else { throw TeamAuthWire.serverError(result.body, status: result.status) }
        if expectedStatus == 204, !result.body.isEmpty { throw TeamAuthHTTPError.invalidResponse }
        return result.body
    }
}
