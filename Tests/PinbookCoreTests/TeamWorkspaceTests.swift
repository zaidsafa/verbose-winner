import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class WorkspaceTermsMemory: TeamTermsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TeamTermsAcceptance?
    func load(accountID: String, teamID: String) throws -> TeamTermsAcceptance? {
        lock.withLock { value }
    }
    func save(_ acceptance: TeamTermsAcceptance) throws {
        lock.withLock { value = acceptance }
    }
    func remove(accountID: String, teamID: String) throws {
        lock.withLock { value = nil }
    }
}

private actor WorkspaceAudienceStub: TeamWorkspaceAudienceProviding {
    let value: TeamAudience
    init(_ value: TeamAudience) { self.value = value }
    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience { value }
}

private enum WorkspaceStubError: Error { case stopped }
private actor WorkspaceSubmissionStub: TeamWorkspaceSubmissionTransport {
    private(set) var hashes = [String]()
    func reserve(_ plan: TeamWorkspaceSendPlan) async throws -> TeamDeliverySubmissionReservation {
        hashes.append(plan.intent.jweSha256)
        throw WorkspaceStubError.stopped
    }
    func status(deliveryID: String, jweSHA256: String) async throws -> TeamDeliverySubmissionStatus {
        throw WorkspaceStubError.stopped
    }
}

private actor WorkspaceSafetyStub: TeamSafetyTransport {
    private(set) var actions = [TeamSafetyAction]()
    func execute(accountID: String, teamID: String, action: TeamSafetyAction) async throws {
        actions.append(action)
    }
}

private final class WorkspaceDeletionProgressMemory:
    TeamAccountDeletionProgressStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: TeamAccountDeletionProgress]()
    func load(accountID: String) throws -> TeamAccountDeletionProgress? {
        lock.withLock { values[accountID] }
    }
    func loadAll() throws -> [TeamAccountDeletionProgress] {
        lock.withLock { values.values.sorted { $0.binding.accountID < $1.binding.accountID } }
    }
    func save(_ progress: TeamAccountDeletionProgress) throws {
        lock.withLock {
            values[progress.binding.accountID] = progress
        }
    }
    func remove(_ progress: TeamAccountDeletionProgress) throws {
        try lock.withLock {
            let storageKey = progress.binding.accountID
            guard values[storageKey] == progress else {
                throw TeamWorkspaceError.bindingMismatch
            }
            values.removeValue(forKey: storageKey)
        }
    }
}

private final class WorkspaceFailingProgressStore:
    TeamAccountDeletionProgressStoring, @unchecked Sendable {
    let base: WorkspaceDeletionProgressMemory
    private let failPhase: TeamAccountDeletionPhase
    init(base: WorkspaceDeletionProgressMemory, failPhase: TeamAccountDeletionPhase) {
        self.base = base; self.failPhase = failPhase
    }
    func load(accountID: String) throws -> TeamAccountDeletionProgress? {
        try base.load(accountID: accountID)
    }
    func loadAll() throws -> [TeamAccountDeletionProgress] { try base.loadAll() }
    func save(_ progress: TeamAccountDeletionProgress) throws {
        if progress.phase == failPhase { throw WorkspaceStubError.stopped }
        try base.save(progress)
    }
    func remove(_ progress: TeamAccountDeletionProgress) throws { try base.remove(progress) }
}

private final class WorkspaceDeletionCredentials:
    TeamAccountDeletionCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: (TeamAccountDeletionCredentialReference,
                                    TeamAccountDeletionStatusCredential)]()
    func load(_ reference: TeamAccountDeletionCredentialReference) throws
        -> TeamAccountDeletionStatusCredential? {
        try lock.withLock {
            guard let value = values[reference.credentialID] else { return nil }
            guard value.0 == reference else { throw TeamWorkspaceError.bindingMismatch }
            return value.1
        }
    }
    func insert(_ credential: TeamAccountDeletionStatusCredential,
                reference: TeamAccountDeletionCredentialReference) throws -> Bool {
        try lock.withLock {
            if let value = values[reference.credentialID] {
                guard value.0 == reference else { throw TeamWorkspaceError.bindingMismatch }
                return false
            }
            values[reference.credentialID] = (reference, credential)
            return true
        }
    }
    func remove(_ reference: TeamAccountDeletionCredentialReference) throws {
        try lock.withLock {
            if let value = values[reference.credentialID] {
                guard value.0 == reference else { throw TeamWorkspaceError.bindingMismatch }
                values.removeValue(forKey: reference.credentialID)
            }
        }
    }
    func contains(_ reference: TeamAccountDeletionCredentialReference) -> Bool {
        lock.withLock { values[reference.credentialID]?.0 == reference }
    }
}

