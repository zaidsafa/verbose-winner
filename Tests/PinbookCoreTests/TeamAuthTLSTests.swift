#if os(macOS) && SWIFT_PACKAGE
import Foundation
import Testing
@testable import PinbookCore

/// Runs real Foundation/CFNetwork over private localhost TLS, without modifying
/// system trust. Certificates exist only in a fresh temporary fixture directory.
@Suite(.serialized)
struct TeamAuthTLSTests {
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
        private let serverExit = ProcessExit()

        init(mode: String) async throws {
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
                origin = try #require(URL(string: "https://localhost:\(port)"))
            } catch {
                if !server.isRunning || serverExit.stop(server) { try? FileManager.default.removeItem(at: directory) }
                throw error
            }
        }
        deinit {
            if serverExit.stop(server) { try? FileManager.default.removeItem(at: directory) }
            else { Issue.record("Synthetic TLS server did not confirm exit; retained its private fixture directory") }
        }
        func client() throws -> TeamAuthHTTPClient {
            try TeamAuthHTTPClient(origin: origin, protocolClasses: nil, localTestAnchor: anchor, clock: { 1_000 })
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
    private var pair: TeamAuthSessionPair {
        TeamAuthSessionPair(accountID: "public-account", sessionID: "public-session",
            accessToken: String(repeating: "A", count: 43), refreshToken: String(repeating: "B", count: 42) + "A",
            accessExpiresAt: 10_000, sessionExpiresAt: 30_000)
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
        for _ in 0..<100 {
            if try !fixture.records("bodies").isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.records("attempts").count == 1)
        let deadlineFixture = try await Fixture(mode: "stall")
        let deadlineClient = try deadlineFixture.client()
        let start = ContinuousClock.now
        await #expect(throws: TeamAuthHTTPError.transport) { try await deadlineClient.refresh(pair) }
        #expect(start.duration(to: .now) < .seconds(18))
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

    @Test func signInCoordinatorUsesActualTLSChallengeExchangeAndBoundReservation() async throws {
        let fixture = try await Fixture(mode: "success")
        let scope = try TeamAccountSessionScope(origin: fixture.origin, providerID: "public-ios")
        let store = TeamAccountSessionStore(testService: "local-tls-signin", keychain: SessionMemoryKeychain())
        let instant = ContinuousClock.now
        let owner = TeamAccountSignInCoordinator(provider: .apple, scope: scope, store: store,
            identity: SyntheticAppleIdentity(), transport: try fixture.client(),
            clock: { TeamSignInMoment(wallTime: 1_000, instant: instant) })
        let result = try await owner.signIn(consent: true)
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
