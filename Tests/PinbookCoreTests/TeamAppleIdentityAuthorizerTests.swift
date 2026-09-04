#if canImport(UIKit) && canImport(AuthenticationServices) && !SWIFT_PACKAGE
import UIKit
import AuthenticationServices
import Testing
@testable import Pinbook

@MainActor private final class FakeAppleDriver: TeamAppleAuthorizationDriving {
    let request: ASAuthorizationAppleIDRequest
    let callback: @MainActor (Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) -> Void
    var starts = 0
    var cancels = 0
    var immediate = false
    init(request: ASAuthorizationAppleIDRequest,
         callback: @escaping @MainActor (Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) -> Void) {
        self.request = request; self.callback = callback
    }
    func start() {
        starts += 1
        if immediate { succeed() }
    }
    func cancel() { cancels += 1 } // Deliberately withholds the terminal callback.
    func succeed() { callback(.success(.apple(state: request.state, token: Data("public.header.signature".utf8)))) }
}

@MainActor @Suite(.serialized)
struct TeamAppleIdentityAuthorizerTests {
    private func context(provider: TeamNativeSignInProvider = .apple, expiry: Int64 = 121_000) async throws -> TeamNativeSignInContext {
        try await TeamNativeSignInFlow().begin(provider: provider, providerID: "public-ios",
            challengeID: String(repeating: "A", count: 43), nonce: String(repeating: "B", count: 42) + "A",
            expiresAt: expiry, now: 1_000)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic Apple driver did not reach expected state")
    }
    private func checkResponse(_ response: TeamNativeIdentityResponse, state: String) {
        guard case .apple(let actual, let token) = response else { Issue.record("Expected Apple response"); return }
        #expect(actual == state && token == Data("public.header.signature".utf8))
    }

    @Test func forwardsExactNonceStateAndNoScopesWithSynchronousCallback() async throws {
        let context = try await context()
        var drivers = [FakeAppleDriver]()
        let window = UIWindow(frame: .zero)
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: window, now: { 1_000 }) { request, anchor, callback in
            #expect(anchor === window)
            let driver = FakeAppleDriver(request: request, callback: callback); driver.immediate = true
            drivers.append(driver); return driver
        }
        let result = try await adapter.authorize(context)
        let driver = try #require(drivers.first)
        #expect(driver.starts == 1 && driver.request.nonce == context.nonce && driver.request.state == context.state)
        #expect(driver.request.requestedScopes?.isEmpty == true)
        checkResponse(result, state: context.state)
        #expect(window.isHidden) // No actual window or native authorization UI shown.
    }

    @Test func cancellationQuarantinesUntilDelegateAndSuppressesLateSuccess() async throws {
        let context = try await context()
        var drivers = [FakeAppleDriver]()
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { 1_000 }) { request, _, callback in
            let driver = FakeAppleDriver(request: request, callback: callback); drivers.append(driver); return driver
        }
        let operation = Task { try await adapter.authorize(context) }
        try await waitUntil { drivers.count == 1 }
        operation.cancel()
        try await waitUntil { drivers[0].cancels == 1 }
        await #expect(throws: TeamAppleIdentityError.busy) { try await adapter.authorize(context) }
        adapter.cancelAuthorization(attemptID: context.id)
        #expect(drivers[0].cancels == 1)
        drivers[0].succeed()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func oldCallbackAndOldLifecycleCannotAffectNewRequest() async throws {
        let first = try await context(), second = try await context()
        var drivers = [FakeAppleDriver]()
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { 1_000 }) { request, _, callback in
            let driver = FakeAppleDriver(request: request, callback: callback); drivers.append(driver); return driver
        }
        let old = Task { try await adapter.authorize(first) }
        try await waitUntil { drivers.count == 1 }; drivers[0].succeed()
        _ = try await old.value
        let current = Task { try await adapter.authorize(second) }
        try await waitUntil { drivers.count == 2 }
        drivers[0].succeed() // Duplicate old native callback.
        adapter.cancelAuthorization(attemptID: first.id)
        #expect(drivers[1].cancels == 0)
        await #expect(throws: TeamAppleIdentityError.busy) { try await adapter.authorize(first) }
        drivers[1].succeed()
        checkResponse(try await current.value, state: second.state)
    }

    @Test func rejectsStateProviderMalformedAndOversizedTokens() async throws {
        let context = try await context()
        let invalid: [TeamNativeIdentityResponse] = [
            .apple(state: "wrong", token: Data("public.header.signature".utf8)),
            .google(token: Data("public.header.signature".utf8)),
            .apple(state: context.state, token: Data("one..three".utf8)),
            .apple(state: context.state, token: Data([0xff])),
            .apple(state: context.state, token: Data(repeating: 65, count: 16_385))]
        for result in invalid {
            var driver: FakeAppleDriver?
            let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { 1_000 }) { request, _, callback in
                let value = FakeAppleDriver(request: request, callback: callback); driver = value; return value
            }
            let operation = Task { try await adapter.authorize(context) }
            try await waitUntil { driver != nil }
            driver?.callback(.success(result))
            await #expect(throws: TeamAppleIdentityError.invalidCredential) { try await operation.value }
        }
        var time: Int64 = 1_000
        var driver: FakeAppleDriver?
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { time }) { request, _, callback in
            let value = FakeAppleDriver(request: request, callback: callback); driver = value; return value
        }
        let operation = Task { try await adapter.authorize(context) }
        try await waitUntil { driver != nil }
        time = 999; driver?.succeed()
        await #expect(throws: TeamAppleIdentityError.invalidCredential) { try await operation.value }
    }

    @Test func preCancelledInvalidContextAndMissingPresentationNeverStart() async throws {
        let context = try await context(), google = try await self.context(provider: .google)
        var starts = 0
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { 1_000 }) { request, _, callback in
            starts += 1; return FakeAppleDriver(request: request, callback: callback)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await adapter.authorize(context) }
        }
        await cancelled.value
        await #expect(throws: TeamAppleIdentityError.invalidContext) { try await adapter.authorize(google) }
        #expect(starts == 0)
        #expect(!TeamAppleIdentityAuthorizer.isUsable(UIWindow(frame: .zero)))
        let unavailable = TeamAppleIdentityAuthorizer(presentationAnchor: { nil })
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let liveContext = try await TeamNativeSignInFlow().begin(provider: .apple, providerID: "public-ios",
            challengeID: context.challengeID, nonce: context.nonce, expiresAt: now + 120_000, now: now)
        await #expect(throws: TeamAppleIdentityError.unavailablePresentation) { try await unavailable.authorize(liveContext) }
    }

    @Test func expiryRequestsCancellationButWaitsForNativeTerminalCallback() async throws {
        let context = try await context(expiry: 1_020)
        var driver: FakeAppleDriver?
        let adapter = TeamAppleIdentityAuthorizer(testAnchor: UIWindow(frame: .zero), now: { 1_000 }) { request, _, callback in
            let value = FakeAppleDriver(request: request, callback: callback); driver = value; return value
        }
        let operation = Task { try await adapter.authorize(context) }
        try await waitUntil { driver?.cancels == 1 }
        await #expect(throws: TeamAppleIdentityError.busy) { try await adapter.authorize(context) }
        driver?.callback(.failure(.cancelled))
        await #expect(throws: CancellationError.self) { try await operation.value }
    }
}
#endif