private final class WorkspaceSecureCleanup: TeamAccountSecureCustodyDeleting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var failureAfterSideEffect: TeamAccountDeletionCleanupStep?
    private var remaining: [String: Set<TeamAccountDeletionCleanupStep>]
    private var attempts = [String: [TeamAccountDeletionCleanupStep]]()
    private var bindings = [TeamAccountDeletionBinding]()
    init(accounts: [String] = ["alice"],
         failAfterSideEffectOnceAt: TeamAccountDeletionCleanupStep? = nil) {
        remaining = Dictionary(uniqueKeysWithValues: accounts.map {
            ($0, Set(TeamAccountDeletionCleanupStep.allCases))
        })
        failureAfterSideEffect = failAfterSideEffectOnceAt
    }
    func remainingSteps(accountID: String) -> Set<TeamAccountDeletionCleanupStep> {
        lock.withLock { remaining[accountID] ?? [] }
    }
    func attemptedSteps(accountID: String) -> [TeamAccountDeletionCleanupStep] {
        lock.withLock { attempts[accountID] ?? [] }
    }
    var observedBindings: [TeamAccountDeletionBinding] { lock.withLock { bindings } }
    func delete(step: TeamAccountDeletionCleanupStep,
                binding: TeamAccountDeletionBinding) throws {
        try lock.withLock {
            guard remaining[binding.accountID] != nil else {
                throw TeamWorkspaceError.bindingMismatch
            }
            attempts[binding.accountID, default: []].append(step)
            bindings.append(binding)
            remaining[binding.accountID]?.remove(step)
            if failureAfterSideEffect == step {
                failureAfterSideEffect = nil
                throw WorkspaceStubError.stopped
            }
        }
    }
}

private actor WorkspaceDeletionTransport:
    TeamAccountDeletionDispatchTransport, TeamAccountDeletionStatusTransport {
    private var dispatchState: TeamAccountDeletionServerState
    private var statusState: TeamAccountDeletionServerState
    private var loseDispatchResponse: Bool
    private let progress: WorkspaceDeletionProgressMemory
    private(set) var requests = [(TeamAccountDeletionBinding, TeamAccountDeletionRequest)]()
    private(set) var statuses = [(TeamAccountDeletionBinding,
                                  TeamAccountDeletionStatusRequest)]()
    private(set) var dispatchObservedPhase: TeamAccountDeletionPhase?

    init(progress: WorkspaceDeletionProgressMemory,
         dispatchState: TeamAccountDeletionServerState = .completed,
         statusState: TeamAccountDeletionServerState = .completed,
         loseDispatchResponse: Bool = false) {
        self.progress = progress; self.dispatchState = dispatchState
        self.statusState = statusState
        self.loseDispatchResponse = loseDispatchResponse
    }
    func requestDeletion(binding: TeamAccountDeletionBinding,
                         request: TeamAccountDeletionRequest) async throws
        -> TeamAccountDeletionStatus {
        requests.append((binding, request))
        dispatchObservedPhase = try progress.load(accountID: binding.accountID)?.phase
        if loseDispatchResponse {
            loseDispatchResponse = false
            throw WorkspaceStubError.stopped
        }
        return try workspaceDeletionStatus(state: dispatchState,
            deletionID: request.requestID, accountID: binding.accountID)
    }
    func deletionStatus(binding: TeamAccountDeletionBinding,
                        request: TeamAccountDeletionStatusRequest) async throws
        -> TeamAccountDeletionStatus {
        statuses.append((binding, request))
        return try workspaceDeletionStatus(state: statusState,
            deletionID: request.deletionID, accountID: binding.accountID)
    }
    func setStatus(_ value: TeamAccountDeletionServerState) { statusState = value }
}

private actor WorkspaceAmbiguousDeletionStatus: TeamAccountDeletionStatusTransport {
    func deletionStatus(binding: TeamAccountDeletionBinding,
                        request: TeamAccountDeletionStatusRequest) async throws
        -> TeamAccountDeletionStatus {
        throw WorkspaceStubError.stopped
    }
}

