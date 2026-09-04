#if canImport(UIKit) && canImport(AuthenticationServices)
import UIKit
import AuthenticationServices

public enum TeamAppleIdentityError: Error, Equatable {
    case busy, invalidContext, unavailablePresentation, invalidCredential, failed, cancelled
}

@MainActor protocol TeamAppleAuthorizationDriving: AnyObject {
    func start()
    func cancel()
}

@MainActor private final class SystemAppleAuthorizationDriver: NSObject, TeamAppleAuthorizationDriving,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let controller: ASAuthorizationController
    private let anchor: UIWindow
    private var callback: ((Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) -> Void)?

    init(request: ASAuthorizationAppleIDRequest, anchor: UIWindow,
         callback: @escaping (Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) -> Void) {
        controller = ASAuthorizationController(authorizationRequests: [request])
        self.anchor = anchor; self.callback = callback
        super.init()
        controller.delegate = self; controller.presentationContextProvider = self
    }
    func start() { controller.performRequests() }
    func cancel() { controller.cancel() }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken, (1...16_384).contains(token.count) else {
            finish(.failure(.invalidCredential)); return
        }
        // Do not retain/use email, name, user identifier, authorizationCode or
        // realUserStatus as admission. Only the backend verifies the ID token.
        finish(.success(.apple(state: credential.state, token: token)))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller else { return }
        let native = error as NSError
        finish(.failure(native.domain == ASAuthorizationError.errorDomain &&
            native.code == ASAuthorizationError.canceled.rawValue ? .cancelled : .failed))
    }
    private func finish(_ result: Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) {
        let completion = callback; callback = nil
        controller.delegate = nil; controller.presentationContextProvider = nil
        completion?(result)
    }
}

private final class AppleBackgroundObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Real Apple controller adapter, but not instantiated by normal navigation yet.
/// The caller must supply its active scene's anchor; no global key-window lookup.
@MainActor public final class TeamAppleIdentityAuthorizer: TeamNativeIdentityAuthorizing {
    typealias DriverFactory = @MainActor (ASAuthorizationAppleIDRequest, UIWindow,
        @escaping @MainActor (Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) -> Void) -> any TeamAppleAuthorizationDriving
    private struct Pending {
        let id: UUID
        let context: TeamNativeSignInContext
        let startedAt: Int64
        let driver: any TeamAppleAuthorizationDriving
        let continuation: CheckedContinuation<TeamNativeIdentityResponse, Error>
        var cancelled = false
        var deadline: Task<Void, Never>?
    }
    private let anchorProvider: @MainActor () -> UIWindow?
    private let makeDriver: DriverFactory
    private let strictPresentation: Bool
    private let now: @MainActor () -> Int64
    private var pending: Pending?
    private var observation: AppleBackgroundObservation?

    public init(presentationAnchor: @escaping @MainActor () -> UIWindow?) {
        anchorProvider = presentationAnchor
        makeDriver = { SystemAppleAuthorizationDriver(request: $0, anchor: $1, callback: $2) }
        strictPresentation = true
        now = { Int64(Date().timeIntervalSince1970 * 1000) }
        let token = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelCurrent() }
            }
        observation = AppleBackgroundObservation(token)
    }
    // Isolated unit driver; never presents or contacts Apple. The window stays
    // hidden and is not attached to a real scene or global application window.
    #if DEBUG
    init(testAnchor: UIWindow, now: @escaping @MainActor () -> Int64, makeDriver: @escaping DriverFactory) {
        anchorProvider = { testAnchor }; self.makeDriver = makeDriver
        strictPresentation = false; self.now = now
    }
    #endif

    public func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        try Task.checkCancellation()
        guard pending == nil else { throw TeamAppleIdentityError.busy }
        let time = now()
        guard context.provider == .apple, time >= 0, context.expiresAt > time,
              context.expiresAt - time <= 120_000,
              TeamAuthWire.credential(context.state), TeamAuthWire.credential(context.nonce),
              TeamAuthWire.credential(context.challengeID) else { throw TeamAppleIdentityError.invalidContext }
        guard let anchor = anchorProvider(), !strictPresentation || Self.isUsable(anchor) else {
            throw TeamAppleIdentityError.unavailablePresentation
        }
        let request = try context.makeAppleRequest()
        let id = UUID()
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let driver = makeDriver(request, anchor) { [weak self] result in self?.finish(id: id, result: result) }
                    // Assign ownership BEFORE start: even synchronous callbacks
                    // from a test driver are matched to the correct operation.
                    pending = Pending(id: id, context: context, startedAt: time, driver: driver, continuation: continuation)
                    pending?.deadline = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: .milliseconds(context.expiresAt - time)) }
                        catch { return }
                        self?.cancel(id: id)
                    }
                    driver.start()
                }
            } onCancel: { Task { @MainActor [weak self] in self?.cancel(id: id) } }
            // A native callback may race the queued main-actor cancellation. No
            // durable write occurs here, so cancellation still suppresses its token.
            try Task.checkCancellation()
            return result
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    /// Scoped lifecycle teardown: an old view cannot cancel a newer attempt.
    public func cancelAuthorization(attemptID: UUID) {
        guard let value = pending, value.context.id == attemptID else { return }
        cancel(id: value.id)
    }
    private func cancelCurrent() { if let id = pending?.id { cancel(id: id) } }
    private func cancel(id: UUID) {
        guard var value = pending, value.id == id, !value.cancelled else { return }
        value.cancelled = true; pending = value
        value.deadline?.cancel()
        value.driver.cancel()
        // Do not resume/clear on a mere cancellation request. Apple documents
        // a delegate completion after cancel(); quarantine until that callback.
    }
    private func finish(id: UUID, result: Result<TeamNativeIdentityResponse, TeamAppleIdentityError>) {
        guard let value = pending, value.id == id else { return }
        pending = nil
        value.deadline?.cancel()
        if value.cancelled { value.continuation.resume(throwing: CancellationError()); return }
        switch result {
        case .failure(let error): value.continuation.resume(throwing: error)
        case .success(let response):
            let completedAt = now()
            guard case .apple(let state, let token) = response,
                  completedAt >= value.startedAt, completedAt < value.context.expiresAt,
                  state == value.context.state, (1...16_384).contains(token.count),
                  token.allSatisfy({ TeamAuthWire.urlByte($0) || $0 == 46 }),
                  token.split(separator: 46, omittingEmptySubsequences: false).count == 3,
                  !token.split(separator: 46, omittingEmptySubsequences: false).contains(where: \.isEmpty) else {
                value.continuation.resume(throwing: TeamAppleIdentityError.invalidCredential); return
            }
            value.continuation.resume(returning: response)
        }
    }
    static func isUsable(_ anchor: UIWindow) -> Bool {
        anchor.windowScene?.activationState == .foregroundActive && !anchor.isHidden &&
            anchor.alpha > 0 && anchor.rootViewController != nil
    }
}
#endif
