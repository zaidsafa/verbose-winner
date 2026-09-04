#if canImport(AppAuthCore)
import AppAuthCore
#endif

#if canImport(AppAuthCore)
private final class SilentPersonalDriveOAuthUserAgent: NSObject, OIDExternalUserAgent {
    private(set) var starts = 0
    private(set) var dismissals = 0

    func present(_ request: any OIDExternalUserAgentRequest,
                 session: any OIDExternalUserAgentSession) -> Bool {
        starts += 1
        return true
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        dismissals += 1
        completion()
    }
}
#endif
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private struct PersonalDriveTokenPlan: Sendable {
    let result: Result<TeamAuthResponse, Error>
}

private actor PersonalDriveTokenHTTPStub: PersonalGoogleDriveTokenHTTPExecuting {
    private var plans: [PersonalDriveTokenPlan]
    private(set) var requests: [URLRequest] = []

    init(_ plans: [PersonalDriveTokenPlan]) { self.plans = plans }

    func execute(_ request: URLRequest) throws -> TeamAuthResponse {
        requests.append(request)
        guard !plans.isEmpty else { throw PersonalGoogleDriveOAuthError.unavailable }
        return try plans.removeFirst().result.get()
    }
}

private actor BlockingPersonalDriveTokenHTTPStub: PersonalGoogleDriveTokenHTTPExecuting {
    private var continuation: CheckedContinuation<TeamAuthResponse, any Error>?
    private(set) var requestCount = 0

    func execute(_ request: URLRequest) async throws -> TeamAuthResponse {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ response: TeamAuthResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private func personalDriveConfiguration() throws -> PersonalGoogleDriveConfiguration {
    try PersonalGoogleDriveConfiguration(
        clientID: "123-personaldrive.apps.googleusercontent.com",
        registeredURLSchemes: ["com.googleusercontent.apps.123-personaldrive"]
    )
}

private func personalDriveTokenJSON(access: String = String(repeating: "a", count: 32),
                                    refresh: String? = String(repeating: "r", count: 32),
                                    extra: [String: Any] = [:]) throws -> Data {
    var object: [String: Any] = [
        "access_token": access,
        "expires_in": 3_600,
        "scope": GoogleDriveBackupTransport.scope,
        "token_type": "Bearer",
    ]
    if let refresh { object["refresh_token"] = refresh }
    for (key, value) in extra { object[key] = value }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func personalDriveRequestBody(_ request: URLRequest) throws -> Data {
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { throw PersonalGoogleDriveOAuthError.unavailable }
        if count == 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

@Suite(.serialized)
struct PersonalGoogleDriveOAuthTests {
    @Test func exactIOSClientAndRegisteredCallbackAreRequired() throws {
        let valid = try personalDriveConfiguration()
        #expect(valid.redirectScheme == "com.googleusercontent.apps.123-personaldrive")
        #expect(valid.redirectURL.absoluteString ==
                "com.googleusercontent.apps.123-personaldrive:/oauth2callback")
        for client in ["", "native", "UPPER.apps.googleusercontent.com",
                       "bad/host.apps.googleusercontent.com"] {
            #expect(throws: PersonalGoogleDriveOAuthError.invalidConfiguration) {
                try PersonalGoogleDriveConfiguration(
                    clientID: client,
                    registeredURLSchemes: [valid.redirectScheme]
                )
            }
        }
        #expect(throws: PersonalGoogleDriveOAuthError.invalidConfiguration) {
            try PersonalGoogleDriveConfiguration(
                clientID: valid.clientID,
                registeredURLSchemes: []
            )
        }
    }

    #if canImport(AppAuthCore)
    @Test func actualAppAuthRequestIsFreshPKCEOfflineDriveOnlyConsent() throws {
        let configuration = try personalDriveConfiguration()
        let request = try PersonalGoogleDriveOAuthRequest.make(configuration: configuration)
        let other = try PersonalGoogleDriveOAuthRequest.make(configuration: configuration)
        #expect(request.state != other.state)
        #expect(request.codeVerifier != other.codeVerifier)
        #expect(request.scope == GoogleDriveBackupTransport.scope)
        #expect(request.responseType == "code" && request.clientSecret == nil)
        #expect(request.nonce != nil && request.nonce != other.nonce)
        #expect(request.redirectURL == configuration.redirectURL)
        #expect(request.codeChallengeMethod == "S256")
        let items = URLComponents(
            url: request.authorizationRequestURL(), resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        #expect(items.filter { $0.name == "scope" }.map(\.value) ==
                [GoogleDriveBackupTransport.scope])
        #expect(items.first { $0.name == "access_type" }?.value == "offline")
        #expect(items.first { $0.name == "include_granted_scopes" }?.value == "false")
        #expect(items.first { $0.name == "prompt" }?.value == "consent")
        #expect(items.first { $0.name == "openid" } == nil)
    }

    @Test func actualAppAuthConsumesOnlyMatchingCallbackOnceWithoutNetwork() throws {
        let request = try PersonalGoogleDriveOAuthRequest.make(
            configuration: personalDriveConfiguration()
        )
        let browser = SilentPersonalDriveOAuthUserAgent()
        var replies = 0
        let flow = OIDAuthorizationService.present(
            request, externalUserAgent: browser
        ) { response, error in
            replies += 1
            #expect(error == nil && response?.request === request)
            #expect(response?.authorizationCode == "public-code")
        }
        let state = try #require(request.state)
        let redirect = try #require(request.redirectURL)
        let callback = try #require(URL(
            string: redirect.absoluteString + "?code=public-code&state=" + state
        ))
        try flow.resumeExternalUserAgentFlow(callback)
        #expect(replies == 1 && browser.starts == 1 && browser.dismissals == 1)
        #expect(throws: (any Error).self) {
            try flow.resumeExternalUserAgentFlow(callback)
        }
        #expect(replies == 1)
    }
    #endif

    @Test func codeExchangeUsesNoSecretAndReturnsOnlyRedactedBoundedGrant() async throws {
        let stub = PersonalDriveTokenHTTPStub([
            .init(result: .success(.init(status: 200,
                                           body: try personalDriveTokenJSON()))),
        ])
        let client = PersonalGoogleDriveTokenClient(
            configuration: try personalDriveConfiguration(), executor: stub,
            now: { 1_000_000 }
        )
        let verifier = String(repeating: "v", count: 43)
        let grant = try await client.exchange(code: "4/public+code&x=1",
                                              verifier: verifier)
        #expect(grant.accessExpiresAt == 4_600_000)
        #expect(String(reflecting: grant) == "PersonalGoogleDriveGrant(<redacted>)")
        #expect(Mirror(reflecting: grant).children.isEmpty)
        #expect(String(reflecting: try grant.accessToken(now: 1_000_000)) ==
                "GoogleDriveAccessToken(<redacted>)")
        #expect(throws: PersonalGoogleDriveOAuthError.expired) {
            try grant.accessToken(now: 4_600_000)
        }
        #expect(throws: PersonalGoogleDriveOAuthError.expired) {
            try grant.accessToken(now: 999_999)
        }

        let request = try #require(await stub.requests.first)
        #expect(request.url == PersonalGoogleDriveTokenClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        let rawBody = try personalDriveRequestBody(request)
        let body = String(decoding: rawBody, as: UTF8.self)
        #expect(body.contains("code=4%2Fpublic%2Bcode%26x%3D1"))
        #expect(body.contains("code_verifier=" + verifier))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("redirect_uri=com.googleusercontent.apps.123-personaldrive%3A%2Foauth2callback"))
        #expect(!body.contains("client_secret") && !body.contains("openid"))
        #expect(request.value(forHTTPHeaderField: "Content-Length") ==
                String(rawBody.count))
    }

    @Test func refreshRetainsExistingRefreshAuthorityAndUsesExactForm() async throws {
        let firstStub = PersonalDriveTokenHTTPStub([
            .init(result: .success(.init(status: 200,
                                           body: try personalDriveTokenJSON()))),
        ])
        let configuration = try personalDriveConfiguration()
        let firstClient = PersonalGoogleDriveTokenClient(
            configuration: configuration, executor: firstStub, now: { 2_000_000 }
        )
        let first = try await firstClient.exchange(code: "public-code",
                                                   verifier: String(repeating: "x", count: 43))
        let refreshStub = PersonalDriveTokenHTTPStub([
            .init(result: .success(.init(
                status: 200,
                body: try personalDriveTokenJSON(
                    access: String(repeating: "b", count: 32), refresh: nil
                )
            ))),
        ])
        let refreshClient = PersonalGoogleDriveTokenClient(
            configuration: configuration, executor: refreshStub, now: { 3_000_000 }
        )
        let next = try await refreshClient.refresh(first.refresh)
        #expect(next.accessExpiresAt == 6_600_000)
        #expect(String(reflecting: next.refresh) ==
                "PersonalGoogleDriveRefreshToken(<redacted>)")
        let refreshRequest = try #require(await refreshStub.requests.first)
        let body = String(decoding: try personalDriveRequestBody(refreshRequest), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=" + String(repeating: "r", count: 32)))
        #expect(!body.contains("code=") && !body.contains("client_secret"))
    }

    @Test func concurrentTokenRequestsFailBusyWithoutSecondDispatch() async throws {
        let stub = BlockingPersonalDriveTokenHTTPStub()
        let client = PersonalGoogleDriveTokenClient(
            configuration: try personalDriveConfiguration(), executor: stub,
            now: { 1_000_000 }
        )
        let verifier = String(repeating: "v", count: 43)
        let first = Task { try await client.exchange(code: "first", verifier: verifier) }
        while await stub.requestCount == 0 { await Task.yield() }
        await #expect(throws: PersonalGoogleDriveOAuthError.busy) {
            try await client.exchange(code: "second", verifier: verifier)
        }
        #expect(await stub.requestCount == 1)
        await stub.finish(.init(status: 200, body: try personalDriveTokenJSON()))
        _ = try await first.value
    }

    @Test func malformedInputsResponsesAndHTTPFailuresFailClosedWithoutRetry() async throws {
        let empty = PersonalDriveTokenHTTPStub([])
        let client = PersonalGoogleDriveTokenClient(
            configuration: try personalDriveConfiguration(), executor: empty,
            now: { 1_000 }
        )
        for code in ["", "line\nbreak", String(repeating: "c", count: 4_097)] {
            await #expect(throws: PersonalGoogleDriveOAuthError.invalidRequest) {
                try await client.exchange(code: code,
                                          verifier: String(repeating: "v", count: 43))
            }
        }
        #expect(await empty.requests.isEmpty)

        let variants: [Data] = [
            try personalDriveTokenJSON(extra: ["id_token": "private"]),
            try personalDriveTokenJSON(extra: ["scope": "openid"]),
            try personalDriveTokenJSON(extra: ["token_type": "MAC"]),
            try personalDriveTokenJSON(extra: ["expires_in": true]),
            try personalDriveTokenJSON(extra: [
                "refresh_token_expires_in": TeamAuthWire.maximumSafeTime / 1_000 + 1,
            ]),
            try personalDriveTokenJSON(refresh: nil),
            Data("{\"access_token\":\"a\",\"access_token\":\"b\"}".utf8),
        ]
        for body in variants {
            #expect(throws: PersonalGoogleDriveOAuthError.invalidResponse) {
                try PersonalGoogleDriveTokenClient.grant(body, existingRefresh: nil,
                                                         now: 1_000)
            }
        }
        #expect(throws: PersonalGoogleDriveOAuthError.invalidResponse) {
            try PersonalGoogleDriveTokenClient.grant(
                personalDriveTokenJSON(), existingRefresh: nil, now: -1
            )
        }

        for status in [400, 500] {
            let stub = PersonalDriveTokenHTTPStub([
                .init(result: .success(.init(status: status, body: Data()))),
            ])
            let statusClient = PersonalGoogleDriveTokenClient(
                configuration: try personalDriveConfiguration(), executor: stub,
                now: { 1_000 }
            )
            await #expect(throws: PersonalGoogleDriveOAuthError.unavailable) {
                try await statusClient.exchange(
                    code: "public", verifier: String(repeating: "v", count: 43)
                )
            }
            #expect(await stub.requests.count == 1)
        }
    }
}
