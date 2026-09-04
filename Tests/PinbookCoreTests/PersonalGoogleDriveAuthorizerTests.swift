#if canImport(UIKit) && canImport(AppAuth) && !SWIFT_PACKAGE
import AppAuthCore
import Testing
import UIKit
@testable import Pinbook

@MainActor private final class FakePersonalDriveAuthorizationDriver:
    PersonalGoogleDriveAuthorizationDriving {
    let request: OIDAuthorizationRequest
    let callback: @MainActor (Result<PersonalGoogleDriveGrant,
                                    PersonalGoogleDriveOAuthError>) -> Void
    var starts = 0
    var cancels = 0
    var resumes = 0
    var immediate = false

    init(request: OIDAuthorizationRequest,
         callback: @escaping @MainActor (Result<PersonalGoogleDriveGrant,
                                               PersonalGoogleDriveOAuthError>) -> Void) {
        self.request = request
        self.callback = callback
    }

    func start() {
        starts += 1
        if immediate { succeed() }
    }

    func cancel() { cancels += 1 }
    func resume(_ url: URL) -> Bool { resumes += 1; return true }
    func succeed(now: Int64 = 1_000) {
        do {
            callback(.success(try personalDriveCredentialGrant(
                refreshLifetime: 7_200, now: now
            )))
        } catch {
            callback(.failure(.invalidResponse))
        }
    }
}

@MainActor private final class PersonalDriveAuthorizationClock {
    var time: Int64 = 1_000
}

@MainActor @Suite(.serialized)
struct PersonalGoogleDriveAuthorizerTests {
    private func configuration() throws -> PersonalGoogleDriveConfiguration {
        try personalDriveCredentialConfiguration("123-browser")
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic personal Drive authorization did not settle")
    }

    @Test func explicitConsentBuildsActualDriveOnlyRequestAndReturnsGrant() async throws {
        var starts = 0
        let authorizer = PersonalGoogleDriveAuthorizer(
            configuration: try configuration(), testPresenter: UIViewController(),
            now: { 1_000 }
        ) { request, _, callback in
            #expect(request.scope == GoogleDriveBackupTransport.scope)
            #expect(request.clientSecret == nil && request.codeChallengeMethod == "S256")
            starts += 1
            let driver = FakePersonalDriveAuthorizationDriver(
                request: request, callback: callback
            )
            driver.immediate = true
            return driver
        }
        let grant = try await authorizer.authorize(consent: true)
        #expect(try grant.accessToken(now: 1_000).description ==
                "GoogleDriveAccessToken(<redacted>)")
        #expect(starts == 1)

        await #expect(throws: PersonalGoogleDriveOAuthError.invalidRequest) {
            try await authorizer.authorize(consent: false)
        }
        #expect(starts == 1)
    }

    @Test func cancellationRetainsOwnershipUntilOldCallbackAndCannotAffectNext() async throws {
        var drivers = [FakePersonalDriveAuthorizationDriver]()
        let authorizer = PersonalGoogleDriveAuthorizer(
            configuration: try configuration(), testPresenter: UIViewController(),
            now: { 1_000 }
        ) { request, _, callback in
            let driver = FakePersonalDriveAuthorizationDriver(
                request: request, callback: callback
            )
            drivers.append(driver)
            return driver
        }
        let first = Task { try await authorizer.authorize(consent: true) }
        try await waitUntil { drivers.count == 1 }
        first.cancel()
        try await waitUntil { drivers[0].cancels == 1 }
        await #expect(throws: PersonalGoogleDriveOAuthError.busy) {
            try await authorizer.authorize(consent: true)
        }
        drivers[0].succeed()
        await #expect(throws: CancellationError.self) { try await first.value }

        let next = Task { try await authorizer.authorize(consent: true) }
        try await waitUntil { drivers.count == 2 }
        drivers[0].succeed()
        #expect(drivers[1].cancels == 0)
        drivers[1].succeed()
        _ = try await next.value
    }

    @Test func redirectRoutingIsExactBoundedAndStopsAfterCancellation() async throws {
        let configuration = try configuration()
        var driver: FakePersonalDriveAuthorizationDriver?
        let authorizer = PersonalGoogleDriveAuthorizer(
            configuration: configuration, testPresenter: UIViewController(),
            now: { 1_000 }
        ) { request, _, callback in
            let value = FakePersonalDriveAuthorizationDriver(
                request: request, callback: callback
            )
            driver = value
            return value
        }
        let task = Task { try await authorizer.authorize(consent: true) }
        try await waitUntil { driver != nil }
        for raw in [
            "other:/oauth2callback",
            configuration.redirectURL.absoluteString + "#fragment",
            configuration.redirectScheme + "://foreign/oauth2callback",
            configuration.redirectScheme + ":/other",
            configuration.redirectURL.absoluteString + "?code="
                + String(repeating: "A", count: 16_384),
        ] {
            #expect(!authorizer.handleRedirect(URL(string: raw)!))
        }
        #expect(authorizer.handleRedirect(configuration.redirectURL))
        #expect(driver?.resumes == 1)
        authorizer.cancel()
        #expect(!authorizer.handleRedirect(configuration.redirectURL))
        driver?.succeed()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func rollbackAndMissingRegisteredLiveSchemeFailClosed() async throws {
        let clock = PersonalDriveAuthorizationClock()
        var driver: FakePersonalDriveAuthorizationDriver?
        let authorizer = PersonalGoogleDriveAuthorizer(
            configuration: try configuration(), testPresenter: UIViewController(),
            now: { clock.time }
        ) { request, _, callback in
            let value = FakePersonalDriveAuthorizationDriver(
                request: request, callback: callback
            )
            driver = value
            return value
        }
        let task = Task { try await authorizer.authorize(consent: true) }
        try await waitUntil { driver != nil }
        clock.time = 999
        driver?.succeed()
        await #expect(throws: PersonalGoogleDriveOAuthError.invalidResponse) {
            try await task.value
        }

        let live = PersonalGoogleDriveAuthorizer(
            configuration: try configuration(), presenting: { nil }
        )
        await #expect(throws: PersonalGoogleDriveOAuthError.invalidConfiguration) {
            try await live.authorize(consent: true)
        }
    }
}
#endif
