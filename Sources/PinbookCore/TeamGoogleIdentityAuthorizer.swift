#if canImport(UIKit) && canImport(AppAuth)
import UIKit
import AppAuth
import AppAuthCore

@MainActor protocol TeamGoogleAuthorizationDriving: AnyObject {
    func start()
    func cancel()
    func resume(_ url: URL) -> Bool
}

@MainActor private final class SystemGoogleAuthorizationDriver: TeamGoogleAuthorizationDriving {
    private struct Reply: Sendable {
        let matchesRequest: Bool
        let code: String?
        let state: String?
        let error: TeamGoogleIdentityError?
    }
    private let request: OIDAuthorizationRequest
    private let presenter: UIViewController
    private let context: TeamNativeSignInContext
    private let tokenClient: TeamGoogleTokenClient
    private var callback: ((Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) -> Void)?
    private var flow: (any OIDExternalUserAgentSession)?
    private var tokenTask: Task<Void, Never>?
    private var started = false
    private var cancelled = false
    private var finished = false

    init(request: OIDAuthorizationRequest, presenter: UIViewController, context: TeamNativeSignInContext,
         configuration: TeamGoogleNativeConfiguration,
         callback: @escaping (Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) -> Void) {
        self.request = request; self.presenter = presenter; self.context = context
        tokenClient = TeamGoogleTokenClient(configuration: configuration); self.callback = callback
    }
    func start() {
        guard !started, !finished else { return }
        started = true
        guard !cancelled else { finish(.failure(.cancelled)); return }
        guard let browser = OIDExternalUserAgentIOS(presenting: presenter, prefersEphemeralSession: true) else {
            finish(.failure(.unavailablePresentation)); return
        }
        let expectedRequest = request
        let session = OIDAuthorizationService.present(request, externalUserAgent: browser) { [weak self] response, error in
            let native = error as NSError?
            let fixedError: TeamGoogleIdentityError? = native.map {
                $0.domain == OIDGeneralErrorDomain && $0.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue ? .cancelled : .failed
            }
            // Copy only bounded scalar results to the main actor. Raw SDK errors,
            // URL, scopes/profile and response objects never cross this boundary.
            let code = response?.authorizationCode
            let returnedState = response?.state
            let reply = Reply(matchesRequest: response?.request === expectedRequest,
                code: code.flatMap { (1...4096).contains($0.utf8.count) ? $0 : nil },
                state: returnedState.flatMap { TeamAuthWire.credential($0) ? $0 : nil }, error: fixedError)
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
        guard reply.matchesRequest, reply.state == request.state, let code = reply.code,
              let verifier = request.codeVerifier else { finish(.failure(.invalidCredential)); return }
        let client = tokenClient, context = context
        tokenTask = Task { @MainActor [weak self] in
            do {
                let token = try await client.exchange(code: code, verifier: verifier, context: context)
                self?.finish(.success(.google(token: token)))
            } catch is CancellationError { self?.finish(.failure(.cancelled)) }
            catch let error as TeamGoogleIdentityError { self?.finish(.failure(error)) }
            catch { self?.finish(.failure(.failed)) }
        }
    }
    func cancel() {
        guard !finished, !cancelled else { return }
        cancelled = true
        if let flow { flow.cancel() }
        else if let tokenTask { tokenTask.cancel() }
        else if !started { finish(.failure(.cancelled)) }
        // Starting/browser or token operations retain ownership until callbacks.
    }
    func resume(_ url: URL) -> Bool {
        guard !cancelled, !finished, let flow else { return false }
        do { try flow.resumeExternalUserAgentFlow(url); return true }
        catch { return false }
    }
    private func finish(_ result: Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) {
        guard !finished else { return }
        finished = true; flow = nil; tokenTask = nil
        let completion = callback; callback = nil
        completion?(cancelled ? .failure(.cancelled) : result)
    }
}

private final class GoogleBackgroundObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Inactive native Google adapter. The system browser owns OAuth state/PKCE;
/// Pinbook owns a bounded one-dispatch token exchange and separate account session.
@MainActor public final class TeamGoogleIdentityAuthorizer: TeamNativeIdentityAuthorizing {
    typealias DriverFactory = @MainActor (OIDAuthorizationRequest, UIViewController, TeamNativeSignInContext,
        @escaping @MainActor (Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) -> Void) -> any TeamGoogleAuthorizationDriving
    private struct Pending {
        let id: UUID
        let context: TeamNativeSignInContext
        let startedAt: Int64
        let driver: any TeamGoogleAuthorizationDriving
        let continuation: CheckedContinuation<TeamNativeIdentityResponse, Error>
        var cancelled = false
        var deadline: Task<Void, Never>?
    }
    private let configuration: TeamGoogleNativeConfiguration
    private let presenter: @MainActor () -> UIViewController?
    private let makeDriver: DriverFactory
    private let now: @MainActor () -> Int64
    private let strictPresentation: Bool
    private var pending: Pending?
    private var observation: GoogleBackgroundObservation?

