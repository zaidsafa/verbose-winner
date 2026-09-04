import Foundation
import CryptoKit
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

private func googleConfiguration(legacy: Bool = false) throws -> TeamGoogleNativeConfiguration {
    try .init(providerID: "public-google-ios", nativeClientID: "123-publicnative.apps.googleusercontent.com",
        serverClientID: "123-publicserver.apps.googleusercontent.com",
        registeredURLSchemes: ["com.googleusercontent.apps.123-publicnative"], allowLegacyIssuer: legacy)
}
private func googleContext() async throws -> TeamNativeSignInContext {
    try await TeamNativeSignInFlow().begin(provider: .google, providerID: "public-google-ios",
        challengeID: tokenA, nonce: tokenB, expiresAt: 1_120_000, now: 1_000_000)
}
private func googleClaims() -> [String: Any] {
    ["iss": "https://accounts.google.com", "aud": "123-publicserver.apps.googleusercontent.com",
     "azp": "123-publicnative.apps.googleusercontent.com", "nonce": tokenB, "sub": "public-subject",
     "iat": 1000, "exp": 4600]
}
private func googleResponse(claims: [String: Any] = googleClaims(),
                            header: [String: Any] = ["alg": "RS256", "kid": "public-key", "typ": "JWT"]) throws -> Data {
    func encoded(_ value: [String: Any]) throws -> String { TeamDeviceEnrollmentWire.encode(try json(value)) }
    // Deliberately UNVERIFIED synthetic token, not an accepted signature/provider proof.
    let token = try encoded(header) + "." + encoded(claims) + ".cHVibGlj"
    return try json(["id_token": token, "access_token": "public-unused-access", "refresh_token": "public-unused-refresh", "token_type": "Bearer", "expires_in": 3600])
}

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
    var beforeDelivery: (@Sendable () -> Void)?
}
private final class OnboardingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_000
    func now() -> Int64 { lock.withLock { value } }
    func set(_ next: Int64) { lock.withLock { value = next } }
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
        plan.beforeDelivery?()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in plan.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if !plan.hangs { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.state.stopped(request.url!.host!) }
}

