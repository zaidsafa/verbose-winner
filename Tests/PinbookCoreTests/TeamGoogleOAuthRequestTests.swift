#if canImport(AppAuthCore)
import Foundation
import CryptoKit
import AppAuthCore
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class SilentOAuthUserAgent: NSObject, OIDExternalUserAgent {
    var starts = 0
    var dismissals = 0
    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool {
        starts += 1; return true // Never presents UI, opens a URL or contacts a provider.
    }
    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        dismissals += 1; completion()
    }
}

@MainActor @Suite(.serialized)
struct TeamGoogleOAuthRequestTests {
    private func request() async throws -> OIDAuthorizationRequest {
        let configuration = try TeamGoogleNativeConfiguration(providerID: "public-google-ios",
            nativeClientID: "123-publicnative.apps.googleusercontent.com",
            serverClientID: "123-publicserver.apps.googleusercontent.com",
            registeredURLSchemes: ["com.googleusercontent.apps.123-publicnative"])
        let context = try await TeamNativeSignInFlow().begin(provider: .google, providerID: configuration.providerID,
            challengeID: String(repeating: "A", count: 43), nonce: String(repeating: "B", count: 42) + "A",
            expiresAt: 121_000, now: 1_000)
        return try TeamGoogleOAuthRequest.make(configuration: configuration, context: context)
    }
    @Test func actualSDKRequestPreservesRawNonceWithFreshStatePKCEAndNoDriveScope() async throws {
        let request = try await request(), other = try await self.request()
        #expect(request.nonce == String(repeating: "B", count: 42) + "A")
        #expect(request.state != other.state && request.codeVerifier != other.codeVerifier)
        #expect(request.scope == "openid" && request.responseType == "code" && request.clientSecret == nil)
        #expect(request.configuration.authorizationEndpoint.absoluteString == "https://accounts.google.com/o/oauth2/v2/auth")
        #expect(request.configuration.tokenEndpoint.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.redirectURL?.absoluteString == "com.googleusercontent.apps.123-publicnative:/oauth2callback")
        let verifier = try #require(request.codeVerifier)
        #expect(request.codeChallenge == TeamDeviceEnrollmentWire.encode(Data(SHA256.hash(data: Data(verifier.utf8)))))
        #expect(request.codeChallengeMethod == "S256")
        let components = try #require(URLComponents(url: request.authorizationRequestURL(), resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(items.filter { $0.name == "nonce" }.map(\.value) == [request.nonce])
        #expect(items.first { $0.name == "prompt" }?.value == "select_account")
        #expect(items.first { $0.name == "include_granted_scopes" }?.value == "false")
        #expect(items.first { $0.name == "audience" }?.value == "123-publicserver.apps.googleusercontent.com")
        #expect(items.first { $0.name == "access_type" }?.value == "online")
    }
    @Test func actualSDKConsumesMatchingRedirectOnceAndReturnsOnlyTheBoundRequest() async throws {
        let request = try await request(), browser = SilentOAuthUserAgent()
        var replies = 0
        let flow = OIDAuthorizationService.present(request, externalUserAgent: browser) { response, error in
            replies += 1
            #expect(error == nil && response?.request === request && response?.authorizationCode == "public-code")
        }
        let state = try #require(request.state), redirect = try #require(request.redirectURL)
        let url = try #require(URL(string: redirect.absoluteString + "?code=public-code&state=" + state))
        try flow.resumeExternalUserAgentFlow(url)
        #expect(replies == 1 && browser.starts == 1 && browser.dismissals == 1)
        #expect(throws: (any Error).self) { try flow.resumeExternalUserAgentFlow(url) }
        #expect(replies == 1)
    }
    @Test func actualSDKWrongStateIsTerminalButForeignRedirectDoesNotConsume() async throws {
        let request = try await request(), browser = SilentOAuthUserAgent()
        var replies = 0
        let flow = OIDAuthorizationService.present(request, externalUserAgent: browser) { response, error in
            replies += 1; #expect(response == nil && error != nil)
        }
        #expect(throws: (any Error).self) { try flow.resumeExternalUserAgentFlow(URL(string: "foreign:/callback?code=public")!) }
        #expect(replies == 0 && browser.dismissals == 0)
        let redirect = try #require(request.redirectURL)
        try flow.resumeExternalUserAgentFlow(URL(string: redirect.absoluteString + "?code=public-code&state=wrong")!)
        #expect(replies == 1 && browser.dismissals == 1)
    }
    @Test func actualSDKCancellationCompletesAfterUserAgentDismissalWithoutNetwork() async throws {
        let request = try await request(), browser = SilentOAuthUserAgent()
        var replies = 0
        let flow = OIDAuthorizationService.present(request, externalUserAgent: browser) { response, error in
            #expect(browser.dismissals == 1)
            #expect(response == nil && (error as NSError?)?.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue)
            replies += 1
        }
        flow.cancel(completion: {})
        #expect(replies == 1)
        let redirect = try #require(request.redirectURL)
        #expect(throws: (any Error).self) { try flow.resumeExternalUserAgentFlow(redirect) }
        #expect(replies == 1)
    }
}
#endif