    public init(configuration: TeamGoogleNativeConfiguration, presenting: @escaping @MainActor () -> UIViewController?) {
        self.configuration = configuration; presenter = presenting; strictPresentation = true
        now = { Int64(Date().timeIntervalSince1970 * 1000) }
        makeDriver = { SystemGoogleAuthorizationDriver(request: $0, presenter: $1, context: $2, configuration: configuration, callback: $3) }
        let token = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let id = self?.pending?.id { self?.cancel(id: id) } }
        }
        observation = GoogleBackgroundObservation(token)
    }
    #if DEBUG
    init(configuration: TeamGoogleNativeConfiguration, testPresenter: UIViewController,
         now: @escaping @MainActor () -> Int64, makeDriver: @escaping DriverFactory) {
        self.configuration = configuration; presenter = { testPresenter }; self.now = now
        self.makeDriver = makeDriver; strictPresentation = false
    }
    #endif

    public func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamGoogleIdentityError.busy }
        let time = now()
        guard context.provider == .google, context.providerID == configuration.providerID,
              time >= 0, context.expiresAt > time, context.expiresAt - time <= 120_000,
              TeamAuthWire.credential(context.nonce), TeamAuthWire.credential(context.challengeID) else {
            throw TeamGoogleIdentityError.invalidContext
        }
        if strictPresentation, !Self.registeredSchemes().contains(configuration.redirectScheme) {
            throw TeamGoogleIdentityError.invalidConfiguration
        }
        guard let presenter = presenter(), !strictPresentation || Self.isUsable(presenter) else {
            throw TeamGoogleIdentityError.unavailablePresentation
        }
        let request = try TeamGoogleOAuthRequest.make(configuration: configuration, context: context)
        let id = UUID()
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let driver = makeDriver(request, presenter, context) { [weak self] in self?.finish(id: id, result: $0) }
                    pending = Pending(id: id, context: context, startedAt: time, driver: driver, continuation: continuation)
                    pending?.deadline = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: .milliseconds(context.expiresAt - time)) } catch { return }
                        self?.cancel(id: id)
                    }
                    driver.start()
                }
            } onCancel: { Task { @MainActor [weak self] in self?.cancel(id: id) } }
            try Task.checkCancellation()
            return result
        } catch { try Task.checkCancellation(); throw error }
    }
    public func cancelAuthorization(attemptID: UUID) {
        guard let value = pending, value.context.id == attemptID else { return }
        cancel(id: value.id)
    }
    /// True means handed to the owned OAuth flow, never successful sign-in/admission.
    public func handleRedirect(_ url: URL, attemptID: UUID) -> Bool {
        guard let value = pending, value.context.id == attemptID, !value.cancelled,
              url.absoluteString.utf8.count <= 16_384, url.scheme == configuration.redirectScheme,
              url.host == nil, url.user == nil, url.password == nil, url.port == nil,
              url.path == configuration.redirectURL.path, url.fragment == nil else { return false }
        return value.driver.resume(url)
    }
    private func cancel(id: UUID) {
        guard var value = pending, value.id == id, !value.cancelled else { return }
        value.cancelled = true; pending = value; value.deadline?.cancel(); value.driver.cancel()
    }
    private func finish(id: UUID, result: Result<TeamNativeIdentityResponse, TeamGoogleIdentityError>) {
        guard let value = pending, value.id == id else { return }
        pending = nil; value.deadline?.cancel()
        if value.cancelled { value.continuation.resume(throwing: CancellationError()); return }
        switch result {
        case .failure(let error): value.continuation.resume(throwing: error)
        case .success(let response):
            let completedAt = now()
            guard completedAt >= value.startedAt, completedAt < value.context.expiresAt,
                  case .google(let token) = response, (1...16_384).contains(token.count),
                  token.allSatisfy({ TeamAuthWire.urlByte($0) || $0 == 46 }),
                  token.split(separator: 46, omittingEmptySubsequences: false).count == 3,
                  !token.split(separator: 46, omittingEmptySubsequences: false).contains(where: \.isEmpty) else {
                value.continuation.resume(throwing: TeamGoogleIdentityError.invalidCredential); return
            }
            value.continuation.resume(returning: response)
        }
    }
    static func isUsable(_ presenter: UIViewController) -> Bool {
        guard !presenter.isBeingDismissed, presenter.presentedViewController == nil,
              let window = presenter.viewIfLoaded?.window else { return false }
        return TeamAppleIdentityAuthorizer.isUsable(window)
    }
    private static func registeredSchemes() -> Set<String> {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    }
}
#endif
