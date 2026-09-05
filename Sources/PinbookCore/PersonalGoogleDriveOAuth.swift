#if canImport(AppAuthCore)
import AppAuthCore
#endif
import Foundation

public enum PersonalGoogleDriveOAuthError: Error, Equatable, Sendable {
    case busy
    case cancelled
    case invalidConfiguration
    case invalidRequest
    case invalidResponse
    case expired
    case unauthorized
    case unavailable
    case unavailablePresentation
}

/// Public Google iOS OAuth configuration. Installed applications never contain a
/// client secret; the allocated client ID and registered callback must agree.
public struct PersonalGoogleDriveConfiguration: Sendable {
    public let clientID: String
    public let redirectURL: URL
    public let redirectScheme: String

    public init(clientID: String, registeredURLSchemes: Set<String>) throws {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.utf8.count <= 256 else {
            throw PersonalGoogleDriveOAuthError.invalidConfiguration
        }
        let prefix = clientID.dropLast(suffix.count)
        guard !prefix.isEmpty, prefix.utf8.allSatisfy({
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }) else {
            throw PersonalGoogleDriveOAuthError.invalidConfiguration
        }
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        guard registeredURLSchemes.contains(scheme),
              let redirect = URL(string: scheme + ":/oauth2callback") else {
            throw PersonalGoogleDriveOAuthError.invalidConfiguration
        }
        self.clientID = clientID
        redirectURL = redirect
        redirectScheme = scheme
    }

    static func installed(in bundle: Bundle = .main) throws -> Self {
        guard let clientID = bundle.object(
            forInfoDictionaryKey: "PinbookPersonalGoogleDriveClientID"
        ) as? String else {
            throw PersonalGoogleDriveOAuthError.invalidConfiguration
        }
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes")
            as? [[String: Any]] ?? []
        let schemes = Set(types.flatMap {
            $0["CFBundleURLSchemes"] as? [String] ?? []
        })
        return try Self(clientID: clientID, registeredURLSchemes: schemes)
    }
}

public struct PersonalGoogleDriveRefreshToken: Sendable, CustomStringConvertible,
                                               CustomDebugStringConvertible,
                                               CustomReflectable {
    let value: String

    init(_ value: String) throws {
        guard Self.valid(value) else {
            throw PersonalGoogleDriveOAuthError.invalidResponse
        }
        self.value = value
    }

    public var description: String { "PersonalGoogleDriveRefreshToken(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    fileprivate static func valid(_ value: String) -> Bool {
        (20...16_384).contains(value.utf8.count)
            && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }
}

