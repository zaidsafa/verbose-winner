import Foundation

public enum TeamGoogleIdentityError: Error, Equatable {
    case invalidConfiguration, invalidContext, unavailablePresentation, busy, failed, invalidCredential, cancelled
}

/// Trusted public configuration only. No secrets and no defaults pretending to be
/// allocated OAuth clients. Construct only after confirming the console inventory.
public struct TeamGoogleNativeConfiguration: Sendable {
    public let providerID: String
    public let nativeClientID: String
    public let serverClientID: String
    public let redirectURL: URL
    public let redirectScheme: String
    public let allowLegacyIssuer: Bool

    public init(providerID: String, nativeClientID: String, serverClientID: String,
                registeredURLSchemes: Set<String>, allowLegacyIssuer: Bool = false) throws {
        guard TeamAuthWire.identifier(providerID), Self.isClientID(nativeClientID),
              Self.isClientID(serverClientID), nativeClientID != serverClientID else {
            throw TeamGoogleIdentityError.invalidConfiguration
        }
        let scheme = nativeClientID.split(separator: ".").reversed().joined(separator: ".")
        guard registeredURLSchemes.contains(scheme),
              let redirect = URL(string: scheme + ":/oauth2callback") else {
            throw TeamGoogleIdentityError.invalidConfiguration
        }
        self.providerID = providerID; self.nativeClientID = nativeClientID
        self.serverClientID = serverClientID; redirectURL = redirect; redirectScheme = scheme
        self.allowLegacyIssuer = allowLegacyIssuer
    }
    private static func isClientID(_ value: String) -> Bool {
        let suffix = ".apps.googleusercontent.com"
        guard value.hasSuffix(suffix), value.utf8.count <= 256 else { return false }
        let prefix = value.dropLast(suffix.count)
        return !prefix.isEmpty && prefix.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }
    }
}

/// Fresh authorization-code exchange only. No provider refresh/restore/persistence,
/// no shared AppAuth URLSession and no Drive scopes or grant revocation.
final class TeamGoogleTokenClient: @unchecked Sendable {
    private let configuration: TeamGoogleNativeConfiguration
    private let protocolClasses: [AnyClass]?
    private let now: @Sendable () -> Int64
    static let endpoint = URL(string: "https://oauth2.googleapis.com/token")!

    init(configuration: TeamGoogleNativeConfiguration) {
        self.configuration = configuration; protocolClasses = nil
        now = { Int64(Date().timeIntervalSince1970 * 1000) }
    }
    #if DEBUG
    init(configuration: TeamGoogleNativeConfiguration, protocolClasses: [AnyClass], now: @escaping @Sendable () -> Int64) {
        self.configuration = configuration; self.protocolClasses = protocolClasses; self.now = now
    }
    #endif

    func exchange(code: String, verifier: String, context: TeamNativeSignInContext) async throws -> Data {
        try Task.checkCancellation()
        let startedAt = now()
        guard context.provider == .google, context.providerID == configuration.providerID,
              startedAt >= 0, context.expiresAt > startedAt, context.expiresAt - startedAt <= 120_000,
              TeamAuthWire.credential(context.nonce), TeamAuthWire.credential(context.challengeID),
              (1...4096).contains(code.utf8.count), code.utf8.allSatisfy({ (33...126).contains($0) }),
              (43...128).contains(verifier.utf8.count), verifier.utf8.allSatisfy(Self.unreserved)
        else { throw TeamGoogleIdentityError.invalidContext }
        // OAuth's form body, never URL query parameters. A public native client has
        // no client_secret. Mirror the explicitly configured Google server audience.
        let fields = ["grant_type": "authorization_code", "client_id": configuration.nativeClientID,
            "redirect_uri": configuration.redirectURL.absoluteString, "code": code,
            "code_verifier": verifier, "audience": configuration.serverClientID]
        let body = Data(fields.keys.sorted().map { Self.form($0) + "=" + Self.form(fields[$0]!) }.joined(separator: "&").utf8)
        guard body.count <= 20_000 else { throw TeamGoogleIdentityError.invalidContext }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBodyStream = InputStream(data: body)
        do {
            let response = try await TeamAuthURLExchange(request: request,
                configuration: TeamAuthHTTPClient.configuration(protocolClasses: protocolClasses),
                localTestAnchor: nil, responseProfile: .googleToken).run()
            try Task.checkCancellation()
            let completedAt = now()
            guard completedAt >= startedAt, completedAt < context.expiresAt else {
                throw TeamGoogleIdentityError.invalidContext
            }
            guard response.status == 200 else { throw TeamGoogleIdentityError.failed }
            return try Self.identityToken(response.body, configuration: configuration, context: context, now: completedAt)
        } catch is CancellationError { throw CancellationError() }
        catch let error as TeamGoogleIdentityError { throw error }
        catch { throw TeamGoogleIdentityError.failed }
    }