private func workspaceDeletionStatus(
    state: TeamAccountDeletionServerState,
    deletionID: String = "stable-delete-operation",
    accountID: String = "alice"
) throws -> TeamAccountDeletionStatus {
    switch state {
    case .revocationRequired:
        return try .init(deletionID: deletionID, accountID: accountID,
                         state: state, requestedAt: 10)
    case .cleanupSchedulingRequired:
        return try .init(deletionID: deletionID, accountID: accountID,
                         state: state, requestedAt: 10, authorityRevokedAt: 20)
    case .pendingErasure:
        return try .init(deletionID: deletionID, accountID: accountID,
                         state: state, requestedAt: 10, authorityRevokedAt: 20,
                         cleanupScheduledAt: 30)
    case .completed:
        return try .init(deletionID: deletionID, accountID: accountID,
                         state: state, requestedAt: 10, authorityRevokedAt: 20,
                         cleanupScheduledAt: 30, completedAt: 40,
                         statusExpiresAt: 3_196_800_040)
    }
}

private func workspaceDeletionBinding(
    origin: String = "https://sync.invalid",
    providerID: String = "public-ios",
    authorityEpoch: String = "epoch",
    accountID: String = "alice",
    custodyID: String = "alice-custody"
) throws -> TeamAccountDeletionBinding {
    try .init(origin: origin, providerID: providerID, authorityEpoch: authorityEpoch,
              accountID: accountID, custodyID: custodyID)
}

private func workspaceDeletionCoordinator(
    binding: TeamAccountDeletionBinding,
    transport: WorkspaceDeletionTransport,
    progress: any TeamAccountDeletionProgressStoring,
    credentials: WorkspaceDeletionCredentials,
    cleanup: WorkspaceSecureCleanup,
    operationID: String = "stable-delete-operation",
    credentialID: String = "stable-status-credential"
) throws -> TeamAccountDeletionCoordinator {
    try .init(binding: binding, dispatch: transport, status: transport,
              progressStore: progress, credentialStore: credentials,
              cleanup: cleanup, operationID: { operationID },
              credentialID: { credentialID },
              credentialBytes: { Data(repeating: 0xA5, count: 32) })
}

private actor WorkspaceSignInTransport: TeamAccountSigningIn {
    let pair: TeamAuthSessionPair
    private(set) var challengedProviders = [String]()
    init(accountID: String) {
        pair = .init(accountID: accountID, sessionID: "session",
            accessToken: String(repeating: "C", count: 42) + "A",
            refreshToken: String(repeating: "D", count: 42) + "A",
            accessExpiresAt: 10_000, sessionExpiresAt: 30_000)
    }
    func challenge(providerID: String) async throws -> TeamAuthChallenge {
        challengedProviders.append(providerID)
        return .init(challengeID: String(repeating: "A", count: 43),
            nonce: String(repeating: "B", count: 42) + "A", expiresAt: 5_000)
    }
    func exchange(_ submission: TeamNativeLoginSubmission) async throws -> TeamAuthSessionPair { pair }
}

private struct WorkspaceIdentityStub: TeamNativeIdentityAuthorizing {
    func authorize(_ context: TeamNativeSignInContext) async throws -> TeamNativeIdentityResponse {
        let token = Data("public.header.signature".utf8)
        switch context.provider {
        case .apple: return .apple(state: context.state, token: token)
        case .google: return .google(token: token)
        }
    }
}

private struct WorkspaceAgreementStore: TeamAgreementKeyStoring {
    let sealed: Data
    func load(scope: String) throws -> Data? { sealed }
    func insert(scope: String, sealed: Data) throws -> Bool { false }
}

private final class WorkspaceAgreementKeys: TeamAgreementKeyProviding, @unchecked Sendable {
    let sealed: Data
    let key: P256.KeyAgreement.PrivateKey
    init(sealed: Data, key: P256.KeyAgreement.PrivateKey) {
        self.sealed = sealed; self.key = key
    }
    func generate() throws -> TeamAgreementKeyMaterial {
        .init(sealed: sealed, publicKey: try wire(key.publicKey))
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        guard sealed == self.sealed else { throw TeamAgreementKeyError.keyUnavailable }
        return try wire(key.publicKey)
    }
    func agree(sealed: Data, peer: TeamDeviceEnrollmentWire.PublicKey) throws -> Data {
        guard sealed == self.sealed else { throw TeamAgreementKeyError.keyUnavailable }
        return try key.sharedSecretFromKeyAgreement(with:
            P256.KeyAgreement.PublicKey(x963Representation: peer.key.x963Representation))
            .withUnsafeBytes { Data($0) }
    }
    private func wire(_ key: P256.KeyAgreement.PublicKey) throws
        -> TeamDeviceEnrollmentWire.PublicKey {
        try TeamDeviceEnrollmentWire.publicKey(
            P256.Signing.PublicKey(x963Representation: key.x963Representation))
    }
}

