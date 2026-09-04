#if canImport(UIKit) && canImport(AppAuth)
import AppAuth
import AppAuthCore
import UIKit

@MainActor protocol PersonalGoogleDriveAuthorizationDriving: AnyObject {
    func start()
    func cancel()
    func resume(_ url: URL) -> Bool
}

@MainActor private final class SystemPersonalGoogleDriveAuthorizationDriver:
    PersonalGoogleDriveAuthorizationDriving {
    private struct Reply: Sendable {
        let matchesRequest: Bool
        let code: String?
        let state: String?
        let error: PersonalGoogleDriveOAuthError?
    }

    private let request: OIDAuthorizationRequest
    private let presenter: UIViewController
    private let tokenClient: PersonalGoogleDriveTokenClient
    private let revoker: PersonalGoogleDriveRevocationClient
    private var callback: ((Result<PersonalGoogleDriveGrant,
                            PersonalGoogleDriveOAuthError>) -> Void)?
    private var flow: (any OIDExternalUserAgentSession)?
    private var tokenTask: Task<Void, Never>?
    private var started = false
    private var cancelled = false
    private var finished = false

    init(request: OIDAuthorizationRequest, presenter: UIViewController,
         configuration: PersonalGoogleDriveConfiguration,
         callback: @escaping (Result<PersonalGoogleDriveGrant,
                             PersonalGoogleDriveOAuthError>) -> Void) {
        self.request = request
        self.presenter = presenter
        tokenClient = PersonalGoogleDriveTokenClient(configuration: configuration)
        revoker = PersonalGoogleDriveRevocationClient()
        self.callback = callback
    }

    func start() {
        guard !started, !finished else { return }
        started = true
        guard !cancelled else { finish(.failure(.cancelled)); return }
        guard let browser = OIDExternalUserAgentIOS(
            presenting: presenter, prefersEphemeralSession: true
        ) else {
            finish(.failure(.unavailablePresentation))
            return
        }
        let expectedRequest = request
        let session = OIDAuthorizationService.present(
            request, externalUserAgent: browser
        ) { [weak self] response, error in
            let native = error as NSError?
            let fixedError: PersonalGoogleDriveOAuthError? = native.map {
                $0.domain == OIDGeneralErrorDomain
                    && $0.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue
                    ? .cancelled : .unavailable
            }
            let rawCode = response?.authorizationCode
            let rawState = response?.state
            let reply = Reply(
                matchesRequest: response?.request === expectedRequest,
                code: rawCode.flatMap {
                    (1...4_096).contains($0.utf8.count) ? $0 : nil
                },
                state: rawState.flatMap {
                    (20...512).contains($0.utf8.count) ? $0 : nil
                },
                error: fixedError
            )
            Task { @MainActor [weak self] in self?.authorized(reply) }
        }
        if !finished, tokenTask == nil {
            flow = session
            if cancelled { session.cancel() }
        }
    }

    private func authorized(_ reply: Reply) {
        guard !finished, tokenTask == nil else { return }
        flow = nil
        guard !cancelled else { finish(.failure(.cancelled)); return }
        if let error = reply.error { finish(.failure(error)); return }
        guard reply.matchesRequest, reply.state == request.state,
              let code = reply.code, let verifier = request.codeVerifier else {
            finish(.failure(.invalidResponse))
            return
        }
        let tokenClient = tokenClient
        let revoker = revoker
        tokenTask = Task { @MainActor [weak self] in
            do {
                let grant = try await tokenClient.exchange(code: code, verifier: verifier)
                guard let self else {
                    try? await revoker.revoke(grant.refresh)
                    return
                }
                if self.cancelled {
                    try? await revoker.revoke(grant.refresh)
                    self.finish(.failure(.cancelled))
                } else {
                    self.finish(.success(grant))
                }
            } catch is CancellationError {
                self?.finish(.failure(.cancelled))
            } catch let error as PersonalGoogleDriveOAuthError {
                self?.finish(.failure(error))
            } catch {
                self?.finish(.failure(.unavailable))
            }
        }
    }

    func cancel() {
        guard !finished, !cancelled else { return }
        cancelled = true
        if let flow { flow.cancel() }
        else if tokenTask == nil, !started { finish(.failure(.cancelled)) }
        // An exchanged grant must settle before completion so it can be revoked.
    }

    func resume(_ url: URL) -> Bool {
        guard !cancelled, !finished, let flow else { return false }
        do {
            try flow.resumeExternalUserAgentFlow(url)
            return true
        } catch { return false }
    }

    private func finish(_ result: Result<PersonalGoogleDriveGrant,
                        PersonalGoogleDriveOAuthError>) {
        guard !finished else { return }
        finished = true
        flow = nil
        tokenTask = nil
        let completion = callback
        callback = nil
        completion?(cancelled ? .failure(.cancelled) : result)
    }
}

private final class PersonalDriveBackgroundObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// AppAuth browser/callback owner for an explicit personal Drive connection.
/// It returns a redacted grant; durable save/cleanup belongs to the connection
/// coordinator and must complete before user-visible success.
@MainActor final class PersonalGoogleDriveAuthorizer {
    typealias DriverFactory = @MainActor (
        OIDAuthorizationRequest, UIViewController,
        @escaping @MainActor (Result<PersonalGoogleDriveGrant,
                              PersonalGoogleDriveOAuthError>) -> Void
    ) -> any PersonalGoogleDriveAuthorizationDriving

    private struct Pending {
        let id: UUID
        let startedAt: Int64
        let deadlineAt: Int64
        let driver: any PersonalGoogleDriveAuthorizationDriving
        let continuation: CheckedContinuation<PersonalGoogleDriveGrant, Error>
        var cancelled = false
        var deadline: Task<Void, Never>?
    }

    private let configuration: PersonalGoogleDriveConfiguration
    private let presenter: @MainActor () -> UIViewController?
    private let makeDriver: DriverFactory
    private let now: @MainActor () -> Int64
    private let strictPresentation: Bool
    private var pending: Pending?
    private var observation: PersonalDriveBackgroundObservation?

    init(configuration: PersonalGoogleDriveConfiguration,
         presenting: @escaping @MainActor () -> UIViewController?) {
        self.configuration = configuration
        presenter = presenting
        now = { Int64(Date().timeIntervalSince1970 * 1_000) }
        strictPresentation = true
        makeDriver = { request, presenter, callback in
            SystemPersonalGoogleDriveAuthorizationDriver(
                request: request, presenter: presenter,
                configuration: configuration, callback: callback
            )
        }
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        observation = PersonalDriveBackgroundObservation(token)
    }

    #if DEBUG
    init(configuration: PersonalGoogleDriveConfiguration,
         testPresenter: UIViewController,
         now: @escaping @MainActor () -> Int64,
         makeDriver: @escaping DriverFactory) {
        self.configuration = configuration
        presenter = { testPresenter }
        self.now = now
        self.makeDriver = makeDriver
        strictPresentation = false
    }
    #endif

    func authorize(consent: Bool) async throws -> PersonalGoogleDriveGrant {
        try Task.checkCancellation()
        guard consent else { throw PersonalGoogleDriveOAuthError.invalidRequest }
        guard pending == nil else { throw PersonalGoogleDriveOAuthError.busy }
        let startedAt = now()
        guard startedAt >= 0,
              startedAt <= TeamAuthWire.maximumSafeTime - 600_000 else {
            throw PersonalGoogleDriveOAuthError.invalidRequest
        }
        if strictPresentation,
           !Self.registeredSchemes().contains(configuration.redirectScheme) {
            throw PersonalGoogleDriveOAuthError.invalidConfiguration
        }
        guard let presenter = presenter(),
              !strictPresentation || TeamGoogleIdentityAuthorizer.isUsable(presenter) else {
            throw PersonalGoogleDriveOAuthError.unavailablePresentation
        }
        let request = try PersonalGoogleDriveOAuthRequest.make(configuration: configuration)
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let driver = makeDriver(request, presenter) { [weak self] result in
                    self?.finish(id: id, result: result)
                }
                pending = Pending(
                    id: id, startedAt: startedAt,
                    deadlineAt: startedAt + 600_000,
                    driver: driver, continuation: continuation
                )
                pending?.deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(600)) } catch { return }
                    self?.cancel(id: id)
                }
                driver.start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }

    func cancel() {
        guard let id = pending?.id else { return }
        cancel(id: id)
    }

    /// True means the exact callback was handed to AppAuth, not that connection
    /// or credential persistence succeeded.
    func handleRedirect(_ url: URL) -> Bool {
        guard let value = pending, !value.cancelled,
              url.absoluteString.utf8.count <= 16_384,
              url.scheme == configuration.redirectScheme,
              url.host == nil, url.user == nil, url.password == nil,
              url.port == nil, url.path == configuration.redirectURL.path,
              url.fragment == nil else { return false }
        return value.driver.resume(url)
    }

    private func cancel(id: UUID) {
        guard var value = pending, value.id == id, !value.cancelled else { return }
        value.cancelled = true
        pending = value
        value.deadline?.cancel()
        value.driver.cancel()
    }

    private func finish(id: UUID,
                        result: Result<PersonalGoogleDriveGrant,
                                       PersonalGoogleDriveOAuthError>) {
        guard let value = pending, value.id == id else { return }
        pending = nil
        value.deadline?.cancel()
        if value.cancelled {
            value.continuation.resume(throwing: CancellationError())
            return
        }
        switch result {
        case .failure(let error):
            value.continuation.resume(throwing: error)
        case .success(let grant):
            let completedAt = now()
            guard completedAt >= value.startedAt,
                  completedAt < value.deadlineAt,
                  (try? grant.accessToken(now: completedAt)) != nil else {
                value.continuation.resume(
                    throwing: PersonalGoogleDriveOAuthError.invalidResponse
                )
                return
            }
            value.continuation.resume(returning: grant)
        }
    }

    private static func registeredSchemes() -> Set<String> {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
            as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    }
}
#endif