/// In-memory result of one code exchange or refresh. Persistence and lifecycle
/// ownership are deliberately separate from the HTTP parser.
public struct PersonalGoogleDriveGrant: Sendable, CustomStringConvertible,
                                        CustomDebugStringConvertible, CustomReflectable {
    private let access: GoogleDriveAccessToken
    let refresh: PersonalGoogleDriveRefreshToken
    private let observedAt: Int64
    public let accessExpiresAt: Int64
    let refreshExpiresAt: Int64?

    fileprivate init(access: GoogleDriveAccessToken,
                     refresh: PersonalGoogleDriveRefreshToken,
                     observedAt: Int64,
                     accessExpiresAt: Int64,
                     refreshExpiresAt: Int64?) {
        self.access = access
        self.refresh = refresh
        self.observedAt = observedAt
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    public func accessToken(now: Int64) throws -> GoogleDriveAccessToken {
        guard now >= observedAt, now < accessExpiresAt else {
            throw PersonalGoogleDriveOAuthError.expired
        }
        return access
    }

    public var description: String { "PersonalGoogleDriveGrant(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

#if canImport(AppAuthCore)
/// Actual AppAuth request construction without presentation or provider contact.
enum PersonalGoogleDriveOAuthRequest {
    static let authorizationEndpoint = URL(
        string: "https://accounts.google.com/o/oauth2/v2/auth"
    )!

    static func make(configuration: PersonalGoogleDriveConfiguration) throws
        -> OIDAuthorizationRequest {
        let request = OIDAuthorizationRequest(
            configuration: OIDServiceConfiguration(
                authorizationEndpoint: authorizationEndpoint,
                tokenEndpoint: PersonalGoogleDriveTokenClient.endpoint,
                issuer: URL(string: "https://accounts.google.com")!
            ),
            clientId: configuration.clientID,
            scopes: [GoogleDriveBackupTransport.scope],
            redirectURL: configuration.redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: [
                "access_type": "offline",
                "include_granted_scopes": "false",
                "prompt": "consent",
            ]
        )
        guard request.clientSecret == nil,
              request.scope == GoogleDriveBackupTransport.scope,
              request.codeChallengeMethod == "S256",
              let nonce = request.nonce, Self.credential(nonce),
              let state = request.state, Self.credential(state),
              let verifier = request.codeVerifier,
              (43...128).contains(verifier.utf8.count),
              let challenge = request.codeChallenge, Self.credential(challenge) else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        return request
    }

    private static func credential(_ value: String) -> Bool {
        (20...512).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95 || $0 == 126
        }
    }
}
#endif

protocol PersonalGoogleDriveTokenHTTPExecuting: Sendable {
    func execute(_ request: URLRequest) async throws -> TeamAuthResponse
}

private struct PersonalGoogleDriveTokenHTTPExecutor: PersonalGoogleDriveTokenHTTPExecuting {
    func execute(_ request: URLRequest) async throws -> TeamAuthResponse {
        try await TeamAuthURLExchange(
            request: request,
            configuration: TeamAuthHTTPClient.configuration(),
            localTestAnchor: nil,
            responseProfile: .googleToken,
            maximumResponseBytes: 32 * 1024
        ).run()
    }
}

private final class PersonalGoogleDriveTokenRequestSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    func acquire() throws {
        try lock.withLock {
            guard !active else { throw PersonalGoogleDriveOAuthError.busy }
            active = true
        }
    }

    func release() {
        lock.withLock { active = false }
    }
}

/// Bounded one-dispatch token endpoint client. It accepts no client secret and
/// never persists, logs or refreshes credentials on its own.
final class PersonalGoogleDriveTokenClient: Sendable {
    static let endpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let configuration: PersonalGoogleDriveConfiguration
    private let executor: any PersonalGoogleDriveTokenHTTPExecuting
    private let now: @Sendable () -> Int64
    private let slot = PersonalGoogleDriveTokenRequestSlot()

    init(configuration: PersonalGoogleDriveConfiguration,
         executor: any PersonalGoogleDriveTokenHTTPExecuting =
            PersonalGoogleDriveTokenHTTPExecutor(),
         now: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) {
        self.configuration = configuration
        self.executor = executor
        self.now = now
    }

    func exchange(code: String, verifier: String) async throws -> PersonalGoogleDriveGrant {
        guard Self.code(code), Self.verifier(verifier) else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        let fields = [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURL.absoluteString,
        ]
        return try await request(fields, existingRefresh: nil)
    }

    func refresh(_ token: PersonalGoogleDriveRefreshToken) async throws
        -> PersonalGoogleDriveGrant {
        try await request([
            "client_id": configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": token.value,
        ], existingRefresh: token)
    }

    private func request(_ fields: [String: String],
                         existingRefresh: PersonalGoogleDriveRefreshToken?) async throws
        -> PersonalGoogleDriveGrant {
        try slot.acquire()
        defer { slot.release() }
        try Task.checkCancellation()
        let startedAt = now()
        guard startedAt >= 0, startedAt <= TeamAuthWire.maximumSafeTime else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        let body = Data(fields.keys.sorted().map {
            Self.form($0) + "=" + Self.form(fields[$0]!)
        }.joined(separator: "&").utf8)
        guard body.count <= 24_000 else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        // One-use stream: the exchange delegate deliberately refuses a second
        // body stream after redirects, authentication challenges or retries.
        request.httpBodyStream = InputStream(data: body)
        let response: TeamAuthResponse
        do {
            response = try await executor.execute(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalGoogleDriveOAuthError.unavailable
        }
        if response.status == 401 { throw PersonalGoogleDriveOAuthError.unauthorized }
        guard response.status == 200 else {
            throw PersonalGoogleDriveOAuthError.unavailable
        }
        let completedAt = now()
        guard completedAt >= startedAt, completedAt <= TeamAuthWire.maximumSafeTime else {
            throw PersonalGoogleDriveOAuthError.invalidResponse
        }
        return try Self.grant(response.body, existingRefresh: existingRefresh,
                              now: completedAt)
    }

    static func grant(_ data: Data, existingRefresh: PersonalGoogleDriveRefreshToken?,
                      now: Int64) throws -> PersonalGoogleDriveGrant {
        guard (0...TeamAuthWire.maximumSafeTime).contains(now) else {
            throw PersonalGoogleDriveOAuthError.invalidResponse
        }
        let object: [String: Any]
        do { object = try TeamStrictJSON.object(data, maximumBytes: 32 * 1024) }
        catch { throw PersonalGoogleDriveOAuthError.invalidResponse }
        let required: Set<String> = ["access_token", "expires_in", "scope", "token_type"]
        let allowed = required.union(["refresh_token", "refresh_token_expires_in"])
        guard required.isSubset(of: object.keys), Set(object.keys).isSubset(of: allowed),
              object["token_type"] as? String == "Bearer",
              object["scope"] as? String == GoogleDriveBackupTransport.scope,
              let rawAccess = object["access_token"] as? String,
              let seconds = object["expires_in"] as? NSNumber,
              CFGetTypeID(seconds) != CFBooleanGetTypeID(),
              (60...86_400).contains(seconds.int64Value),
              seconds.int64Value <= (TeamAuthWire.maximumSafeTime - now) / 1_000 else {
            throw PersonalGoogleDriveOAuthError.invalidResponse
        }
        let access: GoogleDriveAccessToken
        do { access = try GoogleDriveAccessToken(rawAccess) }
        catch { throw PersonalGoogleDriveOAuthError.invalidResponse }
        let refresh: PersonalGoogleDriveRefreshToken
        if let raw = object["refresh_token"] as? String {
            do { refresh = try PersonalGoogleDriveRefreshToken(raw) }
            catch { throw PersonalGoogleDriveOAuthError.invalidResponse }
        } else if let existingRefresh {
            refresh = existingRefresh
        } else {
            throw PersonalGoogleDriveOAuthError.invalidResponse
        }
        let refreshExpiresAt: Int64?
        if let remaining = object["refresh_token_expires_in"] {
            guard let refreshSeconds = remaining as? NSNumber,
                  CFGetTypeID(refreshSeconds) != CFBooleanGetTypeID(),
                  refreshSeconds.int64Value > 0,
                  refreshSeconds.int64Value
                    <= (TeamAuthWire.maximumSafeTime - now) / 1_000 else {
                throw PersonalGoogleDriveOAuthError.invalidResponse
            }
            refreshExpiresAt = now + refreshSeconds.int64Value * 1_000
        } else { refreshExpiresAt = nil }
        return PersonalGoogleDriveGrant(access: access, refresh: refresh,
                                        observedAt: now,
                                        accessExpiresAt: now + seconds.int64Value * 1_000,
                                        refreshExpiresAt: refreshExpiresAt)
    }

    private static func code(_ value: String) -> Bool {
        (1...4_096).contains(value.utf8.count)
            && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }

    private static func verifier(_ value: String) -> Bool {
        (43...128).contains(value.utf8.count) && value.utf8.allSatisfy(unreserved)
    }

    private static func unreserved(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 45 || byte == 46 || byte == 95 || byte == 126
    }

    private static func form(_ value: String) -> String {
        value.utf8.map {
            unreserved($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0)
        }.joined()
    }
}
