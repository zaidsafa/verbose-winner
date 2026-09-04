#if os(macOS) && SWIFT_PACKAGE
import Foundation
import Testing
@testable import PinbookCore

/// Runs real Foundation/CFNetwork over private localhost TLS, without modifying
/// system trust. Certificates exist only in a fresh temporary fixture directory.
@Suite(.serialized)
struct TeamAuthTLSTests {
    private final class Fixture {
        let directory: URL
        let server: Process
        let origin: URL
        let anchor: Data

        init(mode: String) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pinbook-auth-tls-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            self.directory = directory
            let server = Process()
            self.server = server
            do {
                let openssl = Process()
                openssl.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
                openssl.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                    "-addext", "basicConstraints=critical,CA:TRUE",
                    "-addext", "extendedKeyUsage=serverAuth",
                    "-keyout", directory.appendingPathComponent("private.pem").path,
                    "-out", directory.appendingPathComponent("certificate.pem").path]
                openssl.standardOutput = FileHandle.nullDevice; openssl.standardError = FileHandle.nullDevice
                try openssl.run(); openssl.waitUntilExit()
                guard openssl.terminationStatus == 0 else { throw FixtureError.setup }
                let pem = try String(contentsOf: directory.appendingPathComponent("certificate.pem"), encoding: .utf8)
                let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
                anchor = try #require(Data(base64Encoded: base64))
                let script = try #require(Bundle.module.url(forResource: "auth_tls_fixture", withExtension: "py", subdirectory: "Fixtures"))
                server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                server.arguments = [script.path, directory.path, mode]
                server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
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
                if server.isRunning { server.terminate(); server.waitUntilExit() }
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        deinit {
            if server.isRunning { server.terminate(); server.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
        }
        func client() throws -> TeamAuthHTTPClient {
            try TeamAuthHTTPClient(origin: origin, protocolClasses: nil, localTestAnchor: anchor)
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
}
#endif