@Suite(.serialized)
struct TeamOnboardingHTTPTests {
    private func fixture(_ plans: [StubResponse], clock: @escaping @Sendable () -> Int64 = { 1_000 }) throws -> (TeamAuthHTTPClient, String, TeamAccountSessionSnapshot) {
        let host = "onboarding-\(UUID().uuidString.lowercased()).invalid"
        let origin = URL(string: "https://\(host)")!
        AuthStubProtocol.state.configure(host, plans)
        let pair = try TeamAuthWire.pair(pairJSON())
        let snapshot = try TeamAccountSessionCodec.active(pair: pair, scope: .init(origin: origin, providerID: "public-ios"), now: 1_000)
        return (try TeamAuthHTTPClient(origin: origin, protocolClasses: [AuthStubProtocol.self], clock: clock), host, snapshot)
    }
    private func preview(role: String = "MEMBER") -> [String: Any] {
        ["inviteId": "public-invite", "teamId": "public-team", "role": role, "expiresAt": 20_000]
    }
    private func membership(role: String = "MEMBER") -> [String: Any] {
        ["teamId": "public-team", "accountId": "public-account", "enrollmentId": "public-enrollment", "role": role, "membershipRevision": 1]
    }
    private func requestContext(host: String, session: TeamAccountSessionSnapshot,
                                key: TeamDeviceEnrollmentWire.PublicKey,
                                operation: TeamDeviceRequestWire.Operation = .teamAudience) throws
        -> (TeamDeviceRequestWire.Binding, TeamAudienceRevisionRequest, [String: Any]) {
        let request = try TeamAudienceRevisionRequest(membershipRevision: 7)
        let binding = TeamDeviceRequestWire.Binding(audience: "https://\(host)", authorityEpoch: "public-epoch",
            accountID: session.accountID, sessionID: session.sessionID, deviceID: "public-device",
            enrollmentID: "public-enrollment", keyThumbprint: key.thumbprint, operation: operation,
            teamID: "public-team", requestID: "public-request", accessExpiresAt: 10_000)
        let body = Data(#"{"membershipRevision":7}"#.utf8)
        let challenge: [String: Any] = ["audience": binding.audience, "authorityEpoch": binding.authorityEpoch,
            "accountId": binding.accountID, "sessionId": binding.sessionID, "deviceId": binding.deviceID,
            "enrollmentId": binding.enrollmentID, "keyThumbprint": binding.keyThumbprint,
            "operation": binding.operation.rawValue, "teamId": binding.teamID, "requestId": binding.requestID,
            "bodySha256": try TeamDeviceRequestWire.bodySHA256(body), "challengeId": tokenB,
            "nonce": tokenC, "expiresAt": 9_000]
        return (binding, request, challenge)
    }
    private func check(_ host: String, paths: [String], fields: [Set<String>], publicCount: Int = 0) throws {
        let requests = AuthStubProtocol.state.requests(host)
        #expect(requests.map(\.path) == paths.map { "/api/v1/\($0)" })
        #expect(requests.count == fields.count)
        for (index, request) in requests.enumerated() {
            #expect(request.method == "POST")
            #expect(request.header("Authorization") == (index < publicCount ? nil : "Bearer \(tokenA)"))
            #expect(request.header("Cookie") == nil)
            #expect(request.header("Accept-Encoding") == "identity")
            #expect(request.header("Content-Length") == String(request.body.count))
            let object = try TeamStrictJSON.object(request.body)
            #expect(Set(object.keys) == fields[index])
        }
    }
    @Test func invitationAndMembershipRoutesUseExactSchemasAndExplicitRole() async throws {
        var issued = preview(role: "REVIEWER"); issued["token"] = tokenC
        let row: [String: Any] = ["inviteId": "public-invite", "role": "REVIEWER", "state": "PENDING", "expiresAt": 20_000]
        let plans = try [preview(), ["challengeId": tokenA, "nonce": tokenB, "expiresAt": 121_000],
            JSONSerialization.jsonObject(with: pairJSON()) as! [String: Any], membership(role: "OWNER"), membership(),
            membership(role: "REVIEWER"), issued, ["invitations": [row]], ["inviteId": "public-invite", "state": "REVOKED"]].map { StubResponse(chunks: [try json($0)]) }
        let (client, host, session) = try fixture(plans)
        defer { AuthStubProtocol.state.clear(host) }
        #expect(try await client.previewInvitation(token: tokenC).teamID == "public-team")
        let challenge = try await client.invitedChallenge(providerID: "public-ios", token: tokenC, teamID: "public-team", role: .member)
        let flow = TeamNativeSignInFlow()
        let context = try await flow.begin(provider: .apple, providerID: "public-ios", challengeID: challenge.challengeID, nonce: challenge.nonce, expiresAt: challenge.expiresAt, now: 1_000)
        let submission = try await flow.acceptApple(attemptID: context.id, returnedState: context.state, identityToken: Data("public.header.signature".utf8), now: 1_000)
        #expect(try await client.invitedExchange(submission, token: tokenC, teamID: "public-team", role: .member).accountID == session.accountID)
        #expect(try await client.createTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: session).role == .owner)
        #expect(try await client.currentTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: session).role == .member)
        #expect(try await client.acceptInvitation(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .reviewer, session: session).role == .reviewer)
        let invite = try await client.issueInvitation(teamID: "public-team", enrollmentID: "public-enrollment", role: .reviewer, session: session)
        #expect(invite.token == tokenC && !String(reflecting: invite).contains(tokenC))
        #expect(try await client.listInvitations(teamID: "public-team", enrollmentID: "public-enrollment", session: session).count == 1)
        try await client.revokeInvitation(teamID: "public-team", enrollmentID: "public-enrollment", inviteID: "public-invite", session: session)
        try check(host, paths: ["invitations/preview", "auth/invited-challenge", "auth/invited-exchange", "teams/create", "teams/current", "teams/accept", "teams/invites", "teams/invites/list", "teams/invites/revoke"], fields: [["token"], ["providerId", "token", "teamId", "role"], ["providerId", "token", "teamId", "role", "challengeId", "idToken"], ["teamId", "enrollmentId"], ["teamId", "enrollmentId"], ["token", "teamId", "enrollmentId", "role"], ["teamId", "enrollmentId", "role"], ["teamId", "enrollmentId"], ["teamId", "enrollmentId", "inviteId"]], publicCount: 3)
    }
    @Test func acceptanceLookupUsesExactOriginalIdentityAndOnlyExplicitNullIsPending() async throws {
        let (client, host, session) = try fixture([
            StubResponse(chunks: [try json(["membership": NSNull()])]),
            StubResponse(chunks: [try json(["membership": membership(role: "REVIEWER")])])])
        defer { AuthStubProtocol.state.clear(host) }
        #expect(try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .reviewer, session: session) == nil)
        let result = try #require(await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .reviewer, ticket: .init(snapshot: session)))
        #expect(result.role == .reviewer && result.accountID == session.accountID && result.revision == 1)
        #expect(!String(reflecting: result).contains(session.accountID))
        try check(host, paths: ["teams/acceptance", "teams/acceptance"],
            fields: Array(repeating: ["token", "teamId", "enrollmentId", "role"], count: 2))
        for request in AuthStubProtocol.state.requests(host) {
            #expect(try TeamStrictJSON.object(request.body) as? [String: String] == [
                "token": tokenC, "teamId": "public-team", "enrollmentId": "public-enrollment", "role": "REVIEWER"])
        }
        #expect(try session.usablePair(now: 1_000).accessToken == tokenA)
    }
    @Test func acceptanceLookupRejectsMalformedEnvelopeAndForeignMembership() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        var bad: [[String: Any]] = [[:], ["membership": false], ["membership": 0], ["membership": "null"],
            ["membership": []], ["membership": [:]], ["membership": NSNull(), "extra": 1]]
        for field in ["teamId", "accountId", "enrollmentId", "role", "membershipRevision", "extra"] {
            var value = membership(); value[field] = "wrong"
            bad.append(["membership": value])
        }
        bad.append(["membership": membership(role: "OWNER")])
        for object in bad {
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(object)])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) {
                try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
            }
            #expect(AuthStubProtocol.state.requests(host).count == 1)
        }
    }
    @Test func acceptanceLookupRejectsNestedDuplicateKeysUnsafeNumbersAndOversize() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        let valid = #"{"teamId":"public-team","accountId":"public-account","enrollmentId":"public-enrollment","role":"MEMBER","membershipRevision":1}"#
        var invalid = [#"{"membership":null,"\u006dembership":null}"#,
            "{\"membership\":" + valid.replacingOccurrences(of: "\"role\":\"MEMBER\"", with: "\"role\":\"MEMBER\",\"\\u0072ole\":\"MEMBER\"") + "}"]
        for number in ["-1", "1.0", "1e0", "9007199254740992", "true", "null"] {
            invalid.append("{\"membership\":" + valid.replacingOccurrences(of: "\"membershipRevision\":1", with: "\"membershipRevision\":\(number)") + "}")
        }
        for raw in invalid {
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [Data(raw.utf8)])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) {
                try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
            }
        }
        let base = Data(#"{"membership":null}"#.utf8)
        for count in [4096, 4097] {
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [base, Data(repeating: 32, count: count - base.count)])])
            if count == 4096 {
                #expect(try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session) == nil)
            } else {
                await #expect(throws: TeamAuthHTTPError.responseTooLarge) {
                    try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
                }
            }
        }
    }
    @Test func acceptanceHTTPFailuresNeverBecomeNullRetryOrSessionDeletion() async throws {
        for status in [401, 403, 404, 408, 409, 410, 429, 500, 503] {
            // Even a null-shaped body on an HTTP failure must not be interpreted.
            let (client, host, session) = try fixture([StubResponse(status: status, chunks: [try json(["membership": NSNull()])])])
            defer { AuthStubProtocol.state.clear(host) }
            do {
                _ = try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
                Issue.record("HTTP failure became a successful lookup")
            } catch { #expect(error is TeamAuthHTTPError) }
            #expect(AuthStubProtocol.state.requests(host).count == 1)
            #expect(try session.usablePair(now: 1_000).accessToken == tokenA)
        }
    }
    @Test func acceptanceValidatesInputOriginAndAccessBeforeDispatchAndAfterReply() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        for fields in [("bad-token", "public-team", "public-enrollment"), (tokenC, "", "public-enrollment"), (tokenC, "public-team", "../unsafe")] {
            await #expect(throws: TeamAuthHTTPError.invalidRequest) {
                try await client.lookupInvitationAcceptance(token: fields.0, teamID: fields.1, enrollmentID: fields.2, role: .member, session: session)
            }
        }
        let foreign = try TeamAuthHTTPClient(origin: URL(string: "https://other.invalid")!, protocolClasses: [AuthStubProtocol.self], clock: { 1_000 })
        await #expect(throws: TeamAuthHTTPError.invalidRequest) {
            try await foreign.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
        }
        let expired = try TeamAuthHTTPClient(origin: session.scope.origin, protocolClasses: [AuthStubProtocol.self], clock: { 10_000 })
        await #expect(throws: TeamAccountSessionError.reauthenticationRequired) {
            try await expired.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session)
        }
        #expect(AuthStubProtocol.state.requests(host).isEmpty)
        for end: Int64 in [999, 10_000, TeamAuthWire.maximumSafeTime + 1] {
            let clock = OnboardingClock()
            let (timed, target, account) = try fixture([StubResponse(chunks: [try json(["membership": NSNull()])], beforeDelivery: { clock.set(end) })], clock: { clock.now() })
            defer { AuthStubProtocol.state.clear(target) }
            do {
                _ = try await timed.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: account)
                Issue.record("Stale lookup became eligible pending")
            } catch { #expect(error is TeamAuthHTTPError || error is TeamAccountSessionError) }
            #expect(AuthStubProtocol.state.requests(target).count == 1)
        }
    }
    @Test func acceptanceSharesUnresolvedAuthSlotAndCancellationNeverReportsPending() async throws {
        let (client, host, session) = try fixture([StubResponse(chunks: [try json(["membership": NSNull()])], hangs: true), StubResponse(chunks: [try challengeJSON()])])
        defer { AuthStubProtocol.state.clear(host) }
        let work = Task { try await client.lookupInvitationAcceptance(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session) }
        for _ in 0..<100 where AuthStubProtocol.state.requests(host).isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
        await #expect(throws: TeamAuthHTTPError.busy) { try await client.challenge(providerID: "public-ios") }
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(try await client.challenge(providerID: "public-ios").nonce == tokenB)
        #expect(AuthStubProtocol.state.requests(host).map(\.path) == ["/api/v1/teams/acceptance", "/api/v1/auth/challenge"])
    }
    @Test func deviceRoutesBindExactKeyAndOnlyExplicitNullMeansAbsence() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        let key = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let binding = TeamDeviceEnrollmentWire.Binding(audience: "https://\(host)", authorityEpoch: "public-epoch", accountID: session.accountID, sessionID: session.sessionID, deviceID: "public-device", keyThumbprint: key.thumbprint, accessExpiresAt: 10_000)
        let challenge: [String: Any] = ["audience": binding.audience, "authorityEpoch": binding.authorityEpoch, "accountId": binding.accountID, "sessionId": binding.sessionID, "deviceId": binding.deviceID, "keyThumbprint": binding.keyThumbprint, "challengeId": tokenA, "nonce": tokenB, "expiresAt": 9_000]
        let registration: [String: Any] = ["enrollmentId": "public-enrollment", "accountId": binding.accountID, "deviceId": binding.deviceID, "keyThumbprint": binding.keyThumbprint, "authorityEpoch": binding.authorityEpoch]
        AuthStubProtocol.state.configure(host, try [challenge, registration, ["registration": registration], ["registration": NSNull()], ["enrollmentId": "public-enrollment", "active": false]].map { StubResponse(chunks: [try json($0)]) })
        let prepared = try await client.deviceChallenge(key: key, expected: binding, session: session)
        #expect(try prepared.message(expected: binding, now: 1_000).count > 0)
        let result = try await client.completeDevice(challenge: prepared, signature: Data(repeating: 1, count: 64), expected: binding, session: session)
        #expect(result.keyThumbprint == key.thumbprint)
        #expect(try await client.lookupDevice(key: key, expected: binding, session: session)?.enrollmentID == "public-enrollment")
        #expect(try await client.lookupDevice(key: key, expected: binding, session: session) == nil)
        try await client.revokeDevice(enrollmentID: "public-enrollment", session: session)
        try check(host, paths: ["devices/challenge", "devices/complete", "devices/lookup", "devices/lookup", "devices/revoke"], fields: [["deviceId", "publicKey"], ["challengeId", "signature"], ["deviceId", "publicKey"], ["deviceId", "publicKey"], ["enrollmentId"]])
        for object: [String: Any] in [[:], ["registration": false], ["registration": [:]], ["registration": registration, "extra": 1]] {
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(object)])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.lookupDevice(key: key, expected: binding, session: session) }
        }
        for field in ["accountId", "deviceId", "keyThumbprint", "authorityEpoch"] {
            var wrong = registration; wrong[field] = field == "keyThumbprint" ? tokenC : "wrong"
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(["registration": wrong])])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.lookupDevice(key: key, expected: binding, session: session) }
        }
        AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(["enrollmentId": "public-enrollment", "active": 0])])])
        await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.revokeDevice(enrollmentID: "public-enrollment", session: session) }
    }
    @Test func deviceRequestRoutesUseExactNestedSchemaAndReturnBoundAudience() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        let signer = P256.Signing.PrivateKey()
        let key = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let (binding, request, challengeWire) = try requestContext(host: host, session: session, key: key)
        let targetKey = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let targetAgreement = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let target: [String: Any] = ["accountId": "other-account", "deviceId": "other-device",
            "enrollmentId": "other-enrollment", "keyThumbprint": targetKey.thumbprint, "publicKey": targetKey.jwk,
            "agreementKeyThumbprint": targetAgreement.thumbprint, "agreementPublicKey": targetAgreement.jwk]
        let audience: [String: Any] = ["teamId": binding.teamID, "membershipRevision": request.membershipRevision,
            "targets": [target]]
        AuthStubProtocol.state.configure(host, try [challengeWire, audience].map { StubResponse(chunks: [try json($0)]) })
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        let prepared = try await client.deviceRequestChallenge(expected: binding, publicKey: key, request: request, ticket: ticket)
        let raw = try signer.signature(for: prepared.message(expected: binding, publicKey: key,
            request: request, now: 1_000)).rawRepresentation
        let result = try await client.executeDeviceRequest(challenge: prepared, signature: raw,
            expected: binding, publicKey: key, request: request, ticket: ticket)
        #expect(result.teamID == binding.teamID && result.membershipRevision == 7 && result.targets.count == 1)
        #expect(result.targets[0].accountID == "other-account" && result.targets[0].keyThumbprint == targetKey.thumbprint)
        #expect(result.targets[0].agreementKeyThumbprint == targetAgreement.thumbprint)
        #expect(!String(reflecting: result).contains("other-account"))
        try check(host, paths: ["device-requests/challenge", "device-requests/execute"],
            fields: [["enrollmentId", "binding"], ["challengeId", "signature", "body"]])
        let sent = AuthStubProtocol.state.requests(host)
        let begin = try TeamStrictJSON.object(sent[0].body)
        let nested = try #require(begin["binding"] as? [String: Any])
        #expect(Set(nested.keys) == ["operation", "teamId", "requestId", "bodySha256"])
        #expect(begin["enrollmentId"] as? String == binding.enrollmentID)
        let execute = try TeamStrictJSON.object(sent[1].body)
        let encodedBody = try #require(execute["body"] as? String)
        #expect(TeamDeviceEnrollmentWire.decode(encodedBody) == Data(#"{"membershipRevision":7}"#.utf8))
    }
    @Test func deviceRequestAudienceRejectsConfusionDuplicatesAndBadKeys() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        let signer = P256.Signing.PrivateKey()
        let key = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let (binding, request, challengeWire) = try requestContext(host: host, session: session, key: key)
        let targetKey = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let targetAgreement = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let base: [String: Any] = ["accountId": "other-account", "deviceId": "other-device",
            "enrollmentId": "other-enrollment", "keyThumbprint": targetKey.thumbprint, "publicKey": targetKey.jwk,
            "agreementKeyThumbprint": targetAgreement.thumbprint, "agreementPublicKey": targetAgreement.jwk]
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        let preparedData = try json(challengeWire)
        let prepared = try TeamPreparedDeviceRequestChallenge(validating: preparedData, expected: binding,
            publicKey: key, request: request, now: 1_000)
        let raw = try signer.signature(for: prepared.message(expected: binding, publicKey: key,
            request: request, now: 1_000)).rawRepresentation
        var bad = [[String: Any]]()
        bad.append(["teamId": "other-team", "membershipRevision": 7, "targets": [base]])
        bad.append(["teamId": binding.teamID, "membershipRevision": 8, "targets": [base]])
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": Array(repeating: base, count: 10)])
        for field in ["accountId", "deviceId", "enrollmentId"] {
            var duplicate = base; duplicate[field] = base[field]
            var other = base; other["accountId"] = "third-account"; other["deviceId"] = "third-device"; other["enrollmentId"] = "third-enrollment"
            other[field] = base[field]
            bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [duplicate, other]])
        }
        var selfTarget = base; selfTarget["accountId"] = binding.accountID
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [selfTarget]])
        var wrongThumbprint = base; wrongThumbprint["keyThumbprint"] = tokenA
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [wrongThumbprint]])
        var privateKey = targetKey.jwk; privateKey["d"] = tokenA
        var privateTarget = base; privateTarget["publicKey"] = privateKey
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [privateTarget]])
        var missingAgreement = base; missingAgreement["agreementPublicKey"] = nil
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [missingAgreement]])
        var wrongAgreement = base; wrongAgreement["agreementKeyThumbprint"] = tokenA
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [wrongAgreement]])
        var reusedSigning = base
        reusedSigning["agreementKeyThumbprint"] = targetKey.thumbprint
        reusedSigning["agreementPublicKey"] = targetKey.jwk
        bad.append(["teamId": binding.teamID, "membershipRevision": 7, "targets": [reusedSigning]])
        for value in bad {
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(value)])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) {
                try await client.executeDeviceRequest(challenge: prepared, signature: raw,
                    expected: binding, publicKey: key, request: request, ticket: ticket)
            }
        }
    }
    @Test func agreementEnrollmentRoutesSignCanonicalBodyAndRebindExactResult() async throws {
        let (client, host, session) = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        let signer = P256.Signing.PrivateKey()
        let signingKey = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let agreementKey = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let agreement = TeamAgreementPublic(keyThumbprint: agreementKey.thumbprint, publicKey: agreementKey)
        let request = try TeamAgreementEnrollmentRequest(membershipRevision: 7, agreement: agreement)
        let binding = TeamDeviceRequestWire.Binding(audience: "https://\(host)", authorityEpoch: "public-epoch",
            accountID: session.accountID, sessionID: session.sessionID, deviceID: "public-device",
            enrollmentID: "public-enrollment", keyThumbprint: signingKey.thumbprint,
            operation: .agreementEnroll, teamID: "public-team", requestID: "public-agreement-request",
            accessExpiresAt: 10_000)
        let challenge: [String: Any] = ["audience": binding.audience, "authorityEpoch": binding.authorityEpoch,
            "accountId": binding.accountID, "sessionId": binding.sessionID, "deviceId": binding.deviceID,
            "enrollmentId": binding.enrollmentID, "keyThumbprint": binding.keyThumbprint,
            "operation": binding.operation.rawValue, "teamId": binding.teamID, "requestId": binding.requestID,
            "bodySha256": try TeamDeviceRequestWire.bodySHA256(request.body), "challengeId": tokenB,
            "nonce": tokenC, "expiresAt": 9_000]
        let registration: [String: Any] = ["teamId": binding.teamID,
            "membershipRevision": request.membershipRevision, "enrollmentId": binding.enrollmentID,
            "agreementKeyThumbprint": agreement.keyThumbprint, "agreementPublicKey": agreement.publicKey.jwk]
        AuthStubProtocol.state.configure(host, try [challenge, registration].map {
            StubResponse(chunks: [try json($0)])
        })
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        let prepared = try await client.agreementRequestChallenge(expected: binding,
            publicKey: signingKey, request: request, ticket: ticket)
        let signature = try signer.signature(for: prepared.message(expected: binding,
            publicKey: signingKey, request: request, now: 1_000)).rawRepresentation
        let result = try await client.executeAgreementRequest(challenge: prepared, signature: signature,
            expected: binding, publicKey: signingKey, request: request, ticket: ticket)
        #expect(result.teamID == binding.teamID && result.membershipRevision == 7)
        #expect(result.enrollmentID == binding.enrollmentID)
        #expect(result.agreementKeyThumbprint == agreement.keyThumbprint)
        try check(host, paths: ["device-agreements/challenge", "device-agreements/execute"],
            fields: [["enrollmentId", "binding"], ["challengeId", "signature", "body"]])
        let sent = AuthStubProtocol.state.requests(host)
        let execute = try TeamStrictJSON.object(sent[1].body)
        let encoded = try #require(execute["body"] as? String)
        let padded = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - encoded.utf8.count % 4) % 4)
        #expect(Data(base64Encoded: padded) == request.body)
        #expect(String(decoding: request.body, as: UTF8.self).hasPrefix(
            #"{"agreementKey":{"crv":"P-256","kty":"EC","x":"#))

        for field in ["teamId", "membershipRevision", "enrollmentId", "agreementKeyThumbprint", "agreementPublicKey"] {
            var wrong = registration
            if field == "membershipRevision" { wrong[field] = 8 }
            else if field == "agreementKeyThumbprint" { wrong[field] = tokenA }
            else if field == "agreementPublicKey" {
                wrong[field] = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey).jwk
            } else { wrong[field] = "other" }
            AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(wrong)])])
            await #expect(throws: TeamAuthHTTPError.invalidResponse) {
                try await client.executeAgreementRequest(challenge: prepared, signature: signature,
                    expected: binding, publicKey: signingKey, request: request, ticket: ticket)
            }
        }
    }
    @Test func deviceRequestInputsAndPreparedProofRevalidateBeforeDispatch() async throws {
        let clock = OnboardingClock()
        let (client, host, session) = try fixture([], clock: { clock.now() })
        defer { AuthStubProtocol.state.clear(host) }
        let signer = P256.Signing.PrivateKey()
        let key = try TeamDeviceEnrollmentWire.publicKey(signer.publicKey)
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        let (binding, request, challengeWire) = try requestContext(host: host, session: session, key: key)
        let prepared = try TeamPreparedDeviceRequestChallenge(validating: json(challengeWire), expected: binding,
            publicKey: key, request: request, now: 1_000)
        for size in [0, 63, 65] {
            await #expect(throws: TeamAuthHTTPError.invalidRequest) {
                try await client.executeDeviceRequest(challenge: prepared, signature: Data(repeating: 1, count: size),
                    expected: binding, publicKey: key, request: request, ticket: ticket)
            }
        }
        await #expect(throws: TeamAuthHTTPError.invalidRequest) {
            try await client.executeDeviceRequest(challenge: prepared, signature: Data(repeating: 1, count: 64),
                expected: binding, publicKey: key, request: request, ticket: ticket)
        }
        let (_, _, reservedChallenge) = try requestContext(host: host, session: session, key: key, operation: .deliverySubmit)
        let reserved = TeamDeviceRequestWire.Binding(audience: binding.audience, authorityEpoch: binding.authorityEpoch,
            accountID: binding.accountID, sessionID: binding.sessionID, deviceID: binding.deviceID,
            enrollmentID: binding.enrollmentID, keyThumbprint: binding.keyThumbprint, operation: .deliverySubmit,
            teamID: binding.teamID, requestID: binding.requestID, accessExpiresAt: binding.accessExpiresAt)
        AuthStubProtocol.state.configure(host, [StubResponse(chunks: [try json(reservedChallenge)])])
        await #expect(throws: TeamAuthHTTPError.invalidRequest) {
            try await client.deviceRequestChallenge(expected: reserved, publicKey: key, request: request, ticket: ticket)
        }
        clock.set(9_000)
        let validRaw = try signer.signature(for: prepared.message(expected: binding, publicKey: key,
            request: request, now: 1_000)).rawRepresentation
        await #expect(throws: TeamAuthHTTPError.invalidRequest) {
            try await client.executeDeviceRequest(challenge: prepared, signature: validRaw,
                expected: binding, publicKey: key, request: request, ticket: ticket)
        }
        #expect(AuthStubProtocol.state.requests(host).isEmpty)
    }
    @Test func membershipConfusionAndDecodedDuplicateFieldsReject() async throws {
        var wrong = membership(); wrong["accountId"] = "other-account"
        var other = membership(); other["teamId"] = "other-team"
        let (client, host, session) = try fixture(try [wrong, other, membership(role: "OWNER")].map { StubResponse(chunks: [try json($0)]) })
        defer { AuthStubProtocol.state.clear(host) }
        for _ in 0..<3 {
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.acceptInvitation(token: tokenC, teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: session) }
        }
        AuthStubProtocol.state.configure(host, [StubResponse(chunks: [Data(#"{"inviteId":"a","teamId":"public-team","role":"MEMBER","\u0072ole":"REVIEWER","expiresAt":20000}"#.utf8)])])
        await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.previewInvitation(token: tokenC) }
    }
    @Test func onlyListAllowsLargeBoundedResponseAndRejectsDuplicateOrExcessEntries() async throws {
        let rows: [[String: Any]] = (0..<100).map { ["inviteId": "invite-\($0)", "role": "MEMBER", "state": "EXPIRED", "expiresAt": 1] }
        let data = try json(["invitations": rows]); #expect(data.count > 4096)
        let (client, host, session) = try fixture([StubResponse(chunks: [data]), StubResponse(chunks: [data]),
            StubResponse(chunks: [try json(["invitations": rows + [rows[0]]])]),
            StubResponse(chunks: [try json(["invitations": [rows[0], rows[0]]])])])
        defer { AuthStubProtocol.state.clear(host) }
        #expect(try await client.listInvitations(teamID: "public-team", enrollmentID: "public-enrollment", session: session).count == 100)
        await #expect(throws: TeamAuthHTTPError.responseTooLarge) { try await client.previewInvitation(token: tokenC) }
        for _ in 0..<2 {
            await #expect(throws: TeamAuthHTTPError.invalidResponse) { try await client.listInvitations(teamID: "public-team", enrollmentID: "public-enrollment", session: session) }
        }
    }
    @Test func wrongOriginOrExpiredSnapshotNeverDispatchesAndPublicFailureLeavesSessionUsable() async throws {
        let (client, host, session) = try fixture([StubResponse(status: 401, chunks: [try json(["error": "unauthorized"])])])
        defer { AuthStubProtocol.state.clear(host) }
        let otherClient = try TeamAuthHTTPClient(origin: URL(string: "https://other.invalid")!, protocolClasses: [AuthStubProtocol.self], clock: { 1_000 })
        await #expect(throws: TeamAuthHTTPError.invalidRequest) { try await otherClient.currentTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: session) }
        let expiredClient = try TeamAuthHTTPClient(origin: session.scope.origin, protocolClasses: [AuthStubProtocol.self], clock: { 10_000 })
        await #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try await expiredClient.currentTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: session) }
        #expect(AuthStubProtocol.state.requests(host).isEmpty)
        do { _ = try await client.previewInvitation(token: tokenC); Issue.record("Expected public failure") } catch {}
        #expect(try session.usablePair(now: 1_000).accessToken == tokenA)
        #expect(AuthStubProtocol.state.requests(host).count == 1)
    }
    @Test func ordinaryAuthenticationAndOnboardingShareOneUnresolvedSlot() async throws {
        let (client, host, _) = try fixture([StubResponse(hangs: true), StubResponse(chunks: [try json(preview())])])
        defer { AuthStubProtocol.state.clear(host) }
        let operation = Task { try await client.challenge(providerID: "public-ios") }
        for _ in 0..<100 where AuthStubProtocol.state.requests(host).isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
        await #expect(throws: TeamAuthHTTPError.busy) { try await client.previewInvitation(token: tokenC) }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try await client.previewInvitation(token: tokenC).teamID == "public-team")
        #expect(AuthStubProtocol.state.requests(host).count == 2)
    }
    @Test func responseRechecksSessionExpiryAndClockRollbackWithoutRetry() async throws {
        for end: Int64 in [999, 10_000, TeamAuthWire.maximumSafeTime + 1] {
            let clock = OnboardingClock()
            let (client, host, session) = try fixture([StubResponse(chunks: [try json(membership())], beforeDelivery: { clock.set(end) })], clock: { clock.now() })
            defer { AuthStubProtocol.state.clear(host) }
            do { _ = try await client.currentTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: session); Issue.record("Accepted stale response") }
            catch { #expect(error is TeamAuthHTTPError || error is TeamAccountSessionError) }
            #expect(AuthStubProtocol.state.requests(host).count == 1)
        }
        for start: Int64 in [-1, TeamAuthWire.maximumSafeTime + 1] {
            let (client, host, _) = try fixture([], clock: { start })
            defer { AuthStubProtocol.state.clear(host) }
            await #expect(throws: TeamAuthHTTPError.invalidRequest) { try await client.previewInvitation(token: tokenC) }
            #expect(AuthStubProtocol.state.requests(host).isEmpty)
        }
    }
    @Test func preparedProofIsRevalidatedBeforeDispatch() async throws {
        let clock = OnboardingClock()
        let (client, host, session) = try fixture([], clock: { clock.now() })
        defer { AuthStubProtocol.state.clear(host) }
        let key = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let binding = TeamDeviceEnrollmentWire.Binding(audience: "https://\(host)", authorityEpoch: "public-epoch", accountID: session.accountID, sessionID: session.sessionID, deviceID: "public-device", keyThumbprint: key.thumbprint, accessExpiresAt: 10_000)
        let data = try json(["audience": binding.audience, "authorityEpoch": binding.authorityEpoch, "accountId": binding.accountID, "sessionId": binding.sessionID, "deviceId": binding.deviceID, "keyThumbprint": binding.keyThumbprint, "challengeId": tokenA, "nonce": tokenB, "expiresAt": 9_000])
        AuthStubProtocol.state.configure(host, [StubResponse(chunks: [data])])
        let prepared = try await client.deviceChallenge(key: key, expected: binding, session: session)
        for size in [0, 63, 65] {
            await #expect(throws: TeamAuthHTTPError.invalidRequest) { try await client.completeDevice(challenge: prepared, signature: Data(repeating: 1, count: size), expected: binding, session: session) }
        }
        clock.set(9_000)
        await #expect(throws: TeamAuthHTTPError.invalidRequest) { try await client.completeDevice(challenge: prepared, signature: Data(repeating: 1, count: 64), expected: binding, session: session) }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
    }
}

@Suite(.serialized)
struct TeamGoogleTokenClientTests {
    private let host = "oauth2.googleapis.com"
    private func fixture(_ plans: [StubResponse]) throws -> TeamGoogleTokenClient {
        AuthStubProtocol.state.configure(host, plans)
        return TeamGoogleTokenClient(configuration: try googleConfiguration(), protocolClasses: [AuthStubProtocol.self], now: { 1_000_000 })
    }
    @Test func freshCodeUsesPrivateBoundedFormExchangeAndReturnsOnlyIDToken() async throws {
        let response = try googleResponse()
        let headers = ["Content-Type": "application/json", "Cache-Control": "no-cache, no-store, max-age=0"]
        let client = try fixture([StubResponse(headers: headers, chunks: [response])])
        defer { AuthStubProtocol.state.clear(host) }
        let result = try await client.exchange(code: "4/public+code&x=1", verifier: tokenA, context: googleContext())
        let expected = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
        #expect(String(decoding: result, as: UTF8.self) == expected["id_token"] as? String)
        let requests = AuthStubProtocol.state.requests(host)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.path == "/token" && request.method == "POST")
        #expect(request.header("Authorization") == nil && request.header("Cookie") == nil)
        #expect(request.header("Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.header("Accept-Encoding") == "identity")
        let body = String(decoding: request.body, as: UTF8.self)
        #expect(body.contains("code=4%2Fpublic%2Bcode%26x%3D1"))
        #expect(body.contains("redirect_uri=com.googleusercontent.apps.123-publicnative%3A%2Foauth2callback"))
        #expect(body.contains("audience=123-publicserver.apps.googleusercontent.com"))
        #expect(!body.contains("client_secret") && !body.contains("refresh_token") && !body.contains("drive"))
        #expect(request.header("Content-Length") == String(request.body.count))
    }
    @Test func exactClientRedirectConfigurationRequiredBeforeAnyRequest() throws {
        let valid = try googleConfiguration()
        #expect(valid.redirectScheme == "com.googleusercontent.apps.123-publicnative")
        #expect(!valid.allowLegacyIssuer)
        for native in ["", "native", "UPPER.apps.googleusercontent.com", "bad/host.apps.googleusercontent.com", "123-publicserver.apps.googleusercontent.com"] {
            #expect(throws: TeamGoogleIdentityError.invalidConfiguration) {
                try TeamGoogleNativeConfiguration(providerID: "public-google-ios", nativeClientID: native,
                    serverClientID: valid.serverClientID, registeredURLSchemes: [valid.redirectScheme])
            }
        }
        #expect(throws: TeamGoogleIdentityError.invalidConfiguration) {
            try TeamGoogleNativeConfiguration(providerID: "public-google-ios", nativeClientID: valid.nativeClientID,
                serverClientID: valid.serverClientID, registeredURLSchemes: [])
        }
    }
    @Test func preCancelledOrMalformedCodeNeverContactsProvider() async throws {
        let context = try await googleContext()
        let client = try fixture([])
        defer { AuthStubProtocol.state.clear(host) }
        for code in ["", "line\nbreak", String(repeating: "A", count: 4097)] {
            await #expect(throws: TeamGoogleIdentityError.invalidContext) { try await client.exchange(code: code, verifier: tokenA, context: context) }
        }
        await #expect(throws: TeamGoogleIdentityError.invalidContext) { try await client.exchange(code: "public", verifier: "short", context: context) }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await client.exchange(code: "public", verifier: tokenA, context: context) }
        }
        await operation.value
        #expect(AuthStubProtocol.state.requests(host).isEmpty)
    }
    @Test func failureOversizeAndUnsafeResponseNeverRetryOrExposeRawErrors() async throws {
        let context = try await googleContext()
        let plans = [StubResponse(status: 503, chunks: [try json(["error": "public-sensitive-detail"]) ]),
            StubResponse(chunks: [Data(repeating: 32, count: 32_769)]),
            StubResponse(headers: ["Content-Type": "application/json"], chunks: [try googleResponse()]),
            StubResponse(headers: safeHeaders.merging(["Set-Cookie": "public-cookie"]) { _, new in new }, chunks: [try googleResponse()])]
        for plan in plans {
            let client = try fixture([plan])
            do {
                _ = try await client.exchange(code: "public", verifier: tokenA, context: context)
                Issue.record("Unsafe Google response accepted")
            } catch {
                #expect(error as? TeamGoogleIdentityError == .failed)
                #expect(!String(reflecting: error).contains("public-sensitive-detail"))
            }
            #expect(AuthStubProtocol.state.requests(host).count == 1)
            AuthStubProtocol.state.clear(host)
        }
    }
    @Test func unverifiedClaimsStillRequireExactNonceIssuerAudiencePresenterAndFreshness() async throws {
        let config = try googleConfiguration(), context = try await googleContext()
        var variants = [[String: Any]]()
        for (key, value): (String, Any) in [("iss", "https://other.example"), ("iss", "accounts.google.com"),
            ("aud", config.nativeClientID), ("aud", [config.serverClientID]), ("azp", config.serverClientID),
            ("azp", NSNull()), ("nonce", tokenA), ("sub", "\nprivate"), ("iat", true),
            ("iat", 1000.5), ("iat", 1001), ("iat", 998), ("exp", 1000), ("exp", "4600")] {
            var claims = googleClaims(); claims[key] = value; variants.append(claims)
        }
        for claims in variants {
            #expect(throws: TeamGoogleIdentityError.invalidCredential) {
                try TeamGoogleTokenClient.identityToken(googleResponse(claims: claims), configuration: config, context: context, now: 1_000_000)
            }
        }
        for header: [String: Any] in [["alg": "HS256", "kid": "public"], ["alg": "RS256", "kid": "public", "jku": "https://other.example"], ["alg": "RS256"]] {
            #expect(throws: TeamGoogleIdentityError.invalidCredential) {
                try TeamGoogleTokenClient.identityToken(googleResponse(header: header), configuration: config, context: context, now: 1_000_000)
            }
        }
        var legacy = googleClaims(); legacy["iss"] = "accounts.google.com"
        #expect(try !TeamGoogleTokenClient.identityToken(googleResponse(claims: legacy), configuration: googleConfiguration(legacy: true), context: context, now: 1_000_000).isEmpty)
        for response in [try json(["id_token": "one..three"]), try json(["id_token": "one.two.###"]), Data(repeating: 32, count: 32_769)] {
            #expect(throws: TeamGoogleIdentityError.invalidCredential) { try TeamGoogleTokenClient.identityToken(response, configuration: config, context: context, now: 1_000_000) }
        }
    }
    @Test func cancellationWaitsForNativeTransportSettlement() async throws {
        let context = try await googleContext()
        let client = try fixture([StubResponse(hangs: true)])
        defer { AuthStubProtocol.state.clear(host) }
        let operation = Task { try await client.exchange(code: "public", verifier: tokenA, context: context) }
        for _ in 0..<100 {
            if !AuthStubProtocol.state.requests(host).isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(AuthStubProtocol.state.requests(host).count == 1)
    }
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
        #expect(throws: TeamAuthHTTPError.invalidConfiguration) {
            try TeamAuthHTTPClient(origin: URL(string: "https://localhost")!, protocolClasses: nil, testTransportFailure: { _ in })
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
        // Ordinary auth now shares onboarding's narrower 4 KiB route cap.
        let exact = body + Data(repeating: 32, count: 4096 - body.count)
        let (client, host) = try fixture([StubResponse(chunks: [exact]), StubResponse(chunks: [exact, Data([32])]),
            StubResponse(headers: safeHeaders.merging(["Content-Length": "4097"]) { _, new in new })])
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
