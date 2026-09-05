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

private actor WorkspaceRemoteStub: TeamWorkspaceRemoteTransport {
    private(set) var deletionAttempts = [(String, String)]()
    private var rejectDeletion: Bool
    init(rejectDeletion: Bool = false) { self.rejectDeletion = rejectDeletion }
    func allowDeletion() { rejectDeletion = false }
    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience {
        throw WorkspaceStubError.stopped
    }
    func reserve(_ plan: TeamWorkspaceSendPlan) async throws -> TeamDeliverySubmissionReservation {
        throw WorkspaceStubError.stopped
    }
    func status(deliveryID: String, jweSHA256: String) async throws -> TeamDeliverySubmissionStatus {
        throw WorkspaceStubError.stopped
    }
    func pending(after: TeamDeliveryListCursor?, limit: Int) async throws -> TeamPendingDeliveryPage {
        throw WorkspaceStubError.stopped
    }
    func fetch(_ pending: TeamPendingDelivery) async throws -> TeamWorkspaceFetchedDelivery {
        throw WorkspaceStubError.stopped
    }
    func acknowledge(_ receipt: PendingTeamReceipt) async throws -> TeamWorkspaceACKReply {
        throw WorkspaceStubError.stopped
    }
    func execute(accountID: String, teamID: String, action: TeamSafetyAction) async throws {
        throw WorkspaceStubError.stopped
    }
    func deleteAccount(accountID: String, operationID: String) async throws {
        deletionAttempts.append((accountID, operationID))
        if rejectDeletion { throw WorkspaceStubError.stopped }
    }
}

private final class WorkspaceDeletionProgressMemory:
    TeamAccountDeletionProgressStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TeamAccountDeletionProgress?
    func load(accountID: String, teamID: String) throws -> TeamAccountDeletionProgress? {
        lock.withLock { value }
    }
    func save(_ progress: TeamAccountDeletionProgress) throws {
        lock.withLock { value = progress }
    }
    func remove(_ progress: TeamAccountDeletionProgress) throws {
        try lock.withLock {
            guard value == progress else { throw TeamWorkspaceError.bindingMismatch }
            value = nil
        }
    }
}

private final class WorkspaceSecureCleanup: TeamAccountSecureCustodyDeleting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var failure: TeamAccountDeletionCleanupStep?
    private var completed = [TeamAccountDeletionCleanupStep]()
    init(failOnceAt: TeamAccountDeletionCleanupStep? = nil) { failure = failOnceAt }
    var steps: [TeamAccountDeletionCleanupStep] { lock.withLock { completed } }
    func delete(step: TeamAccountDeletionCleanupStep,
                accountID: String, teamID: String) throws {
        try lock.withLock {
            guard accountID == "alice", teamID == "team" else {
                throw TeamWorkspaceError.bindingMismatch
            }
            if failure == step { failure = nil; throw WorkspaceStubError.stopped }
            if !completed.contains(step) { completed.append(step) }
        }
    }
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

    @Test func rejectedDeletionPreservesLocalMaterialThenRetriesSameOperation() async throws {
        let progress = WorkspaceDeletionProgressMemory()
        let cleanup = WorkspaceSecureCleanup()
        let remote = WorkspaceRemoteStub(rejectDeletion: true)
        let deletion = try TeamAccountDeletionCoordinator(accountID: "alice", teamID: "team",
            transport: remote, progressStore: progress, cleanup: cleanup,
            operationID: { "stable-delete-operation" })
        await #expect(throws: TeamWorkspaceError.invalidInput) {
            try await deletion.delete(confirmation: "delete")
        }
        await #expect(throws: WorkspaceStubError.stopped) {
            try await deletion.delete(confirmation: "DELETE")
        }
        #expect(cleanup.steps.isEmpty)
        let pending = try #require(try progress.load(accountID: "alice", teamID: "team"))
        #expect(!pending.remoteAccepted && pending.completedSteps.isEmpty)
        await remote.allowDeletion()
        #expect(try await deletion.resumePending())
        let attempts = await remote.deletionAttempts
        #expect(attempts.count == 2 && attempts.allSatisfy {
            $0.0 == "alice" && $0.1 == "stable-delete-operation"
        })
        #expect(cleanup.steps == TeamAccountDeletionCleanupStep.allCases)
        #expect(try progress.load(accountID: "alice", teamID: "team") == nil)
    }

    @Test func cleanupFailureRemainsDurableAndRestartResumesWithoutRemoteReplay() async throws {
        let progress = WorkspaceDeletionProgressMemory()
        let cleanup = WorkspaceSecureCleanup(failOnceAt: .deviceSigningIdentity)
        let remote = WorkspaceRemoteStub()
        let first = try TeamAccountDeletionCoordinator(accountID: "alice", teamID: "team",
            transport: remote, progressStore: progress, cleanup: cleanup,
            operationID: { "restartable-delete-operation" })
        await #expect(throws: WorkspaceStubError.stopped) {
            try await first.delete(confirmation: "DELETE")
        }
        let pending = try #require(try progress.load(accountID: "alice", teamID: "team"))
        #expect(pending.remoteAccepted)
        #expect(pending.completedSteps == [.teamCacheAndArchive, .agreementIdentity])

        let afterRestart = try TeamAccountDeletionCoordinator(accountID: "alice", teamID: "team",
            transport: remote, progressStore: progress, cleanup: cleanup)
        #expect(try await afterRestart.resumePending())
        #expect(await remote.deletionAttempts.count == 1)
        #expect(cleanup.steps == TeamAccountDeletionCleanupStep.allCases)
        #expect(try progress.load(accountID: "alice", teamID: "team") == nil)
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