private actor WorkspaceInboxStub: TeamWorkspaceInboxTransport {
    let page: TeamPendingDeliveryPage
    let currentAudience: TeamAudience
    let fetched: TeamWorkspaceFetchedDelivery
    let inbox: TeamInboxStore
    private(set) var acknowledgedAfterArchive = false
    init(page: TeamPendingDeliveryPage, audience: TeamAudience,
         fetched: TeamWorkspaceFetchedDelivery, inbox: TeamInboxStore) {
        self.page = page; currentAudience = audience; self.fetched = fetched; self.inbox = inbox
    }
    func pending(after: TeamDeliveryListCursor?, limit: Int) async throws -> TeamPendingDeliveryPage { page }
    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience { currentAudience }
    func fetch(_ pending: TeamPendingDelivery) async throws -> TeamWorkspaceFetchedDelivery { fetched }
    func acknowledge(_ receipt: PendingTeamReceipt) async throws -> TeamWorkspaceACKReply {
        acknowledgedAfterArchive = try inbox.archived(deliveryId: receipt.deliveryId) != nil
        let binding = TeamDeviceRequestWire.Binding(audience: "https://sync.invalid",
            authorityEpoch: "epoch", accountID: receipt.accountId, sessionID: "session",
            deviceID: receipt.deviceId, enrollmentID: receipt.enrollmentId,
            keyThumbprint: String(repeating: "A", count: 43), operation: .deliveryACK,
            teamID: receipt.teamId, requestID: receipt.deliveryId, accessExpiresAt: 9_000_000)
        return .acknowledged(.init(deliveryID: receipt.deliveryId, settledAt: 200,
            expiresAt: try #require(try inbox.archived(deliveryId: receipt.deliveryId)?.envelope.expiresAt),
            jweSHA256: receipt.jweSHA256, purgeEligible: false), binding)
    }
}

private final class WorkspaceIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values = ["draft-id", "note-id", "delivery-id"]
    func next() -> String { lock.withLock { values.removeFirst() } }
}

private func workspaceTarget() throws -> TeamAudienceTarget {
    let signing = P256.Signing.PrivateKey().publicKey
    let agreement = P256.KeyAgreement.PrivateKey().publicKey
    let signingWire = try TeamDeviceEnrollmentWire.publicKey(signing)
    let agreementWire = try TeamDeviceEnrollmentWire.publicKey(
        P256.Signing.PublicKey(x963Representation: agreement.x963Representation))
    return .init(accountID: "bob", deviceID: "bob-phone",
        enrollmentID: "bob-enrollment", keyThumbprint: signingWire.thumbprint,
        publicKey: signingWire, agreementKeyThumbprint: agreementWire.thumbprint,
        agreementPublicKey: agreementWire)
}

