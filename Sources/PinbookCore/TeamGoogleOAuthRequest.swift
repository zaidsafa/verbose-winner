#if canImport(AppAuthCore)
import Foundation
import AppAuthCore

/// Shared actual AppAuth request construction, testable without a UI or account.
enum TeamGoogleOAuthRequest {
    static func make(configuration: TeamGoogleNativeConfiguration, context: TeamNativeSignInContext) throws -> OIDAuthorizationRequest {
        guard context.provider == .google, context.providerID == configuration.providerID,
              TeamAuthWire.credential(context.nonce), TeamAuthWire.credential(context.challengeID) else {
            throw TeamGoogleIdentityError.invalidContext
        }
        let request = OIDAuthorizationRequest(configuration: OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: TeamGoogleTokenClient.endpoint, issuer: URL(string: "https://accounts.google.com")!),
            clientId: configuration.nativeClientID, scopes: ["openid"], redirectURL: configuration.redirectURL,
            responseType: OIDResponseTypeCode, nonce: context.nonce,
            additionalParameters: ["audience": configuration.serverClientID, "prompt": "select_account",
                "include_granted_scopes": "false", "access_type": "online"])
        guard request.nonce == context.nonce, request.codeChallengeMethod == "S256",
              let state = request.state, TeamAuthWire.credential(state),
              let verifier = request.codeVerifier, (43...128).contains(verifier.utf8.count),
              let challenge = request.codeChallenge, TeamAuthWire.credential(challenge) else {
            throw TeamGoogleIdentityError.invalidContext
        }
        return request
    }
}
#endif
