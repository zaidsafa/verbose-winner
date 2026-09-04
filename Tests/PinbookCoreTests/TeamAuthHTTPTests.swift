import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private let tokenA = String(repeating: "A", count: 43)
private let tokenB = String(repeating: "B", count: 42) + "A"
private let tokenC = String(repeating: "C", count: 42) + "A"
private let tokenD = String(repeating: "D", count: 42) + "A"
private let safeHeaders = ["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"]

private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
private func challengeJSON() throws -> Data { try json(["challengeId": tokenA, "nonce": tokenB, "expiresAt": 121_000]) }
private func pairJSON(access: String = tokenA, refresh: String = tokenB,
                      account: String = "public-account", session: String = "public-session",
                      expiry: Int64 = 30_000) throws -> Data {
    try json(["accountId": account, "sessionId": session, "accessToken": access, "refreshToken": refresh,
              "accessExpiresAt": 10_000, "sessionExpiresAt": expiry])
}

private struct StubResponse: Sendable {
    var status = 200
    var headers = safeHeaders
    var chunks: [Data] = []
    var hangs = false
    var redirect: URL?
}
private struct CapturedRequest: Sendable {
    let path: String
    let method: String
    let headers: [String: String]
    let body: Data
    func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
}
private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [StubResponse]] = [:]
    private var captured: [String: [CapturedRequest]] = [:]
    private var stops: [String: Int] = [:]
    func configure(_ host: String, _ plans: [StubResponse]) { lock.withLock { responses[host] = plans; captured[host] = []; stops[host] = 0 } }
    func clear(_ host: String) { lock.withLock { responses[host] = nil; captured[host] = nil; stops[host] = nil } }
    func take(_ request: URLRequest, body: Data) -> StubResponse? {
        lock.withLock {
            let host = request.url!.host!
            captured[host, default: []].append(CapturedRequest(path: request.url!.path,
                method: request.httpMethod!, headers: request.allHTTPHeaderFields ?? [:], body: body))
            guard var queue = responses[host], !queue.isEmpty else { return nil }
            let first = queue.removeFirst(); responses[host] = queue
            return first
        }
    }
    func requests(_ host: String) -> [CapturedRequest] { lock.withLock { captured[host] ?? [] } }
    func stopped(_ host: String) { lock.withLock { stops[host, default: 0] += 1 } }
}