private func withWorkspaceOutbox(_ body: (TeamOutgoingStore, URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pinbook-workspace-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sender = try DeliveryTarget(userId: "alice", deviceId: "alice-phone",
                                    enrollmentId: "alice-enrollment")
    try await body(TeamOutgoingStore(applicationSupportDirectory: root,
        sender: sender, teamId: "team"), root)
}

@Suite struct TeamWorkspaceTests {
    @Test func productionDefaultIsOffAndAppleGoogleUseEquivalentInjectedPath() async throws {
        #expect(!TeamWorkspaceRuntimeConfiguration.productionDefault.isEnabled)
        for (provider, providerID, accountID) in [
            (TeamNativeSignInProvider.apple, "apple-profile", "apple-account"),
            (.google, "google-profile", "google-account")
        ] {
            let keychain = SessionMemoryKeychain()
            let store = TeamAccountSessionStore(testService: "workspace-signin-\(providerID)",
                                                keychain: keychain)
            let transport = WorkspaceSignInTransport(accountID: accountID)
            let composition = TeamWorkspaceAccountComposition(sessions: store,
                                                               transport: transport)
            let scope = try TeamAccountSessionScope(origin: URL(string: "https://sync.invalid")!,
                                                    providerID: providerID)
            let coordinator = composition.signIn(provider: provider, scope: scope,
                identity: WorkspaceIdentityStub(), clock: {
                    TeamSignInMoment(wallTime: 1_000, instant: .now)
                })
            let pair = try await coordinator.signIn(consent: true)
            #expect(pair.accountID == accountID)
            #expect(await transport.challengedProviders == [providerID])
        }
    }

    @Test func lostResponseReconcilesWithoutRestoringOrdinarySession() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: progress,
            statusState: .completed, loseDispatchResponse: true)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: TeamWorkspaceError.invalidInput) {
            try await deletion.delete(confirmation: "DELETE")
        }
        await #expect(throws: WorkspaceStubError.stopped) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        let pending = try #require(try progress.load(accountID: "alice"))
        #expect(pending.phase == .uncertain)
        #expect(credentials.contains(pending.credentialReference))
        #expect(await transport.dispatchObservedPhase == .dispatched)

        let recovery = TeamAccountDeletionAppStartRecovery(status: transport,
            progressStore: progress, credentialStore: credentials, cleanup: cleanup)
        #expect(await recovery.resumeAll() == [
            .init(accountID: "alice", outcome: .completed)
        ])
        #expect(cleanup.remainingSteps(accountID: "alice").isEmpty)
        #expect(try progress.load(accountID: "alice") == nil)
        #expect(!credentials.contains(pending.credentialReference))
        let statuses = await transport.statuses
        #expect(statuses.first?.0 == binding)
        #expect(statuses.first?.1.deletionID == "stable-delete-operation")
        #expect(statuses.first?.1.statusToken.count == 43)
    }

    @Test func deletionGateIsAccountGlobalAcrossTeams() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: progress,
            dispatchState: .revocationRequired)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: TeamWorkspaceError.deletionPending) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        let gate = TeamAccountDeletionStartupGate(progressStore: progress)
        #expect(try gate.blocksTeamActions(accountID: "alice"))
        #expect(throws: TeamWorkspaceError.busy) {
            try gate.requireTeamActionsAllowed(accountID: "alice")
        }
        #expect(!(try gate.blocksTeamActions(accountID: "bob")))
        #expect(cleanup.remainingSteps(accountID: "alice")
            == Set(TeamAccountDeletionCleanupStep.allCases))
    }

    @Test func authorityRevocationStartsCleanupButCompletionStaysServerAuthoritative() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: progress,
            dispatchState: .revocationRequired, statusState: .cleanupSchedulingRequired)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: TeamWorkspaceError.deletionPending) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        await #expect(throws: TeamWorkspaceError.deletionPending) {
            try await deletion.resumePending()
        }
        let locallyClean = try #require(try progress.load(accountID: "alice"))
        #expect(locallyClean.phase == .authorityRevoked)
        #expect(locallyClean.completedSteps == TeamAccountDeletionCleanupStep.allCases)
        #expect(credentials.contains(locallyClean.credentialReference))
        await transport.setStatus(.completed)
        #expect(try await deletion.resumePending())
        #expect(try progress.load(accountID: "alice") == nil)
    }

    @Test func exactRetryReusesRequestIDAndCanonicalStatusToken() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: progress,
            dispatchState: .revocationRequired, loseDispatchResponse: true)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: WorkspaceStubError.stopped) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        await #expect(throws: TeamWorkspaceError.deletionPending) {
            try await deletion.retryExactRequest(confirmation: "DELETE_ACCOUNT")
        }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].1.requestID == requests[1].1.requestID)
        #expect(requests[0].1.statusToken == requests[1].1.statusToken)
        #expect(requests[0].1.statusToken.count == 43)
        #expect(!requests[0].1.statusToken.contains("="))
        let body = try #require(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(requests[0].1)) as? [String: Any])
        #expect(Set(body.keys) == ["type", "requestId", "confirmation", "statusToken"])
        #expect(body["confirmation"] as? String == "DELETE_ACCOUNT")
    }

    @Test func invalidStatusCredentialRemainsAmbiguousAndPreservesCustody() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: progress,
            dispatchState: .revocationRequired)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: TeamWorkspaceError.deletionPending) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        let saved = try #require(try progress.load(accountID: "alice"))
        let recovery = TeamAccountDeletionAppStartRecovery(
            status: WorkspaceAmbiguousDeletionStatus(), progressStore: progress,
            credentialStore: credentials, cleanup: cleanup)
        #expect(await recovery.resumeAll() == [
            .init(accountID: "alice", outcome: .ambiguous)
        ])
        #expect(try progress.load(accountID: "alice")?.phase == .uncertain)
        #expect(credentials.contains(saved.credentialReference))
        #expect(cleanup.remainingSteps(accountID: "alice")
            == Set(TeamAccountDeletionCleanupStep.allCases))
    }

    @Test func failedSynchronousCheckpointPreventsDispatch() async throws {
        let binding = try workspaceDeletionBinding()
        let base = WorkspaceDeletionProgressMemory()
        let failing = WorkspaceFailingProgressStore(base: base, failPhase: .dispatched)
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup()
        let transport = WorkspaceDeletionTransport(progress: base)
        let deletion = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: failing, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: WorkspaceStubError.stopped) {
            try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        }
        #expect(await transport.requests.isEmpty)
        #expect(try base.load(accountID: "alice")?.phase == .prepared)
    }

    @Test func completedDeletionCleansOnlyTheExactAccount() async throws {
        let alice = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup(accounts: ["alice", "bob"])
        let transport = WorkspaceDeletionTransport(progress: progress)
        let deletion = try workspaceDeletionCoordinator(binding: alice,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)

        try await deletion.delete(confirmation: "DELETE_ACCOUNT")
        #expect(cleanup.remainingSteps(accountID: "alice").isEmpty)
        #expect(cleanup.remainingSteps(accountID: "bob")
            == Set(TeamAccountDeletionCleanupStep.allCases))
        #expect(cleanup.observedBindings.allSatisfy { $0 == alice })
        #expect(try progress.load(accountID: "bob") == nil)
    }

    @Test func revokedCleanupIsIdempotentAcrossRestartAfterSideEffect() async throws {
        let binding = try workspaceDeletionBinding()
        let progress = WorkspaceDeletionProgressMemory()
        let credentials = WorkspaceDeletionCredentials()
        let cleanup = WorkspaceSecureCleanup(
            failAfterSideEffectOnceAt: .deviceSigningIdentity)
        let transport = WorkspaceDeletionTransport(progress: progress)
        let first = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        await #expect(throws: WorkspaceStubError.stopped) {
            try await first.delete(confirmation: "DELETE_ACCOUNT")
        }
        let pending = try #require(try progress.load(accountID: "alice"))
        #expect(pending.phase == .serverCompleted)
        #expect(pending.completedSteps == [.teamCacheAndArchive, .agreementIdentity])

        let afterRestart = try workspaceDeletionCoordinator(binding: binding,
            transport: transport, progress: progress, credentials: credentials,
            cleanup: cleanup)
        #expect(try await afterRestart.resumePending())
        #expect(cleanup.attemptedSteps(accountID: "alice")
            .filter { $0 == .deviceSigningIdentity }.count == 2)
        #expect(try progress.load(accountID: "alice") == nil)
    }

    @Test func sqliteJournalIsDurableEnumerableAndBackupExcluded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinbook-deletion-store-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binding = try workspaceDeletionBinding()
        let progress = TeamAccountDeletionProgress(
            version: TeamAccountDeletionProgress.currentVersion,
            binding: binding, operationID: "operation",
            credentialReference: .init(credentialID: "credential",
                                       bindingDigest: binding.digest),
            phase: .prepared, completedSteps: [])
        let store = try SQLiteTeamAccountDeletionProgressStore(
            applicationSupportDirectory: root)
        try store.save(progress)
        #expect(try store.loadAll() == [progress])
        #expect(try store.directoryURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try store.databaseURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let reopened = try SQLiteTeamAccountDeletionProgressStore(
            applicationSupportDirectory: root)
        #expect(try reopened.load(accountID: "alice") == progress)
        let changed = try workspaceDeletionBinding(origin: "https://changed.invalid",
            providerID: "changed-provider", authorityEpoch: "changed-epoch",
            custodyID: "changed-custody")
        let rebound = TeamAccountDeletionProgress(
            version: TeamAccountDeletionProgress.currentVersion,
            binding: changed, operationID: progress.operationID,
            credentialReference: .init(credentialID: "credential",
                                       bindingDigest: changed.digest),
            phase: .prepared, completedSteps: [])
        #expect(throws: TeamWorkspaceError.bindingMismatch) { try reopened.save(rebound) }
    }

    @Test func termsAreExactScopeVersionedAndRequiredBeforeUpload() throws {
        let storage = WorkspaceTermsMemory(), gate = TeamTermsGate(store: storage)
        #expect(throws: TeamWorkspaceError.termsRequired) {
            try gate.requireAccepted(accountID: "alice", teamID: "team")
        }
        #expect(throws: TeamWorkspaceError.termsRequired) {
            try gate.accept(accountID: "alice", teamID: "team", acceptedAt: 10,
                            explicitConsent: false)
        }
        let accepted = try gate.accept(accountID: "alice", teamID: "team",
            acceptedAt: 10, explicitConsent: true)
        #expect(accepted.version == TeamTermsAcceptance.currentVersion)
        #expect(try gate.requireAccepted(accountID: "alice", teamID: "team") == accepted)
    }

    @Test func invitationQRAndShareUseOneCanonicalUniversalLink() throws {
        let token = TeamDeviceEnrollmentWire.encode(Data(repeating: 7, count: 32))
        let issued = TeamIssuedInvitation(preview: .init(inviteID: "invite",
            teamID: "team", role: .member, expiresAt: 1_000), token: token)
        let item = try TeamInvitationShareItem(origin: "https://sync.invalid", issued: issued)
        #expect(String(decoding: item.qrPayload, as: UTF8.self) == item.url.absoluteString)
        #expect(item.url.absoluteString == "https://sync.invalid/join?invite=\(token)")
        #expect(!item.description.contains(token))
    }

    @Test func encryptedOutboxPersistsExactRetryAndTermsBlockAllWork() async throws {
        try await withWorkspaceOutbox { outbox, _ in
            let termsStorage = WorkspaceTermsMemory()
            let terms = TeamTermsGate(store: termsStorage)
            let audience = TeamAudience(teamID: "team", membershipRevision: 3,
                                        targets: [try workspaceTarget()])
            let transport = WorkspaceSubmissionStub(), ids = WorkspaceIDs()
            let coordinator = try TeamManualNoteSendCoordinator(accountID: "alice",
                teamID: "team", enrollmentID: "alice-enrollment", outbox: outbox,
                terms: terms, audience: WorkspaceAudienceStub(audience),
                transport: transport, now: { 100 }, identifier: { ids.next() })

            await #expect(throws: TeamWorkspaceError.termsRequired) {
                try await coordinator.queueAndSubmit(body: "private text")
            }
            #expect(try outbox.pendingEvents().isEmpty)

            _ = try terms.accept(accountID: "alice", teamID: "team",
                acceptedAt: 99, explicitConsent: true)
            await #expect(throws: WorkspaceStubError.stopped) {
                try await coordinator.queueAndSubmit(body: "private text")
            }
            let event = try #require(try outbox.pendingEvents().first)
            let encrypted = try #require(try outbox.encryptedSubmission(eventId: event.eventId))
            #expect(!encrypted.canonicalJWE.contains("private text"))
            await #expect(throws: WorkspaceStubError.stopped) {
                try await coordinator.retryNext()
            }
            let hashes = await transport.hashes
            #expect(hashes.count == 2 && hashes[0] == hashes[1])
            #expect(try outbox.encryptedSubmission(eventId: event.eventId) == encrypted)
        }
    }

    @Test func onlyExactAcceptedHashRetiresEncryptedOutbox() async throws {
        try await withWorkspaceOutbox { outbox, _ in
            let draft = try outbox.createDraft(draftId: "draft", noteId: "note",
                kind: .noteSubmission, baseRevision: nil, body: "hello", createdAt: 1)
            let event = try outbox.finalizeDraft(draftId: draft.draftId,
                expectedVersion: draft.version, eventId: "delivery", finalizedAt: 2)
            let audience = TeamAudience(teamID: "team", membershipRevision: 4,
                                        targets: [try workspaceTarget()])
            let plan = try TeamManualNotePlanner.plan(event: event, audience: audience)
            _ = try outbox.saveEncryptedSubmission(event: event, intent: plan.intent,
                canonicalJWE: String(decoding: plan.request.jwe, as: UTF8.self), createdAt: 3)
            #expect(throws: TeamOutgoingError.immutableConflict) {
                try outbox.retireAcceptedSubmission(eventId: event.eventId,
                    expectedJWESHA256: String(repeating: "0", count: 64))
            }
            try outbox.retireAcceptedSubmission(eventId: event.eventId,
                expectedJWESHA256: plan.intent.jweSha256)
            #expect(try outbox.pendingEvents().isEmpty)
            #expect(try outbox.encryptedSubmission(eventId: event.eventId) == nil)
        }
    }

    @Test func safetyRejectsSelfBlankAndOversizedBeforeInjectedTransport() async throws {
        let transport = WorkspaceSafetyStub()
        let coordinator = try TeamSafetyCoordinator(accountID: "alice", teamID: "team",
                                                     transport: transport)
        await #expect(throws: TeamWorkspaceError.invalidInput) {
            try await coordinator.execute(.blockUser(userID: "alice"))
        }
        await #expect(throws: TeamWorkspaceError.invalidInput) {
            try await coordinator.execute(.reportUser(userID: "bob", reason: " "))
        }
        try await coordinator.execute(.reportNote(noteID: "note", authorID: "bob",
                                                  reason: "Unwanted content"))
        #expect(await transport.actions == [
            .reportNote(noteID: "note", authorID: "bob", reason: "Unwanted content")
        ])
    }

    @Test func foregroundRefreshArchivesBeforeACKAndClearsOnlyReceipt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinbook-workspace-inbox-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try DeliveryTarget(userId: "bob", deviceId: "bob-phone",
                                        enrollmentId: "bob-enrollment")
        let inbox = try TeamInboxStore(applicationSupportDirectory: root,
                                       target: target, teamId: "team")
        let privateKey = P256.KeyAgreement.PrivateKey(), sealed = Data("sealed".utf8)
        let keys = WorkspaceAgreementKeys(sealed: sealed, key: privateKey)
        let custody = try TeamAgreementKeyCustody(origin: "https://sync.invalid",
            accountID: "bob", authorityEpoch: "epoch", enrollmentID: "bob-enrollment",
            storage: WorkspaceAgreementStore(sealed: sealed), keys: keys,
            requireAccess: {})
        let local = try custody.current()
        let acceptedAt: Int64 = 100
        let expiresAt = try TeamDeliveryRules.expiresAt(acceptedAt: acceptedAt)
        let payload = TeamDeliveryPayload(teamId: "team", deliveryId: "delivery",
            noteId: "note", authorUserId: "alice", body: "encrypted hello",
            bodySha256: TeamDeliveryRules.textSHA256("encrypted hello"))
        let jwe = try TeamDeliveryJWE().encrypt(TeamDeliveryPayloadCodec.encode(payload),
                                                recipients: [local])
        let jweBytes = Data(jwe.utf8)
        let jweHash = SHA256.hash(data: jweBytes).map { String(format: "%02x", $0) }.joined()
        let audienceBytes = try JSONSerialization.data(withJSONObject: [local.keyThumbprint],
                                                        options: [.withoutEscapingSlashes])
        let audienceDigest = TeamDeviceEnrollmentWire.encode(Data(SHA256.hash(data: audienceBytes)))
        let pending = TeamPendingDelivery(deliveryID: "delivery", acceptedAt: acceptedAt,
            expiresAt: expiresAt, jweBytes: jweBytes.count, jweSHA256: jweHash,
            senderAccountID: "alice", senderDeviceID: "alice-phone",
            senderEnrollmentID: "alice-enrollment", audienceDigest: audienceDigest,
            agreementKeyThumbprint: local.keyThumbprint)
        let fetchBinding = TeamDeviceRequestWire.Binding(audience: "https://sync.invalid",
            authorityEpoch: "epoch", accountID: "bob", sessionID: "session",
            deviceID: "bob-phone", enrollmentID: "bob-enrollment",
            keyThumbprint: String(repeating: "A", count: 43), operation: .deliveryFetch,
            teamID: "team", requestID: "delivery", accessExpiresAt: 9_000_000)
        let fetched = TeamWorkspaceFetchedDelivery(pending: pending,
            result: .init(deliveryID: "delivery", acceptedAt: acceptedAt,
                expiresAt: expiresAt, jweBytes: jweBytes.count, jweSHA256: jweHash,
                audienceDigest: audienceDigest, agreementKeyThumbprint: local.keyThumbprint,
                jwe: jweBytes), binding: fetchBinding)
        let sender = try workspaceTarget()
        let current = TeamAudience(teamID: "team", membershipRevision: 1,
            targets: [.init(accountID: "alice", deviceID: "alice-phone",
                enrollmentID: "alice-enrollment", keyThumbprint: sender.keyThumbprint,
                publicKey: sender.publicKey,
                agreementKeyThumbprint: sender.agreementKeyThumbprint,
                agreementPublicKey: sender.agreementPublicKey)])
        let transport = WorkspaceInboxStub(page: .init(deliveries: [pending],
            hasMore: false, nextCursor: nil), audience: current,
            fetched: fetched, inbox: inbox)
        let coordinator = try TeamForegroundInboxCoordinator(teamID: "team",
            enrollmentID: "bob-enrollment", inbox: inbox, custody: custody,
            transport: transport, now: { 150 })
        #expect(try await coordinator.refresh() == 1)
        #expect(await transport.acknowledgedAfterArchive)
        #expect(try inbox.pendingReceipts().isEmpty)
        #expect(try inbox.archived(deliveryId: "delivery")?.envelope.body == "encrypted hello")
    }
}
