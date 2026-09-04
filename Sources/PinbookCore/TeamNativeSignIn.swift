import CryptoKit
import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

public enum TeamNativeSignInProvider: Sendable { case apple, google }
public enum TeamNativeSignInError: Error, Equatable {
    case invalidChallenge, busy, expired, invalidCallback
}

/// Volatile provider request context, never a login credential or admission proof.
/// The host selects provider/profile from trusted app configuration, not token claims.
public struct TeamNativeSignInContext: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: UUID
    public let provider: TeamNativeSignInProvider
    public let providerID: String
    public let challengeID: String
    public let nonce: String
    public let state: String
    public let expiresAt: Int64
    public var description: String { "TeamNativeSignInContext(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Unverified identity-token submission. Only the backend verifies signature,
/// nonce, issuer/audience/presenter and admission before issuing a separate session.
/// Deliberately not Codable: the HTTP route/encoding contract is not frozen yet.
public struct TeamNativeLoginSubmission: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let challengeID: String
    public let providerID: String
    public let idToken: String
    public var description: String { "TeamNativeLoginSubmission(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One native authorization attempt at a time. No networking, token persistence,
/// cached sign-in restore, profile lookup, Drive scope or runtime team activation.
public actor TeamNativeSignInFlow {
    private var pending: TeamNativeSignInContext?
    private var lastNow: Int64?
    public init() {}

    public func begin(provider: TeamNativeSignInProvider, providerID: String,
                      challengeID: String, nonce: String, expiresAt: Int64,
                      now: Int64) throws -> TeamNativeSignInContext {
        try Task.checkCancellation()
        try checkClock(now)
        guard pending == nil else { throw TeamNativeSignInError.busy }
        guard (try? TeamDeliveryRules.requireID(providerID)) != nil,
              Self.isRandom256(challengeID), Self.isRandom256(nonce),
              expiresAt > now, expiresAt - now <= 120_000 else {
            throw TeamNativeSignInError.invalidChallenge
        }
        let key = SymmetricKey(size: .bits256)
        let state = key.withUnsafeBytes { Self.base64URL(Data($0)) }
        let context = TeamNativeSignInContext(id: UUID(), provider: provider,
            providerID: providerID, challengeID: challengeID, nonce: nonce,
            state: state, expiresAt: expiresAt)
        pending = context
        return context
    }

    public func cancel(attemptID: UUID) {
        if pending?.id == attemptID { pending = nil }
    }

    /// The native Apple credential must echo the state on this exact request.
    public func acceptApple(attemptID: UUID, returnedState: String?,
                            identityToken: Data, now: Int64) throws -> TeamNativeLoginSubmission {
        let context = try take(attemptID: attemptID, provider: .apple, now: now)
        guard returnedState == context.state else { throw TeamNativeSignInError.invalidCallback }
        return try submission(context, identityToken)
    }

    /// Call only from the fresh interactive Google SDK request's own callback.
    /// The SDK owns OAuth state/PKCE; this UUID binds that callback locally. A
    /// cached currentUser/refresh token is NOT a new challenge response.
    public func acceptGoogleSDK(attemptID: UUID, identityToken: Data,
                                now: Int64) throws -> TeamNativeLoginSubmission {
        let context = try take(attemptID: attemptID, provider: .google, now: now)
        return try submission(context, identityToken)
    }

    private func take(attemptID: UUID, provider: TeamNativeSignInProvider,
                      now: Int64) throws -> TeamNativeSignInContext {
        guard let current = pending, current.id == attemptID else { throw TeamNativeSignInError.expired }
        // Matching callbacks are consumed even if cancelled, malformed or expired.
        // A stale callback never consumes a newer attempt.
        pending = nil
        try Task.checkCancellation()
        try checkClock(now)
        guard current.provider == provider else { throw TeamNativeSignInError.invalidCallback }
        guard now < current.expiresAt else { throw TeamNativeSignInError.expired }
        return current
    }

    private func checkClock(_ now: Int64) throws {
        // JS-safe Unix milliseconds match the backend profile. Rollback drops
        // any pending context; a new explicit challenge is required afterward.
        guard now >= 0, now <= 9_007_199_254_620_991,
              lastNow.map({ now >= $0 }) ?? true else {
            pending = nil
            throw TeamNativeSignInError.expired
        }
        lastNow = now
    }

    private func submission(_ context: TeamNativeSignInContext,
                            _ bytes: Data) throws -> TeamNativeLoginSubmission {
        guard (1...16_384).contains(bytes.count),
              bytes.allSatisfy({ Self.isURLByte($0) || $0 == 46 }) else {
            throw TeamNativeSignInError.invalidCallback
        }
        let token = String(decoding: bytes, as: UTF8.self)
        guard token.split(separator: ".", omittingEmptySubsequences: false).count == 3,
              !token.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty) else {
            throw TeamNativeSignInError.invalidCallback
        }
        return TeamNativeLoginSubmission(challengeID: context.challengeID,
            providerID: context.providerID, idToken: token)
    }

    private static func isURLByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func isRandom256(_ value: String) -> Bool {
        guard value.utf8.count == 43, value.utf8.allSatisfy(isURLByte),
              let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else { return false }
        return base64URL(bytes) == value
    }
}

#if canImport(AuthenticationServices)
extension TeamNativeSignInContext {
    /// Request construction only. The host must retain its controller, validate
    /// returned state through the flow and submit the token to the trusted server.
    /// No name/email scope is needed for exact issuer+subject admission.
    @MainActor public func makeAppleRequest() throws -> ASAuthorizationAppleIDRequest {
        guard provider == .apple else { throw TeamNativeSignInError.invalidCallback }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = nonce
        request.state = state
        request.requestedScopes = []
        return request
    }
}
#endif
