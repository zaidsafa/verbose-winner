#if os(macOS) && SWIFT_PACKAGE
import Foundation
import CryptoKit
import Testing
@testable import PinbookCore

/// Runs real Foundation/CFNetwork over private localhost TLS, without modifying
/// system trust. Certificates exist only in a fresh temporary fixture directory.
@Suite(.serialized)
struct TeamAuthTLSTests {
    private final class TransportDiagnostics: @unchecked Sendable {
        private let lock = NSLock()
        private var codes = [TeamAuthTestFailure]()
        func record(_ code: TeamAuthTestFailure) { lock.withLock { if codes.count < 32 { codes.append(code) } } }
        var values: [TeamAuthTestFailure] { lock.withLock { codes } }
    }
    private final class ProcessExit: @unchecked Sendable {
        private let lock = NSLock()
        private let signal = DispatchSemaphore(value: 0)
        private var exited = false
        func observe(_ process: Process) {
            process.terminationHandler = { [self] _ in
                lock.withLock { exited = true }; signal.signal()
            }
        }
        func wait(seconds: Double) -> Bool {
            if lock.withLock({ exited }) { return true }
            return signal.wait(timeout: .now() + seconds) == .success
        }
        func stop(_ process: Process) -> Bool {
            if lock.withLock({ exited }) { return true }
            if process.isRunning { process.terminate() }
            return wait(seconds: 5)
        }
    }
    private final class Fixture {
        let directory: URL
        let server: Process
        let origin: URL
        let anchor: Data
        let diagnostics = TransportDiagnostics()
        let mode: String
        private let serverExit = ProcessExit()

        init(mode: String) async throws {
            self.mode = mode
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-auth-tls-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            self.directory = directory
            let server = Process()
            self.server = server
            do {
                let openssl = Process()
                let opensslExit = ProcessExit()
                opensslExit.observe(openssl)
                openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
                openssl.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                    "-addext", "basicConstraints=critical,CA:TRUE",
                    "-addext", "extendedKeyUsage=serverAuth",
                    "-keyout", directory.appendingPathComponent("private.pem").path,
                    "-out", directory.appendingPathComponent("certificate.pem").path]
                openssl.standardOutput = FileHandle.nullDevice; openssl.standardError = FileHandle.nullDevice
                try openssl.run()
                guard opensslExit.wait(seconds: 10) else {
                    _ = opensslExit.stop(openssl); throw FixtureError.setup
                }
                guard openssl.terminationStatus == 0 else { throw FixtureError.setup }
                let pem = try String(contentsOf: directory.appendingPathComponent("certificate.pem"), encoding: .utf8)
                let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
                anchor = try #require(Data(base64Encoded: base64))
                let script = try #require(Bundle.module.url(forResource: "auth_tls_fixture", withExtension: "py", subdirectory: "Fixtures"))
                server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                server.arguments = [script.path, directory.path, mode]
                server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
                serverExit.observe(server)
                try server.run()
                let portURL = directory.appendingPathComponent("port")
                for _ in 0..<150 {
                    if FileManager.default.fileExists(atPath: portURL.path) { break }
                    guard server.isRunning else { throw FixtureError.setup }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let port = try String(contentsOf: portURL, encoding: .utf8)
                origin = try Self.origin(forPort: port)
            } catch {
                if !server.isRunning || serverExit.stop(server) { try? FileManager.default.removeItem(at: directory) }
                throw error
            }
        }
        static func origin(forPort raw: String) throws -> URL {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let port = Int(raw), (1...65_535).contains(port), String(port) == raw,
                  let url = URL(string: "https://localhost:\(port)"), url.port == port else {
                throw FixtureError.setup
            }
            return url
        }
        deinit {
            let errors = diagnostics.values
            if !errors.isEmpty { print("Private localhost TLS fixture \(mode): \(errors)") }
            if serverExit.stop(server) { try? FileManager.default.removeItem(at: directory) }
            else { Issue.record("Synthetic TLS server did not confirm exit; retained its private fixture directory") }
        }
        func client() throws -> TeamAuthHTTPClient {
            try TeamAuthHTTPClient(origin: origin, protocolClasses: nil, localTestAnchor: anchor,
                testTransportFailure: { [diagnostics] in diagnostics.record($0) }, clock: { 1_000 })
        }
        func records(_ name: String) throws -> [[String: Any]] {
            let url = directory.appendingPathComponent(name + ".jsonl")
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
        }
    }
    private enum FixtureError: Error { case setup }
    private actor SignInTransportTrace: TeamAccountSigningIn {
        let client: TeamAuthHTTPClient
        private(set) var failures = [String]()
        init(_ client: TeamAuthHTTPClient) { self.client = client }
        func challenge(providerID: String) async throws -> TeamAuthChallenge {
            do { return try await client.challenge(providerID: providerID) }
            catch { failures.append("challenge: \(error as? TeamAuthHTTPError ?? .transport)"); throw error }
        }
        func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair {
            do { return try await client.exchange(submission) }
            catch { failures.append("exchange: \(error as? TeamAuthHTTPError ?? .transport)"); throw error }
        }
    }
    private var pair: TeamAuthSessionPair {
        TeamAuthSessionPair(accountID: "public-account", sessionID: "public-session",
            accessToken: String(repeating: "A", count: 43), refreshToken: String(repeating: "B", count: 42) + "A",
            accessExpiresAt: 10_000, sessionExpiresAt: 30_000)
    }