    /// Defensive local claim checks only, NOT signature verification or admission.
    /// The backend still verifies RS256/JWKS, exact profile, nonce and account state.
    static func identityToken(_ response: Data, configuration: TeamGoogleNativeConfiguration,
                              context: TeamNativeSignInContext, now: Int64) throws -> Data {
        guard now >= 0, now <= TeamAuthWire.maximumSafeTime, now < context.expiresAt,
              context.provider == .google, context.providerID == configuration.providerID,
              TeamAuthWire.credential(context.nonce), response.count <= TeamAuthWire.maximumResponseBytes,
              let responseFields = try? JSONSerialization.jsonObject(with: response) as? [String: Any], responseFields.count <= 32,
              responseFields["error"] == nil, let token = responseFields["id_token"] as? String,
              (1...16_384).contains(token.utf8.count) else { throw TeamGoogleIdentityError.invalidCredential }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let header = object(parts[0]), let claims = object(parts[1]),
              decode(parts[2]) != nil,
              Set(header.keys).isSubset(of: ["alg", "kid", "typ"]), header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String, (1...128).contains(kid.utf8.count),
              header["typ"] == nil || header["typ"] as? String == "JWT",
              claims["iss"] as? String == "https://accounts.google.com" ||
                (configuration.allowLegacyIssuer && claims["iss"] as? String == "accounts.google.com"),
              claims["aud"] as? String == configuration.serverClientID,
              claims["azp"] as? String == configuration.nativeClientID,
              claims["nonce"] as? String == context.nonce,
              let subject = claims["sub"] as? String, (1...255).contains(subject.utf8.count),
              subject.utf8.allSatisfy({ (33...126).contains($0) }),
              let issuedAt = try? TeamAuthWire.time(claims, "iat"),
              let expiresAt = try? TeamAuthWire.time(claims, "exp"),
              issuedAt <= TeamAuthWire.maximumSafeTime / 1000, expiresAt <= TeamAuthWire.maximumSafeTime / 1000,
              issuedAt * 1000 <= now, expiresAt * 1000 > now, expiresAt > issuedAt,
              issuedAt * 1000 >= context.expiresAt - 121_000
        else { throw TeamGoogleIdentityError.invalidCredential }
        // Do not retain/return the Google access token, refresh token, profile or scopes.
        return Data(token.utf8)
    }
    private static func object(_ part: Substring) -> [String: Any]? {
        guard let bytes = decode(part), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              value.count <= 32 else { return nil }
        return value
    }
    private static func decode(_ value: Substring) -> Data? {
        guard !value.isEmpty, value.utf8.count <= 16_384, value.utf8.allSatisfy(TeamAuthWire.urlByte) else { return nil }
        let raw = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: raw), data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == String(value) else { return nil }
        return data
    }
    private static func unreserved(_ byte: UInt8) -> Bool { TeamAuthWire.urlByte(byte) || byte == 46 || byte == 126 }
    private static func form(_ value: String) -> String {
        value.utf8.map { unreserved($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
    }
}
