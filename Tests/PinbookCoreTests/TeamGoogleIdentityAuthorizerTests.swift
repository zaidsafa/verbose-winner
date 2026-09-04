#if canImport(UIKit) && canImport(AppAuth) && !SWIFT_PACKAGE
import UIKit
import AppAuthCore
import Testing
@testable import Pinbook

@MainActor private final class FakeGoogleDriver: TeamGoogleAuthorizationDriving {
    let request: OIDAuthorizationRequest
    let callback: @MainActor (Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) -> Void
    var starts = 0, cancels = 0, resumes = 0
    var immediate = false
    init(request: OIDAuthorizationRequest, callback: @escaping @MainActor (Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) -> Void) {
        self.request = request; self.callback = callback
    }
    func start() { starts += 1; if immediate { succeed() } }
    func cancel() { cancels += 1 }
    func resume(_ url: URL) -> Bool { resumes += 1; return true }
    func succeed() { callback(.success(.google(token: Data("public.header.signature".utf8)))) }
}
@MainActor private final class GoogleClock { var time: Int64 = 1_000 }

@MainActor @Suite(.serialized)
struct TeamGoogleIdentityAuthorizerTests {
    private func configuration() throws -> TeamGoogleNativeConfiguration {
        try .init(providerID: "public-google-ios", nativeClientID: "123-publicnative.apps.googleusercontent.com",
            serverClientID: "123-publicserver.apps.googleusercontent.com", registeredURLSchemes: ["com.googleusercontent.apps.123-publicnative"])
    }
    private func context(expiry: Int64 = 121_000) async throws -> TeamNativeSignInContext {
        try await TeamNativeSignInFlow().begin(provider: .google, providerID: "public-google-ios",
            challengeID: String(repeating: "A", count: 43), nonce: String(repeating: "B", count: 42) + "A", expiresAt: expiry, now: 1_000)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic Google driver did not reach expected state")
    }
    @Test func synchronousDriverCompletesCorrectlyWithActualSDKRequest() async throws {
        let context = try await context()
        var starts = 0
        let adapter = TeamGoogleIdentityAuthorizer(configuration: try configuration(), testPresenter: UIViewController(), now: { 1_000 }) { request, _, bound, callback in
            #expect(bound.id == context.id && request.nonce == context.nonce && request.scope == "openid")
            starts += 1
            let driver = FakeGoogleDriver(request: request, callback: callback); driver.immediate = true; return driver
        }
        let response = try await adapter.authorize(context)
        guard case .google(let token) = response else { Issue.record("Expected Google response"); return }
        #expect(token == Data("public.header.signature".utf8) && starts == 1)
    }
    @Test func cancellationQuarantineAndOldCallbackCannotAffectNewAttempt() async throws {
        let first = try await context(), second = try await context()
        var drivers = [FakeGoogleDriver]()
        let adapter = TeamGoogleIdentityAuthorizer(configuration: try configuration(), testPresenter: UIViewController(), now: { 1_000 }) { request, _, _, callback in
            let driver = FakeGoogleDriver(request: request, callback: callback); drivers.append(driver); return driver
        }
        let old = Task { try await adapter.authorize(first) }
        try await waitUntil { drivers.count == 1 }; old.cancel()
        try await waitUntil { drivers[0].cancels == 1 }
        await #expect(throws: TeamGoogleIdentityError.busy) { try await adapter.authorize(second) }
        drivers[0].succeed()
        await #expect(throws: CancellationError.self) { try await old.value }
        let current = Task { try await adapter.authorize(second) }
        try await waitUntil { drivers.count == 2 }
        drivers[0].succeed(); adapter.cancelAuthorization(attemptID: first.id)
        #expect(drivers[1].cancels == 0)
        drivers[1].succeed(); _ = try await current.value
    }
    @Test func redirectRoutingIsBoundedExactAndAttemptScoped() async throws {
        let context = try await context(), configuration = try configuration()
        var driver: FakeGoogleDriver?
        let adapter = TeamGoogleIdentityAuthorizer(configuration: configuration, testPresenter: UIViewController(), now: { 1_000 }) { request, _, _, callback in
            let value = FakeGoogleDriver(request: request, callback: callback); driver = value; return value
        }
        let task = Task { try await adapter.authorize(context) }
        try await waitUntil { driver != nil }
        for raw in ["other:/oauth2callback", configuration.redirectURL.absoluteString + "#fragment",
            configuration.redirectScheme + "://foreign/oauth2callback", configuration.redirectScheme + ":/other",
            configuration.redirectURL.absoluteString + "?code=" + String(repeating: "A", count: 16_384)] {
            #expect(!adapter.handleRedirect(URL(string: raw)!, attemptID: context.id))
        }
        #expect(!adapter.handleRedirect(configuration.redirectURL, attemptID: UUID()))
        #expect(adapter.handleRedirect(configuration.redirectURL, attemptID: context.id))
        #expect(driver?.resumes == 1)
        adapter.cancelAuthorization(attemptID: context.id)
        #expect(!adapter.handleRedirect(configuration.redirectURL, attemptID: context.id))
        driver?.succeed()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func wrongProviderMalformedTokenAndClockRollbackNeverReturnIdentity() async throws {
        let context = try await context()
        for response in [TeamNativeIdentityResponse.apple(state: nil, token: Data("a.b.c".utf8)), .google(token: Data("one..three".utf8)), .google(token: Data(repeating: 65, count: 16_385))] {
            let adapter = TeamGoogleIdentityAuthorizer(configuration: try configuration(), testPresenter: UIViewController(), now: { 1_000 }) { request, _, _, callback in
                let driver = FakeGoogleDriver(request: request, callback: callback)
                driver.immediate = false
                Task { @MainActor in callback(.success(response)) }
                return driver
            }
            await #expect(throws: TeamGoogleIdentityError.invalidCredential) { try await adapter.authorize(context) }
        }
        let clock = GoogleClock()
        var driver: FakeGoogleDriver?
        let adapter = TeamGoogleIdentityAuthorizer(configuration: try configuration(), testPresenter: UIViewController(), now: { clock.time }) { request, _, _, callback in
            let value = FakeGoogleDriver(request: request, callback: callback); driver = value; return value
        }
        let task = Task { try await adapter.authorize(context) }
        try await waitUntil { driver != nil }; clock.time = 999; driver?.succeed()
        await #expect(throws: TeamGoogleIdentityError.invalidCredential) { try await task.value }
    }
    @Test func preCancellationMissingConfiguredRedirectAndExpiryAreSafe() async throws {
        let context = try await context(), expiring = try await self.context(expiry: 1_020)
        var driver: FakeGoogleDriver?
        let adapter = TeamGoogleIdentityAuthorizer(configuration: try configuration(), testPresenter: UIViewController(), now: { 1_000 }) { request, _, _, callback in
            let value = FakeGoogleDriver(request: request, callback: callback); driver = value; return value
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await adapter.authorize(context) }
        }
        await cancelled.value; #expect(driver == nil)
        let operation = Task { try await adapter.authorize(expiring) }
        try await waitUntil { driver?.cancels == 1 }
        await #expect(throws: TeamGoogleIdentityError.busy) { try await adapter.authorize(context) }
        driver?.callback(.failure(.cancelled))
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!TeamGoogleIdentityAuthorizer.isUsable(UIViewController()))
        // No synthetic scheme was installed in the real app bundle.
        let live = TeamGoogleIdentityAuthorizer(configuration: try configuration(), presenting: { nil })
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let liveContext = try await TeamNativeSignInFlow().begin(provider: .google, providerID: "public-google-ios",
            challengeID: context.challengeID, nonce: context.nonce, expiresAt: now + 120_000, now: now)
        await #expect(throws: TeamGoogleIdentityError.invalidConfiguration) { try await live.authorize(liveContext) }
    }
}
#endif