    @Test func fixtureRejectsIncompleteOrInvalidPortPublication() throws {
        // Previously file existence could race with write_text and publish "";
        // Foundation accepts that URL but silently loses the intended port.
        #expect(URL(string: "https://localhost:")?.port == nil)
        for raw in ["", " ", "0", "65536", "443\n", "+123", "01", "1.0", "localhost"] {
            #expect(throws: FixtureError.setup) { try Fixture.origin(forPort: raw) }
        }
        for port in [1, 443, 49_152, 65_535] {
            #expect(try Fixture.origin(forPort: String(port)).port == port)
        }
    }
    @Test func tlsTrustAndActualPostBody() async throws {
        let fixture = try await Fixture(mode: "success")
        let untrusted = try TeamAuthHTTPClient(origin: fixture.origin)
        await #expect(throws: TeamAuthHTTPError.transport) { try await untrusted.challenge(providerID: "public-ios") }
        #expect(try fixture.records("attempts").isEmpty)
        let client = try fixture.client()
        let next = try await client.refresh(pair)
        #expect(next.refreshToken != pair.refreshToken)
        #expect(try fixture.records("attempts").count == 1)
        let body = try #require(fixture.records("bodies").first?["body"] as? String)
        #expect(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String] == ["refreshToken": pair.refreshToken])
    }

    @Test func onboardingUsesActualTLSBodiesScopedBearerAndBoundedList() async throws {
        let fixture = try await Fixture(mode: "success")
        let client = try fixture.client()
        let snapshot = try TeamAccountSessionCodec.active(pair: pair,
            scope: .init(origin: fixture.origin, providerID: "public-ios"), now: 1_000)
        let invitation = String(repeating: "E", count: 42) + "A"
        #expect(try await client.previewInvitation(token: invitation).role == .member)
        #expect(try await client.currentTeam(teamID: "public-team", enrollmentID: "public-enrollment", session: snapshot).role == .member)
        #expect(try await client.listInvitations(teamID: "public-team", enrollmentID: "public-enrollment", session: snapshot).count == 100)
        let attempts = try fixture.records("attempts")
        #expect(attempts.compactMap { $0["path"] as? String } == ["/api/v1/invitations/preview", "/api/v1/teams/current", "/api/v1/teams/invites/list"])
        #expect(attempts.first?["authorization"] is NSNull)
        #expect(attempts.dropFirst().allSatisfy { $0["authorization"] as? String == "Bearer \(pair.accessToken)" })
        let bodies = try fixture.records("bodies")
        #expect(bodies.count == 3)
        let raw = try #require(bodies.first?["body"] as? String)
        #expect(try TeamStrictJSON.object(Data(raw.utf8))["token"] as? String == invitation)
    }