private final class AuthStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true } // No test falls through to DNS/network.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while body.count <= 20_000 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let plan = Self.state.take(request, body: body),
              let response = HTTPURLResponse(url: request.url!, statusCode: plan.status,
                httpVersion: "HTTP/1.1", headerFields: plan.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        if let redirect = plan.redirect {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in plan.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if !plan.hangs { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.state.stopped(request.url!.host!) }
}

@Suite(.serialized)
struct TeamAuthHTTPTests {
    private func fixture(_ plans: [StubResponse]) throws -> (TeamAuthHTTPClient, String) {
        let host = "auth-\(UUID().uuidString.lowercased()).invalid"
        AuthStubProtocol.state.configure(host, plans)
        return (try TeamAuthHTTPClient(origin: URL(string: "https://\(host)")!, protocolClasses: [AuthStubProtocol.self]), host)
    }

    @Test func allSixRoutesUseExactFieldsAndScopedAuthorization() async throws {
        let session = try json(["accountId": "public-account", "sessionId": "public-session", "providerId": "public-ios"])
        let (client, host) = try fixture([
            StubResponse(chunks: [challengeJSON()]), StubResponse(chunks: [pairJSON()]),
            StubResponse(chunks: [pairJSON(access: tokenC, refresh: tokenD)]),
            StubResponse(chunks: [session]), StubResponse(status: 204), StubResponse(status: 204)])
        defer { AuthStubProtocol.state.clear(host) }
        let challenge = try await client.challenge(providerID: "public-ios")
        #expect(challenge.nonce == tokenB)
        let flow = TeamNativeSignInFlow()
        let context = try await flow.begin(provider: .apple, providerID: "public-ios",
            challengeID: challenge.challengeID, nonce: challenge.nonce, expiresAt: challenge.expiresAt, now: 1_000)
        let submission = try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
            identityToken: Data("public.header.signature".utf8), now: 2_000)
        let pair = try await client.exchange(submission)
        let next = try await client.refresh(pair)
        #expect(next.accessToken == tokenC)
        let current = try await client.session(for: next)
        #expect(current.accountID == "public-account")
        try await client.logout(refreshToken: next.refreshToken)
        try await client.logoutAll(accessToken: next.accessToken)
        let requests = AuthStubProtocol.state.requests(host)
        #expect(requests.map(\.path) == ["challenge", "exchange", "refresh", "session", "logout", "logout-all"].map { "/api/v1/auth/\($0)" })
        #expect(requests.map(\.method) == ["POST", "POST", "POST", "GET", "POST", "POST"])
        for (index, request) in requests.enumerated() {
            #expect(request.header("Cookie") == nil)
            #expect(request.header("Origin") == nil)
            #expect(request.header("Authorization") == ([3, 5].contains(index) ? "Bearer \(tokenC)" : nil))
        }
        let objects = try requests.enumerated().filter { $0.offset != 3 }.map {
            try #require(JSONSerialization.jsonObject(with: $0.element.body) as? [String: String])
        }
        #expect(objects == [["providerId": "public-ios"], ["providerId": "public-ios", "challengeId": tokenA, "idToken": "public.header.signature"],
            ["refreshToken": tokenB], ["refreshToken": tokenD], [:]])
        #expect(requests[3].body.isEmpty)
        #expect(!String(reflecting: pair).contains(tokenA))
        #expect(Mirror(reflecting: pair).children.isEmpty)
    }

    @Test func configurationRejectsUnsafeOriginsAndAmbientCredentials() throws {
        for raw in ["http://auth.invalid", "https://u:p@auth.invalid", "https://auth.invalid/path", "https://auth.invalid?x=1", "https://auth.invalid/#x", "https://auth.invalid:0"] {
            #expect(throws: TeamAuthHTTPError.invalidConfiguration) { try TeamAuthHTTPClient(origin: URL(string: raw)!) }
        }
        #expect(throws: TeamAuthHTTPError.invalidConfiguration) {
            try TeamAuthHTTPClient(origin: URL(string: "https://auth.invalid")!, protocolClasses: nil, localTestAnchor: Data())
        }
        let configuration = TeamAuthHTTPClient.configuration()
        #expect(configuration.httpCookieStorage == nil && configuration.urlCache == nil && configuration.urlCredentialStorage == nil)
        #expect(!configuration.httpShouldSetCookies && !configuration.waitsForConnectivity)
        #expect(configuration.timeoutIntervalForResource == 15)
        #expect(TeamAuthHTTPClient.authenticationDisposition(NSURLAuthenticationMethodServerTrust) == .performDefaultHandling)
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodClientCertificate, "unknown"] {
            #expect(TeamAuthHTTPClient.authenticationDisposition(method) == .cancelAuthenticationChallenge)
        }
    }

    @Test func unknownFieldsInvalidTypesTimesAndCredentialsFailClosed() throws {
        let valid = try challengeJSON()
        let original = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for replacement: Any in [true, -1, 1.5, "121000", NSNull(), 9_007_199_254_740_992 as Int64] {
            var fields = original; fields["expiresAt"] = replacement
            #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.challenge(json(fields)) }
        }
        var fields = original; fields["extra"] = "public"
        #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.challenge(json(fields)) }
        fields = original; fields["nonce"] = String(repeating: "B", count: 43)
        #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.challenge(json(fields)) }
        for invalid in [Data([0xef, 0xbb, 0xbf]) + valid, Data([0xff]), Data("[]".utf8), Data("null".utf8)] {
            #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.challenge(invalid) }
        }
        #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.pair(pairJSON(refresh: tokenA)) }
    }

    @Test func actualBodyCapAppliesWithoutContentLengthAndAtExactBoundary() async throws {
        let body = try challengeJSON()
        let exact = body + Data(repeating: 32, count: TeamAuthWire.maximumResponseBytes - body.count)
        let (client, host) = try fixture([StubResponse(chunks: [exact]), StubResponse(chunks: [exact, Data([32])]),
            StubResponse(headers: safeHeaders.merging(["Content-Length": "32769"]) { _, new in new })])
        defer { AuthStubProtocol.state.clear(host) }
        _ = try await client.challenge(providerID: "public-ios")
        for _ in 0..<2 {
            await #expect(throws: TeamAuthHTTPError.responseTooLarge) { try await client.challenge(providerID: "public-ios") }
        }
        #expect(AuthStubProtocol.state.requests(host).count == 3)
    }

    @Test func metadataRedirectAndMalformedResponsesNeverProduceCredentials() async throws {
        var noCache = safeHeaders; noCache["Cache-Control"] = nil
        let plans = [StubResponse(headers: noCache, chunks: [try challengeJSON()]),
            StubResponse(headers: safeHeaders.merging(["Set-Cookie": "public=value"]) { _, new in new }),
            StubResponse(chunks: [Data("not-json".utf8)]),
            StubResponse(status: 302, redirect: URL(string: "https://other.invalid/steal"))]
        let (client, host) = try fixture(plans)
        defer { AuthStubProtocol.state.clear(host); AuthStubProtocol.state.clear("other.invalid") }
        for _ in 0..<3 {
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.challenge(providerID: "public-ios") }
        }
        await #expect(throws: TeamAuthHTTPError.redirectRefused) { try await client.challenge(providerID: "public-ios") }
        #expect(AuthStubProtocol.state.requests("other.invalid").isEmpty)
    }

    @Test func refreshRejectsAccountFamilyExpiryAndTokenReuseWithoutRetry() async throws {
        let old = try TeamAuthWire.pair(pairJSON())
        let (client, host) = try fixture([
            StubResponse(chunks: [pairJSON(access: tokenC, refresh: tokenD, account: "another-account")]),
            StubResponse(chunks: [pairJSON(access: tokenC, refresh: tokenD, session: "another-family")]),
            StubResponse(chunks: [pairJSON(access: tokenC, refresh: tokenD, expiry: 30_001)]),
            StubResponse(chunks: [pairJSON()]),
            StubResponse(chunks: [pairJSON(access: tokenB, refresh: tokenA)]),
            StubResponse(chunks: [pairJSON(access: tokenC, refresh: tokenA)]),
            StubResponse(chunks: [pairJSON(access: tokenB, refresh: tokenD)]),
            StubResponse(status: 503, chunks: [json(["error": "uncertain"])])])
        defer { AuthStubProtocol.state.clear(host) }
        for _ in 0..<7 {
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.refresh(old) }
        }
        await #expect(throws: TeamAuthHTTPError.server(.uncertain)) { try await client.refresh(old) }
        #expect(AuthStubProtocol.state.requests(host).count == 8)
    }

    @Test func fixedErrorCodesRequireMatchingStatusAndNeverExposeRawBodies() throws {
        let cases: [(Int, TeamAuthServerError)] = [(400, .invalidRequest), (415, .jsonRequired), (413, .requestTooLarge),
            (404, .notFound), (408, .requestTimeout), (401, .invalidCredentials), (429, .capacity), (503, .unavailable), (503, .uncertain)]
        for (status, code) in cases {
            #expect(try TeamAuthWire.serverError(json(["error": code.rawValue]), status: status) == .server(code))
            #expect(try TeamAuthWire.serverError(json(["error": code.rawValue]), status: 500) == .invalidResponse)
        }
        #expect(try TeamAuthWire.serverError(json(["error": tokenA]), status: 503) == .invalidResponse)
    }

    @Test func cancellationBeforeAndDuringRequestDoesNotRetry() async throws {
        let (client, host) = try fixture([StubResponse(hangs: true)])
        defer { AuthStubProtocol.state.clear(host) }
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await client.challenge(providerID: "public-ios") }
        }
        await early.value
        #expect(AuthStubProtocol.state.requests(host).isEmpty)
        let active = Task { try await client.challenge(providerID: "public-ios") }
        for _ in 0..<100 {
            if !AuthStubProtocol.state.requests(host).isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
        active.cancel()
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
    }
}