    @Test func acceptanceLookupUsesRealTLSAndNeverTurnsUncertaintyIntoPending() async throws {
        for mode in ["success", "acceptance-pending", "503", "drop"] {
            let fixture = try await Fixture(mode: mode), client = try fixture.client()
            let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
            let backend = SessionMemoryKeychain(), store = TeamAccountSessionStore(testService: "acceptance-tls", keychain: backend)
            let snapshot = try store.saveInitial(pair, scope: scope, now: 1_000, consent: true)
            let savedBytes = backend.bytes, savedWrites = backend.writes
            let invitation = String(repeating: "E", count: 42) + "A"
            if mode == "success" || mode == "acceptance-pending" {
                let result = try await client.lookupInvitationAcceptance(token: invitation, teamID: "public-team",
                    enrollmentID: "public-enrollment", role: .member, ticket: .init(snapshot: snapshot))
                if mode == "success" { #expect(result?.accountID == pair.accountID && result?.role == .member && result?.revision == 1) }
                else { #expect(result == nil) }
            } else {
                do {
                    _ = try await client.lookupInvitationAcceptance(token: invitation, teamID: "public-team",
                        enrollmentID: "public-enrollment", role: .member, ticket: .init(snapshot: snapshot))
                    Issue.record("Uncertain TLS response became a successful acceptance lookup")
                } catch { #expect(error is TeamAuthHTTPError) }
            }
            let attempts = try fixture.records("attempts"), bodies = try fixture.records("bodies")
            #expect(attempts.count == 1 && bodies.count == 1)
            #expect(attempts.first?["path"] as? String == "/api/v1/teams/acceptance")
            #expect(attempts.first?["authorization"] as? String == "Bearer \(pair.accessToken)")
            let raw = try #require(bodies.first?["body"] as? String)
            #expect(try TeamStrictJSON.object(Data(raw.utf8)) as? [String: String] == [
                "token": invitation, "teamId": "public-team", "enrollmentId": "public-enrollment", "role": "MEMBER"])
            #expect(backend.bytes == savedBytes && backend.writes == savedWrites)
            #expect(!String(decoding: try #require(backend.bytes), as: UTF8.self).contains(invitation))
        }
    }

    @Test func invitationConsentUsesActualTLSWithoutImplicitMembershipOrSavedCode() async throws {
        let fixture = try await Fixture(mode: "success"), client = try fixture.client()
        let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
        let backend = SessionMemoryKeychain()
        let store = TeamAccountSessionStore(testService: "invitation-consent-tls", keychain: backend)
        let instant = ContinuousClock.now
        let owner = TeamInvitedSignIn(provider: .apple, scope: scope, sessions: store,
            identity: SyntheticAppleIdentity(), transport: client,
            clock: { .init(wallTime: 1_000, instant: instant) })
        let code = String(repeating: "E", count: 42) + "A"
        let display = try await owner.preview(code: code)
        #expect(backend.writes == 0)
        let consent = try await owner.confirmAccountAccess(display, agreed: true)
        let intent = try await owner.signIn(consent)
        try store.requireCurrentAccess(intent.account, now: 1_000)
        #expect(intent.teamID == "public-team" && intent.role == .member && intent.token == code)
        let requests = try fixture.records("attempts")
        #expect(requests.compactMap { $0["path"] as? String } == ["/api/v1/invitations/preview",
            "/api/v1/auth/invited-challenge", "/api/v1/auth/invited-exchange"])
        #expect(requests.allSatisfy { $0["authorization"] is NSNull })
        let bodies = try fixture.records("bodies")
        #expect(bodies.count == 3)
        let decoded = try bodies.map { row in
            try TeamStrictJSON.object(Data((try #require(row["body"] as? String)).utf8))
        }
        #expect(decoded.allSatisfy { $0["token"] as? String == code })
        #expect(decoded.dropFirst().allSatisfy { $0["teamId"] as? String == "public-team" && $0["role"] as? String == "MEMBER" })
        let exchanged = try #require(decoded.last)
        #expect(Set(exchanged.keys) == ["providerId", "token", "teamId", "role", "challengeId", "idToken"])
        #expect(exchanged["idToken"] as? String == "public.header.signature")
        let saved = try #require(backend.bytes)
        #expect(!String(decoding: saved, as: UTF8.self).contains(code))
        await #expect(throws: TeamInvitationAccountError.staleConsent) { try await owner.signIn(consent) }
        #expect(try fixture.records("attempts").count == 3)
    }

    @Test func ambiguousOnboardingNeverAutomaticallyReplaysOrMutatesSavedAccount() async throws {
        for mode in ["503", "drop"] {
            let fixture = try await Fixture(mode: mode)
            let client = try fixture.client()
            let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
            let store = TeamAccountSessionStore(testService: "onboarding-tls", keychain: SessionMemoryKeychain())
            let snapshot = try store.saveInitial(pair, scope: scope, now: 1_000, consent: true)
            do {
                _ = try await client.acceptInvitation(token: String(repeating: "E", count: 42) + "A", teamID: "public-team", enrollmentID: "public-enrollment", role: .member, session: snapshot)
                Issue.record("Expected ambiguous invitation result")
            } catch { #expect(error is TeamAuthHTTPError) }
            try await Task.sleep(for: .milliseconds(150))
            #expect(try fixture.records("attempts").count == 1)
            #expect(try fixture.records("bodies").count == 1)
            #expect(try store.load(scope: scope)?.usablePair(now: 1_000) == pair)
        }
    }

    @Test(arguments: ["join-uncertain", "retry-pending-once"])
    func membershipOwnerUsesTLSAndKeepsRecoverySeparateFromExplicitRetry(mode: String) async throws {
        let fixture = try await Fixture(mode: mode), client = try fixture.client()
        let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
        let sessions = TeamAccountSessionStore(testService: "membership-tls-account", keychain: SessionMemoryKeychain())
        let account = try TeamAccountAccessTicket(snapshot: sessions.saveInitial(pair, scope: scope, now: 1_000, consent: true))
        let instant = ContinuousClock.now
        let deviceMetadata = try KeychainTeamDeviceMetadata(testService: "pinbook.device-test.membership-tls", keychain: SessionMemoryKeychain())
        let custody = TeamDeviceCustody(storage: deviceMetadata, keys: DeviceFixtureKeys(), clock: { 1_000 })
        let registration = try TeamDeviceRegistration(scope: scope, authorityEpoch: "public-epoch", sessions: sessions,
            devices: TeamRegistrationCustodyDriver(custody: custody), transport: client,
            clock: { .init(wallTime: 1_000, instant: instant) })
        guard case .registered = try await registration.register(consent: true) else { throw FixtureError.setup }
        let invitation = TeamInvitedSignIn(provider: .apple, scope: scope, sessions: sessions, identity: SyntheticAppleIdentity(),
            transport: client, clock: { .init(wallTime: 1_000, instant: instant) })
        let code = String(repeating: "E", count: 42) + "A"
        let preview = try await invitation.preview(code: code), intent = try await invitation.existingAccountIntent(preview)
        let joinBackend = SessionMemoryKeychain()
        let joins = TeamJoinStore(storage: try KeychainTeamJoinMetadata(testService: "pinbook.join-test.membership-tls", keychain: joinBackend), clock: { 1_000 })
        let owner = try TeamMembershipJoin(account: account, authorityEpoch: "public-epoch", sessions: sessions,
            devices: TeamMembershipDeviceDriver(custody: custody), metadata: TeamMembershipMetadataDriver(store: joins),
            transport: client, clock: { .init(wallTime: 1_000, instant: instant) })
        let display = try await owner.prepare(intent)
        #expect(joinBackend.writes == 0)
        await #expect(throws: TeamMembershipJoinError.transportFailure) { try await owner.join(display, consent: true) }
        let deviceScope = try TeamDeviceScope(audience: fixture.origin.absoluteString, accountID: account.accountID, authorityEpoch: "public-epoch")
        #expect(try joins.load(scope: deviceScope, teamID: intent.teamID)?.phase == .pending)
        await owner.close()
        let reopened = try TeamMembershipJoin(account: account, authorityEpoch: "public-epoch", sessions: sessions,
            devices: TeamMembershipDeviceDriver(custody: custody), metadata: TeamMembershipMetadataDriver(store: joins),
            transport: client, clock: { .init(wallTime: 1_000, instant: instant) })
        let result: TeamJoinSnapshot
        if mode == "retry-pending-once" {
            guard case .ready(let retry) = try await reopened.prepareRetry(token: code, teamID: intent.teamID, role: intent.role) else {
                Issue.record("Expected new explicit retry consent"); return
            }
            #expect(joinBackend.writes == 2)
            await #expect(throws: TeamMembershipJoinError.consentRequired) { try await reopened.join(retry, consent: false) }
            #expect(try fixture.records("attempts").filter { $0["path"] as? String == "/api/v1/teams/accept" }.count == 1)
            result = try await reopened.join(retry, consent: true)
            #expect(joinBackend.writes == 4)
        } else { result = try await reopened.recover(teamID: intent.teamID) }
        #expect(result.phase == .confirmed && result.role == .member)
        let expectedPaths = mode == "retry-pending-once"
            ? ["devices/lookup", "devices/lookup", "teams/accept", "devices/lookup", "teams/acceptance", "devices/lookup", "teams/accept"]
            : ["devices/lookup", "devices/lookup", "teams/accept", "devices/lookup", "teams/current"]
        let requests = try fixture.records("attempts").suffix(expectedPaths.count)
        #expect(requests.compactMap { $0["path"] as? String } == expectedPaths.map { "/api/v1/" + $0 })
        #expect(requests.allSatisfy { $0["authorization"] as? String == "Bearer \(account.accessToken)" })
        let body = try #require(fixture.records("bodies").last?["body"] as? String)
        let fields = try TeamStrictJSON.object(Data(body.utf8))
        #expect(Set(fields.keys) == (mode == "retry-pending-once" ? ["token", "teamId", "enrollmentId", "role"] : ["teamId", "enrollmentId"]))
        #expect(fields["teamId"] as? String == result.teamID && fields["enrollmentId"] as? String == result.enrollmentID)
        if mode == "retry-pending-once" {
            let originalFields: [String: String] = ["token": code, "teamId": result.teamID, "enrollmentId": result.enrollmentID, "role": "MEMBER"]
            let allRequests = try fixture.records("attempts"), allBodies = try fixture.records("bodies")
            #expect(allRequests.count == allBodies.count)
            for (request, body) in zip(allRequests, allBodies) where request["path"] as? String == "/api/v1/teams/accept" {
                let raw = try #require(body["body"] as? String)
                #expect(try TeamStrictJSON.object(Data(raw.utf8)) as? [String: String] == originalFields)
            }
        }
        #expect(!String(decoding: try #require(joinBackend.bytes), as: UTF8.self).contains(code))
        try sessions.requireCurrentAccess(account, now: 1_000)
    }

    @Test func deviceCustodyComposesWithActualTLSAndTransmittedSignatureVerifies() async throws {
        let fixture = try await Fixture(mode: "success"), client = try fixture.client()
        let scope = try TeamDeviceScope(audience: fixture.origin.absoluteString, accountID: pair.accountID, authorityEpoch: "public-epoch")
        let metadata = try KeychainTeamDeviceMetadata(testService: "pinbook.device-test.tls", keychain: SessionMemoryKeychain())
        let custody = TeamDeviceCustody(storage: metadata, keys: DeviceFixtureKeys(), clock: { 1_000 })
        let ready = try custody.prepare(scope: scope, consent: true), key = try #require(ready.publicKey)
        let session = try TeamAccountSessionCodec.active(pair: pair, scope: .init(origin: fixture.origin, providerID: "public-ios"), now: 1_000)
        let binding = TeamDeviceEnrollmentWire.Binding(audience: scope.audience, authorityEpoch: scope.authorityEpoch,
            accountID: scope.accountID, sessionID: pair.sessionID, deviceID: ready.deviceID, keyThumbprint: key.thumbprint, accessExpiresAt: pair.accessExpiresAt)
        #expect(try await client.lookupDevice(key: key, expected: binding, session: session) == nil)
        let challenge = try await client.deviceChallenge(key: key, expected: binding, session: session)
        let proof = try custody.signForSubmission(ready, challenge: challenge, binding: binding)
        #expect(try custody.load(scope: scope)?.phase == .submitPending)
        let registration = try await client.completeDevice(challenge: challenge, signature: proof.signature, expected: binding, session: session)
        #expect(try custody.recordRegistration(proof.pending, registration: registration).phase == .registered)
        let attempts = try fixture.records("attempts")
        #expect(attempts.compactMap { $0["path"] as? String } == ["/api/v1/devices/lookup", "/api/v1/devices/challenge", "/api/v1/devices/complete"])
        #expect(attempts.allSatisfy { $0["authorization"] as? String == "Bearer \(pair.accessToken)" })
        let bodyString = try #require(fixture.records("bodies").last?["body"] as? String)
        let fields = try TeamStrictJSON.object(Data(bodyString.utf8))
        let raw = try #require((fields["signature"] as? String).flatMap(TeamDeviceEnrollmentWire.decode))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        #expect(try key.key.isValidSignature(signature, for: challenge.message(expected: binding, now: 1_000)))
        #expect(raw.count == 64 && raw == proof.signature)
    }

    @Test func accountBoundRegistrationOwnerUsesTLSAndFreshLookupOnRepeat() async throws {
        let fixture = try await Fixture(mode: "success"), client = try fixture.client()
        let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
        let sessions = TeamAccountSessionStore(testService: "registration-owner-tls", keychain: SessionMemoryKeychain())
        _ = try sessions.saveInitial(pair, scope: scope, now: 1_000, consent: true)
        let metadata = try KeychainTeamDeviceMetadata(testService: "pinbook.device-test.owner-tls", keychain: SessionMemoryKeychain())
        let custody = TeamDeviceCustody(storage: metadata, keys: DeviceFixtureKeys(), clock: { 1_000 })
        let owner = try TeamDeviceRegistration(scope: scope, authorityEpoch: "public-epoch", sessions: sessions,
            devices: TeamRegistrationCustodyDriver(custody: custody), transport: client,
            clock: { .init(wallTime: 1_000, instant: .now) })
        guard case .registered(let saved) = try await owner.register(consent: true),
              case .registered(let refreshed) = try await owner.register(consent: true) else { Issue.record("Expected registration and fresh lookup"); return }
        #expect(saved.deviceID == refreshed.deviceID && saved.publicKey?.thumbprint == refreshed.publicKey?.thumbprint)
        let attempts = try fixture.records("attempts")
        #expect(attempts.compactMap { $0["path"] as? String } == ["/api/v1/devices/lookup", "/api/v1/devices/challenge", "/api/v1/devices/complete", "/api/v1/devices/lookup"])
        #expect(attempts.allSatisfy { $0["authorization"] as? String == "Bearer \(pair.accessToken)" })
        let bodies = try fixture.records("bodies"); #expect(bodies.count == 4)
        let encodedBody = try #require(bodies[2]["body"] as? String)
        let sent = try TeamStrictJSON.object(Data(encodedBody.utf8))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: #require((sent["signature"] as? String).flatMap(TeamDeviceEnrollmentWire.decode)))
        let key = try #require(saved.publicKey)
        let binding = TeamDeviceEnrollmentWire.Binding(audience: fixture.origin.absoluteString, authorityEpoch: "public-epoch", accountID: pair.accountID,
            sessionID: pair.sessionID, deviceID: saved.deviceID, keyThumbprint: key.thumbprint, accessExpiresAt: pair.accessExpiresAt)
        let wire = try Data(contentsOf: fixture.directory.appendingPathComponent("device-public.json"))
        let message = try TeamDeviceEnrollmentWire.message(challenge: wire, expected: binding, now: 1_000)
        #expect(key.key.isValidSignature(signature, for: message))
        #expect(try sessions.load(scope: scope)?.usablePair(now: 1_000) == pair)
    }

    @Test func rotatingTokenNeverReplayedAfterHTTPFailureOrLostResponse() async throws {
        for mode in ["503", "408", "drop"] {
            let fixture = try await Fixture(mode: mode)
            let client = try fixture.client()
            do { _ = try await client.refresh(pair); Issue.record("Expected synthetic failure: \(mode)") }
            catch { #expect(error is TeamAuthHTTPError) }
            // Allow any already-dispatched retry to reach the local listener.
            try await Task.sleep(for: .milliseconds(150))
            #expect(try fixture.records("attempts").count == 1, "Request attempts for \(mode)")
            #expect(try fixture.records("bodies").count == 1, "Credential transmissions for \(mode)")
        }
    }

    @Test func redirectAndFixedOrChunkedOverflowFailClosed() async throws {
        for mode in ["redirect", "oversize", "chunked"] {
            let fixture = try await Fixture(mode: mode)
            let client = try fixture.client()
            let expected: TeamAuthHTTPError = mode == "redirect" ? .redirectRefused : .responseTooLarge
            await #expect(throws: expected) { try await client.challenge(providerID: "public-ios") }
            #expect(try fixture.records("attempts").count == 1)
        }
    }

    @Test func cancellationAndStalledBodyHaveBoundedCompletion() async throws {
        let fixture = try await Fixture(mode: "stall")
        let client = try fixture.client()
        let task = Task { try await client.refresh(pair) }
        var bodyObserved = false
        for _ in 0..<100 {
            if try !fixture.records("bodies").isEmpty { bodyObserved = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(bodyObserved, "Cancellation fixture did not receive body; URL error codes=\(fixture.diagnostics.values)")
        #expect(try fixture.records("attempts").count == 1)
        let deadlineFixture = try await Fixture(mode: "stall")
        let deadlineClient = try deadlineFixture.client()
        let start = ContinuousClock.now
        await #expect(throws: TeamAuthHTTPError.transport) { try await deadlineClient.refresh(pair) }
        #expect(start.duration(to: .now) < .seconds(18))
        #expect(deadlineFixture.diagnostics.values.contains(.url(NSURLErrorTimedOut)))
        #expect(try deadlineFixture.records("attempts").count == 1)
    }

    @Test func refreshManagerPersistsActualTLSResultOrKeepsReauthenticationBarrier() async throws {
        for mode in ["success", "503", "drop"] {
            let fixture = try await Fixture(mode: mode)
            let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
            let backend = SessionMemoryKeychain()
            let store = TeamAccountSessionStore(testService: "local-tls-manager", keychain: backend)
            _ = try store.saveInitial(pair, scope: scope, now: 1_000, consent: true)
            let manager = TeamAccountRefreshManager(scope: scope, store: store,
                transport: try fixture.client(), clock: { 2_000 })
            if mode == "success" {
                let next = try await manager.refresh()
                #expect(next != pair)
                #expect(try store.load(scope: scope)?.usablePair(now: 2_001) == next)
            } else {
                await #expect(throws: TeamAccountRefreshError.transportFailure) { try await manager.refresh() }
                #expect(try store.load(scope: scope)?.phase == .refreshPending)
                // A newly constructed owner after restart must not recover old tokens.
                let reopened = TeamAccountRefreshManager(scope: scope, store: store,
                    transport: try fixture.client(), clock: { 2_001 })
                await #expect(throws: TeamAccountSessionError.reauthenticationRequired) { try await reopened.refresh() }
            }
            #expect(try fixture.records("attempts").count == 1)
            #expect(try fixture.records("bodies").count == 1)
        }
    }

    // Fresh listener/certificate for each case. Every case must pass; this is not
    // retry-on-failure or replay of a request/credential against the same service.
    @Test(arguments: 0..<3) func signInCoordinatorUsesActualTLSChallengeExchangeAndBoundReservation(iteration: Int) async throws {
        let fixture = try await Fixture(mode: "success")
        let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
        let store = TeamAccountSessionStore(testService: "local-tls-signin", keychain: SessionMemoryKeychain())
        let instant = ContinuousClock.now
        let trace = SignInTransportTrace(try fixture.client())
        let owner = TeamAccountSignInCoordinator(provider: .apple, scope: scope, store: store,
            identity: SyntheticAppleIdentity(), transport: trace,
            clock: { TeamSignInMoment(wallTime: 1_000, instant: instant) })
        let result: TeamAuthSessionPair
        do { result = try await owner.signIn(consent: true) }
        catch {
            // Fixed error cases and public path/count only; never token/body data.
            let routes = try fixture.records("attempts").compactMap { $0["path"] as? String }
            Issue.record("Local TLS sign-in failure case\(iteration): \(await trace.failures), URLcodes=\(fixture.diagnostics.values), routes=\(routes), bodies=\(try fixture.records("bodies").count)")
            throw error
        }
        #expect(try store.load(scope: scope)?.usablePair(now: 2_000) == result)
        let requests = try fixture.records("attempts")
        #expect(requests.compactMap { $0["path"] as? String } == ["/api/v1/auth/challenge", "/api/v1/auth/exchange"])
        let bodies = try fixture.records("bodies")
        #expect(bodies.count == 2)
        let exchangeBody = try #require(bodies.last?["body"] as? String)
        let fields = try #require(JSONSerialization.jsonObject(with: Data(exchangeBody.utf8)) as? [String: String])
        #expect(Set(fields.keys) == ["providerId", "challengeId", "idToken"])
        #expect(fields["providerId"] == "public-ios")
        #expect(fields["idToken"] == "public.header.signature")
    }
}
#endif
