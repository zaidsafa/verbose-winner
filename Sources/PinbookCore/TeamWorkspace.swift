import CryptoKit
import Foundation

enum TeamWorkspaceError: Error, Equatable {
    case invalidInput
    case termsRequired
    case busy
    case unavailable
    case bindingMismatch
}

struct TeamTermsAcceptance: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let accountID: String
    let teamID: String
    let version: Int
    let acceptedAt: Int64
}

protocol TeamTermsStoring: Sendable {
    func load(accountID: String, teamID: String) throws -> TeamTermsAcceptance?
    func save(_ acceptance: TeamTermsAcceptance) throws
    func remove(accountID: String, teamID: String) throws
}

/// Device-local, non-synchronizing consent record. It contains no invitation,
/// session, note or provider credential.
final class UserDefaultsTeamTermsStore: TeamTermsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    init(suiteName: String = "com.zaidsafa.pinbook.team-terms.v1") throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TeamWorkspaceError.unavailable
        }
        self.defaults = defaults
    }
    func load(accountID: String, teamID: String) throws -> TeamTermsAcceptance? {
        try validate(accountID, teamID)
        return try lock.withLock {
            guard let data = defaults.data(forKey: key(accountID, teamID)) else { return nil }
            let value = try JSONDecoder().decode(TeamTermsAcceptance.self, from: data)
            guard value.accountID == accountID, value.teamID == teamID,
                  value.version == TeamTermsAcceptance.currentVersion,
                  value.acceptedAt >= 0 else { throw TeamWorkspaceError.bindingMismatch }
            return value
        }
    }
    func save(_ acceptance: TeamTermsAcceptance) throws {
        try validate(acceptance.accountID, acceptance.teamID)
        guard acceptance.version == TeamTermsAcceptance.currentVersion,
              acceptance.acceptedAt >= 0 else { throw TeamWorkspaceError.invalidInput }
        let data = try JSONEncoder().encode(acceptance)
        lock.withLock { defaults.set(data, forKey: key(acceptance.accountID, acceptance.teamID)) }
    }
    func remove(accountID: String, teamID: String) throws {
        try validate(accountID, teamID)
        lock.withLock { defaults.removeObject(forKey: key(accountID, teamID)) }
    }
    private func key(_ accountID: String, _ teamID: String) -> String {
        let digest = SHA256.hash(data: Data((accountID + "\u{0}" + teamID).utf8))
        return "terms." + digest.map { String(format: "%02x", $0) }.joined()
    }
    private func validate(_ accountID: String, _ teamID: String) throws {
        guard TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(teamID) else {
            throw TeamWorkspaceError.invalidInput
        }
    }
}

struct TeamTermsGate: Sendable {
    let store: any TeamTermsStoring
    func accept(accountID: String, teamID: String, acceptedAt: Int64,
                explicitConsent: Bool) throws -> TeamTermsAcceptance {
        guard explicitConsent, acceptedAt >= 0 else { throw TeamWorkspaceError.termsRequired }
        let value = TeamTermsAcceptance(accountID: accountID, teamID: teamID,
            version: TeamTermsAcceptance.currentVersion, acceptedAt: acceptedAt)
        try store.save(value)
        return value
    }
    func requireAccepted(accountID: String, teamID: String) throws -> TeamTermsAcceptance {
        guard let value = try store.load(accountID: accountID, teamID: teamID),
              value.version == TeamTermsAcceptance.currentVersion else {
            throw TeamWorkspaceError.termsRequired
        }
        return value
    }
}

/// A validated Universal Link is the single source for both QR and ShareLink.
/// The raw invitation token is never separately copied into presentation state.
struct TeamInvitationShareItem: Equatable, Sendable, CustomStringConvertible,
                                CustomDebugStringConvertible, CustomReflectable {
    let url: URL
    let qrPayload: Data
    init(origin: String, issued: TeamIssuedInvitation) throws {
        let link = try TeamInvitationLink(origin: origin, token: issued.token)
        url = link.url
        qrPayload = Data(link.url.absoluteString.utf8)
        guard qrPayload.count <= TeamInvitationLink.maximumURLBytes else {
            throw TeamWorkspaceError.invalidInput
        }
    }
    var description: String { "TeamInvitationShareItem(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamWorkspaceSendPlan: Sendable, CustomStringConvertible,
                              CustomDebugStringConvertible, CustomReflectable {
    let event: PendingTeamOutgoingEvent
    let audience: TeamAudience
    let intent: TeamDeliverySubmitIntent
    let request: TeamDeliveryReservationRequest
    var description: String { "TeamWorkspaceSendPlan(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum TeamManualNotePlanner {
    static func plan(event: PendingTeamOutgoingEvent,
                     audience: TeamAudience) throws -> TeamWorkspaceSendPlan {
        guard event.kind == .noteSubmission, event.baseRevision == nil,
              event.teamId == audience.teamID,
              (1...TeamDeliveryRules.maximumRecipients).contains(audience.targets.count) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        let recipients = audience.targets.map {
            TeamAgreementPublic(keyThumbprint: $0.agreementKeyThumbprint,
                                publicKey: $0.agreementPublicKey)
        }
        let payload = TeamDeliveryPayload(teamId: event.teamId,
            deliveryId: event.eventId, noteId: event.noteId,
            authorUserId: event.accountId, body: event.body,
            bodySha256: TeamDeliveryRules.textSHA256(event.body))
        var plaintext = try TeamDeliveryPayloadCodec.encode(payload)
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        let jwe = try TeamDeliveryJWE().encrypt(plaintext, recipients: recipients)
        let digest = try audienceDigest(recipients.map(\.keyThumbprint))
        let intent = try TeamDeliverySubmitIntentCodec.fromCanonicalJWE(
            deliveryId: event.eventId, membershipRevision: audience.membershipRevision,
            audienceDigest: digest, serialized: jwe)
        let request = try TeamDeliveryReservationRequest(intent: intent, canonicalJWE: jwe)
        return .init(event: event, audience: audience, intent: intent, request: request)
    }

    static func restore(event: PendingTeamOutgoingEvent,
                        audience: TeamAudience,
                        saved: PendingTeamEncryptedSubmission) throws -> TeamWorkspaceSendPlan {
        guard saved.accountId == event.accountId, saved.teamId == event.teamId,
              saved.deviceId == event.deviceId, saved.enrollmentId == event.enrollmentId,
              saved.eventId == event.eventId,
              saved.bodySHA256 == TeamDeliveryRules.textSHA256(event.body) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        let recipients = audience.targets.map {
            TeamAgreementPublic(keyThumbprint: $0.agreementKeyThumbprint,
                                publicKey: $0.agreementPublicKey)
        }
        let digest = try audienceDigest(recipients.map(\.keyThumbprint))
        let intent = try TeamDeliverySubmitIntentCodec.decode(saved.canonicalIntent,
            expectedDeliveryId: event.eventId,
            expectedMembershipRevision: audience.membershipRevision,
            expectedAudienceDigest: digest)
        let request = try TeamDeliveryReservationRequest(intent: intent,
            canonicalJWE: saved.canonicalJWE)
        return .init(event: event, audience: audience, intent: intent, request: request)
    }

    private static func audienceDigest(_ keys: [String]) throws -> String {
        let ordered = keys.sorted()
        guard Set(ordered).count == ordered.count else { throw TeamWorkspaceError.invalidInput }
        let bytes = try JSONSerialization.data(withJSONObject: ordered,
            options: [.withoutEscapingSlashes])
        return TeamDeviceEnrollmentWire.encode(Data(SHA256.hash(data: bytes)))
    }
}

protocol TeamWorkspaceAudienceProviding: Sendable {
    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience
}
extension TeamAudienceLookup: TeamWorkspaceAudienceProviding {}

protocol TeamWorkspaceSubmissionTransport: Sendable {
    func reserve(_ plan: TeamWorkspaceSendPlan) async throws -> TeamDeliverySubmissionReservation
    func status(deliveryID: String, jweSHA256: String) async throws -> TeamDeliverySubmissionStatus
}

/// Every public operation is user-triggered. Failures retain the exact plaintext
/// event and, once created, the exact encrypted submission for manual retry.
actor TeamManualNoteSendCoordinator {
    private let accountID: String
    private let teamID: String
    private let enrollmentID: String
    private let outbox: TeamOutgoingStore
    private let terms: TeamTermsGate
    private let audience: any TeamWorkspaceAudienceProviding
    private let transport: any TeamWorkspaceSubmissionTransport
    private let now: @Sendable () -> Int64
    private let identifier: @Sendable () -> String
    private var working = false

    init(accountID: String, teamID: String, enrollmentID: String,
         outbox: TeamOutgoingStore, terms: TeamTermsGate,
         audience: any TeamWorkspaceAudienceProviding,
         transport: any TeamWorkspaceSubmissionTransport,
         now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
         identifier: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) throws {
        guard accountID == outbox.sender.userId, teamID == outbox.teamId,
              enrollmentID == outbox.sender.enrollmentId else {
            throw TeamWorkspaceError.bindingMismatch
        }
        self.accountID = accountID; self.teamID = teamID
        self.enrollmentID = enrollmentID; self.outbox = outbox; self.terms = terms
        self.audience = audience; self.transport = transport
        self.now = now; self.identifier = identifier
    }

    func queueAndSubmit(body: String) async throws -> TeamDeliverySubmissionReservation {
        _ = try terms.requireAccepted(accountID: accountID, teamID: teamID)
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        let createdAt = now()
        let draftID = identifier(), noteID = identifier(), eventID = identifier()
        let draft = try outbox.createDraft(draftId: draftID, noteId: noteID,
            kind: .noteSubmission, baseRevision: nil, body: body, createdAt: createdAt)
        let event = try outbox.finalizeDraft(draftId: draft.draftId,
            expectedVersion: draft.version, eventId: eventID, finalizedAt: createdAt)
        return try await submit(event)
    }

    func retryNext() async throws -> TeamDeliverySubmissionReservation? {
        _ = try terms.requireAccepted(accountID: accountID, teamID: teamID)
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        guard let event = try outbox.pendingEvents(limit: 1).first else { return nil }
        return try await submit(event)
    }

    func refreshNextStatus() async throws -> TeamDeliverySubmissionStatus? {
        _ = try terms.requireAccepted(accountID: accountID, teamID: teamID)
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        guard let event = try outbox.pendingEvents(limit: 1).first,
              let saved = try outbox.encryptedSubmission(eventId: event.eventId) else { return nil }
        let object = try TeamStrictJSON.object(saved.canonicalIntent,
            maximumBytes: TeamDeliverySubmitIntentCodec.maximumIntentBytes)
        let digest = try TeamAuthWire.string(object, "jweSha256")
        let result = try await transport.status(deliveryID: event.eventId,
            jweSHA256: digest)
        if result.state == .accepted || result.state == .cleanupPending || result.state == .purged {
            try outbox.retireAcceptedSubmission(eventId: event.eventId,
                expectedJWESHA256: digest)
        }
        return result
    }

    private func submit(_ event: PendingTeamOutgoingEvent) async throws
        -> TeamDeliverySubmissionReservation {
        let current = try await audience.audience(teamID: teamID, enrollmentID: enrollmentID)
        let plan: TeamWorkspaceSendPlan
        if let saved = try outbox.encryptedSubmission(eventId: event.eventId) {
            plan = try TeamManualNotePlanner.restore(event: event, audience: current, saved: saved)
        } else {
            plan = try TeamManualNotePlanner.plan(event: event, audience: current)
            _ = try outbox.saveEncryptedSubmission(event: event, intent: plan.intent,
                canonicalJWE: String(decoding: plan.request.jwe, as: UTF8.self), createdAt: now())
        }
        let result = try await transport.reserve(plan)
        if result.state == .accepted || result.state == .cleanupPending || result.state == .purged {
            try outbox.retireAcceptedSubmission(eventId: event.eventId,
                expectedJWESHA256: plan.intent.jweSha256)
        }
        return result
    }
}

struct TeamWorkspaceFetchedDelivery: Sendable {
    let pending: TeamPendingDelivery
    let result: TeamDeliveryFetchResult
    let binding: TeamDeviceRequestWire.Binding
}
enum TeamWorkspaceACKReply: Sendable {
    case acknowledged(TeamDeliveryACKResult, TeamDeviceRequestWire.Binding)
    case terminal(TeamDeviceRequestWire.Binding)
}
protocol TeamWorkspaceInboxTransport: Sendable {
    func pending(after: TeamDeliveryListCursor?, limit: Int) async throws -> TeamPendingDeliveryPage
    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience
    func fetch(_ pending: TeamPendingDelivery) async throws -> TeamWorkspaceFetchedDelivery
    func acknowledge(_ receipt: PendingTeamReceipt) async throws -> TeamWorkspaceACKReply
}

/// One bounded foreground refresh. There is no timer, push dependency or
/// automatic retry; archived notes and pending ACK receipts remain durable.
actor TeamForegroundInboxCoordinator {
    private let teamID: String
    private let enrollmentID: String
    private let inbox: TeamInboxStore
    private let custody: TeamAgreementKeyCustody
    private let transport: any TeamWorkspaceInboxTransport
    private let now: @Sendable () -> Int64
    private var working = false

    init(teamID: String, enrollmentID: String, inbox: TeamInboxStore,
         custody: TeamAgreementKeyCustody,
         transport: any TeamWorkspaceInboxTransport,
         now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) throws {
        guard teamID == inbox.teamId, enrollmentID == inbox.target.enrollmentId else {
            throw TeamWorkspaceError.bindingMismatch
        }
        self.teamID = teamID; self.enrollmentID = enrollmentID
        self.inbox = inbox; self.custody = custody; self.transport = transport; self.now = now
    }

    func refresh(limit: Int = 20) async throws -> Int {
        guard !working else { throw TeamWorkspaceError.busy }
        guard (1...50).contains(limit) else { throw TeamWorkspaceError.invalidInput }
        working = true; defer { working = false }
        let page = try await transport.pending(after: nil, limit: limit)
        var imported = 0
        for pending in page.deliveries {
            let current = try await transport.audience(teamID: teamID,
                enrollmentID: enrollmentID)
            let local = try custody.current()
            let recipients = [local] + current.targets
                .filter { $0.accountID != pending.senderAccountID }
                .map { TeamAgreementPublic(keyThumbprint: $0.agreementKeyThumbprint,
                                           publicKey: $0.agreementPublicKey) }
            let fetched = try await transport.fetch(pending)
            guard fetched.pending == pending else { throw TeamWorkspaceError.bindingMismatch }
            _ = try TeamDeliveryReceiveCoordinator().archiveFetched(fetched.result,
                pending: pending, expectedBinding: fetched.binding,
                expectedRecipients: recipients, custody: custody, inbox: inbox,
                savedAt: now())
            imported += 1
        }
        for receipt in try inbox.pendingReceipts(limit: 100) {
            switch try await transport.acknowledge(receipt) {
            case .acknowledged(let result, let binding):
                _ = try TeamDeliveryReceiptCoordinator().apply(result, receipt: receipt,
                    expectedBinding: binding, inbox: inbox)
            case .terminal(let binding):
                _ = try TeamDeliveryReceiptCoordinator().applyAuthenticatedTerminal(
                    .server(.terminal), receipt: receipt, expectedBinding: binding, inbox: inbox)
            }
        }
        return imported
    }
}

enum TeamSafetyAction: Equatable, Sendable {
    case reportNote(noteID: String, authorID: String, reason: String)
    case reportUser(userID: String, reason: String)
    case blockUser(userID: String)
}
protocol TeamSafetyTransport: Sendable {
    func execute(accountID: String, teamID: String, action: TeamSafetyAction) async throws
}

/// Interface-only until the server freezes moderation routes. No guessed URL or
/// HTTP shape exists in the app.
actor TeamSafetyCoordinator {
    private let accountID: String
    private let teamID: String
    private let transport: any TeamSafetyTransport
    private var working = false
    init(accountID: String, teamID: String, transport: any TeamSafetyTransport) throws {
        guard TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(teamID) else {
            throw TeamWorkspaceError.invalidInput
        }
        self.accountID = accountID; self.teamID = teamID; self.transport = transport
    }
    func execute(_ action: TeamSafetyAction) async throws {
        guard !working else { throw TeamWorkspaceError.busy }
        try Self.validate(action, accountID: accountID)
        working = true; defer { working = false }
        try await transport.execute(accountID: accountID, teamID: teamID, action: action)
    }
    private static func validate(_ action: TeamSafetyAction, accountID: String) throws {
        let userID: String
        let reason: String?
        switch action {
        case .reportNote(let noteID, let authorID, let value):
            guard TeamAuthWire.identifier(noteID) else { throw TeamWorkspaceError.invalidInput }
            userID = authorID; reason = value
        case .reportUser(let value, let text): userID = value; reason = text
        case .blockUser(let value): userID = value; reason = nil
        }
        guard TeamAuthWire.identifier(userID), userID != accountID else {
            throw TeamWorkspaceError.invalidInput
        }
        if let reason {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == reason, reason.utf8.count <= 500 else {
                throw TeamWorkspaceError.invalidInput
            }
        }
    }
}

protocol TeamAccountDeletionTransport: Sendable {
    /// A successful return is authenticated acceptance of this exact idempotent
    /// operation. Retrying the same operation ID must return the same outcome.
    func deleteAccount(accountID: String, operationID: String) async throws
}

enum TeamAccountDeletionCleanupStep: String, Codable, CaseIterable, Sendable {
    case teamCacheAndArchive
    case agreementIdentity
    case deviceSigningIdentity
    case termsAcceptance
    case accountSession
}

struct TeamAccountDeletionProgress: Codable, Equatable, Sendable {
    let accountID: String
    let teamID: String
    let operationID: String
    var remoteAccepted: Bool
    var completedSteps: [TeamAccountDeletionCleanupStep]
}

protocol TeamAccountDeletionProgressStoring: Sendable {
    func load(accountID: String, teamID: String) throws -> TeamAccountDeletionProgress?
    func save(_ progress: TeamAccountDeletionProgress) throws
    func remove(_ progress: TeamAccountDeletionProgress) throws
}

/// Device-local restart journal. It contains identifiers and cleanup progress,
/// never credentials, invitation tokens, note content or cryptographic material.
final class UserDefaultsTeamAccountDeletionProgressStore:
    TeamAccountDeletionProgressStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    init(suiteName: String = "com.zaidsafa.pinbook.team-account-deletion.v1") throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TeamWorkspaceError.unavailable
        }
        self.defaults = defaults
    }
    func load(accountID: String, teamID: String) throws -> TeamAccountDeletionProgress? {
        try Self.validateIdentity(accountID, teamID)
        return try lock.withLock {
            guard let data = defaults.data(forKey: key(accountID, teamID)) else { return nil }
            let value = try JSONDecoder().decode(TeamAccountDeletionProgress.self, from: data)
            try Self.validate(value)
            guard value.accountID == accountID, value.teamID == teamID else {
                throw TeamWorkspaceError.bindingMismatch
            }
            return value
        }
    }
    func save(_ progress: TeamAccountDeletionProgress) throws {
        try Self.validate(progress)
        try lock.withLock {
            let storageKey = key(progress.accountID, progress.teamID)
            if let data = defaults.data(forKey: storageKey) {
                let current = try JSONDecoder().decode(TeamAccountDeletionProgress.self, from: data)
                try Self.validate(current)
                guard current.accountID == progress.accountID,
                      current.teamID == progress.teamID,
                      current.operationID == progress.operationID,
                      !current.remoteAccepted || progress.remoteAccepted,
                      progress.completedSteps.starts(with: current.completedSteps) else {
                    throw TeamWorkspaceError.bindingMismatch
                }
            }
            defaults.set(try JSONEncoder().encode(progress), forKey: storageKey)
        }
    }
    func remove(_ progress: TeamAccountDeletionProgress) throws {
        try Self.validate(progress)
        try lock.withLock {
            let storageKey = key(progress.accountID, progress.teamID)
            guard let data = defaults.data(forKey: storageKey) else { return }
            let current = try JSONDecoder().decode(TeamAccountDeletionProgress.self, from: data)
            guard current == progress else { throw TeamWorkspaceError.bindingMismatch }
            defaults.removeObject(forKey: storageKey)
        }
    }
    private func key(_ accountID: String, _ teamID: String) -> String {
        let digest = SHA256.hash(data: Data((accountID + "\u{0}" + teamID).utf8))
        return "deletion." + digest.map { String(format: "%02x", $0) }.joined()
    }
    private static func validateIdentity(_ accountID: String, _ teamID: String) throws {
        guard TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(teamID) else {
            throw TeamWorkspaceError.invalidInput
        }
    }
    private static func validate(_ progress: TeamAccountDeletionProgress) throws {
        try validateIdentity(progress.accountID, progress.teamID)
        let all = TeamAccountDeletionCleanupStep.allCases
        guard TeamAuthWire.identifier(progress.operationID),
              progress.completedSteps.count <= all.count,
              Array(all.prefix(progress.completedSteps.count)) == progress.completedSteps,
              progress.remoteAccepted || progress.completedSteps.isEmpty else {
            throw TeamWorkspaceError.bindingMismatch
        }
    }
}

/// Every stage must be idempotent: a crash can occur after the secure deletion
/// commits but before its journal checkpoint. A production implementation must
/// delete the exact account/team material named by each step and treat absence
/// as success. No incomplete built-in implementation is provided.
protocol TeamAccountSecureCustodyDeleting: Sendable {
    func delete(step: TeamAccountDeletionCleanupStep,
                accountID: String, teamID: String) throws
}

/// Default-off account deletion. It never reports completion while any account-
/// bound team data, agreement key, signing identity, Terms record or session is
/// pending. The durable operation can resume after process termination.
actor TeamAccountDeletionCoordinator {
    static let confirmation = "DELETE"
    private let accountID: String
    private let teamID: String
    private let transport: any TeamAccountDeletionTransport
    private let progressStore: any TeamAccountDeletionProgressStoring
    private let cleanup: any TeamAccountSecureCustodyDeleting
    private let operationID: @Sendable () -> String
    private var working = false

    init(accountID: String, teamID: String,
         transport: any TeamAccountDeletionTransport,
         progressStore: any TeamAccountDeletionProgressStoring,
         cleanup: any TeamAccountSecureCustodyDeleting,
         operationID: @escaping @Sendable () -> String = { UUID().uuidString }) throws {
        guard TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(teamID) else {
            throw TeamWorkspaceError.invalidInput
        }
        self.accountID = accountID; self.teamID = teamID
        self.transport = transport; self.progressStore = progressStore
        self.cleanup = cleanup; self.operationID = operationID
    }
    func delete(confirmation: String) async throws {
        guard confirmation == Self.confirmation else { throw TeamWorkspaceError.invalidInput }
        try await run(createIfMissing: true)
    }
    func resumePending() async throws -> Bool {
        guard try progressStore.load(accountID: accountID, teamID: teamID) != nil else {
            return false
        }
        try await run(createIfMissing: false)
        return true
    }
    private func run(createIfMissing: Bool) async throws {
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        var progress: TeamAccountDeletionProgress
        if let current = try progressStore.load(accountID: accountID, teamID: teamID) {
            progress = current
        } else {
            guard createIfMissing else { return }
            let identifier = operationID()
            guard TeamAuthWire.identifier(identifier) else { throw TeamWorkspaceError.invalidInput }
            progress = .init(accountID: accountID, teamID: teamID,
                operationID: identifier, remoteAccepted: false, completedSteps: [])
            try progressStore.save(progress)
        }
        if !progress.remoteAccepted {
            // Any rejection or ambiguous failure leaves every local item intact
            // and preserves the same operation ID for an idempotent retry.
            try await transport.deleteAccount(accountID: accountID,
                                               operationID: progress.operationID)
            progress.remoteAccepted = true
            try progressStore.save(progress)
        }
        for step in TeamAccountDeletionCleanupStep.allCases
            .dropFirst(progress.completedSteps.count) {
            try cleanup.delete(step: step, accountID: accountID, teamID: teamID)
            progress.completedSteps.append(step)
            try progressStore.save(progress)
        }
        try progressStore.remove(progress)
    }
}

/// One provider-neutral sign-in seam. Apple and Google use the same challenge,
/// server exchange, session reservation and exact-generation custody path.
/// Scope, transport and native identity adapters are supplied by the host.
struct TeamWorkspaceAccountComposition: Sendable {
    let sessions: TeamAccountSessionStore
    let transport: any TeamAccountSigningIn

    func signIn(provider: TeamNativeSignInProvider,
                scope: TeamAccountSessionScope,
                identity: any TeamNativeIdentityAuthorizing,
                clock: @escaping @Sendable () -> TeamSignInMoment = { .current() })
        -> TeamAccountSignInCoordinator {
        TeamAccountSignInCoordinator(provider: provider, scope: scope,
            store: sessions, identity: identity, transport: transport, clock: clock)
    }
}

/// Normal app composition is disabled. A future release host must deliberately
/// inject every approved server/custody dependency; this type stores no origin,
/// credential or fallback endpoint of its own.
enum TeamWorkspaceRuntimeConfiguration: Sendable {
    case disabled
    case injected(TeamWorkspaceAccountComposition)

    static let productionDefault: Self = .disabled
    var isEnabled: Bool {
        if case .injected = self { return true }
        return false
    }
}

/// Approved production implementations conform once they can satisfy every
/// frozen workspace operation. There is intentionally no default HTTP conformer:
/// moderation and deletion routes remain unfrozen and cannot be guessed here.
protocol TeamWorkspaceRemoteTransport: TeamWorkspaceAudienceProviding,
    TeamWorkspaceSubmissionTransport, TeamWorkspaceInboxTransport,
    TeamSafetyTransport, TeamAccountDeletionTransport {}

/// Adds exact-generation session checks around every injected remote operation.
/// Access credentials remain volatile inside `TeamAccountAccessTicket` and are
/// never copied into workspace models, URLs, defaults, logs or SQLite stores.
actor TeamWorkspaceSessionBoundRemote: TeamWorkspaceRemoteTransport {
    private let ticket: TeamAccountAccessTicket
    private let sessions: TeamAccountSessionStore
    private let remote: any TeamWorkspaceRemoteTransport
    private let clock: @Sendable () -> Int64

    init(ticket: TeamAccountAccessTicket, sessions: TeamAccountSessionStore,
         remote: any TeamWorkspaceRemoteTransport,
         clock: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) throws {
        try sessions.requireCurrentAccess(ticket, now: clock())
        self.ticket = ticket; self.sessions = sessions
        self.remote = remote; self.clock = clock
    }

    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience {
        try check(); let value = try await remote.audience(teamID: teamID, enrollmentID: enrollmentID)
        try check(); return value
    }
    func reserve(_ plan: TeamWorkspaceSendPlan) async throws -> TeamDeliverySubmissionReservation {
        try check(); let value = try await remote.reserve(plan)
        try check(); return value
    }
    func status(deliveryID: String, jweSHA256: String) async throws -> TeamDeliverySubmissionStatus {
        try check(); let value = try await remote.status(deliveryID: deliveryID, jweSHA256: jweSHA256)
        try check(); return value
    }
    func pending(after: TeamDeliveryListCursor?, limit: Int) async throws -> TeamPendingDeliveryPage {
        try check(); let value = try await remote.pending(after: after, limit: limit)
        try check(); return value
    }
    func fetch(_ pending: TeamPendingDelivery) async throws -> TeamWorkspaceFetchedDelivery {
        try check(); let value = try await remote.fetch(pending)
        try check(); return value
    }
    func acknowledge(_ receipt: PendingTeamReceipt) async throws -> TeamWorkspaceACKReply {
        try check(); let value = try await remote.acknowledge(receipt)
        try check(); return value
    }
    func execute(accountID: String, teamID: String, action: TeamSafetyAction) async throws {
        guard accountID == ticket.accountID else { throw TeamWorkspaceError.bindingMismatch }
        try check(); try await remote.execute(accountID: accountID, teamID: teamID, action: action)
        try check()
    }
    func deleteAccount(accountID: String, operationID: String) async throws {
        guard accountID == ticket.accountID else { throw TeamWorkspaceError.bindingMismatch }
        guard TeamAuthWire.identifier(operationID) else { throw TeamWorkspaceError.invalidInput }
        try check()
        try await remote.deleteAccount(accountID: accountID, operationID: operationID)
        // A successful remote deletion may invalidate the session immediately,
        // so no post-dispatch session assertion is valid for this one operation.
    }

    private func check() throws {
        try Task.checkCancellation()
        let now = clock()
        _ = try ticket.usableToken(now: now)
        try sessions.requireCurrentAccess(ticket, now: now)
        try Task.checkCancellation()
    }
}

/// Constructs user-triggered workspace coordinators only from an exact live
/// account generation and fully injected stores/custody/transports. Merely
/// creating this value performs no provider or server operation.
struct TeamWorkspaceConnectedComposition: Sendable {
    let accountID: String
    let teamID: String
    let enrollmentID: String
    let session: TeamAccountSessionSnapshot
    let sessions: TeamAccountSessionStore
    let terms: any TeamTermsStoring
    let outbox: TeamOutgoingStore
    let inbox: TeamInboxStore
    let agreement: TeamAgreementKeyCustody
    let remote: TeamWorkspaceSessionBoundRemote
    let deletionProgress: any TeamAccountDeletionProgressStoring
    let accountCleanup: any TeamAccountSecureCustodyDeleting

    init(session: TeamAccountSessionSnapshot, sessions: TeamAccountSessionStore,
         teamID: String, enrollmentID: String,
         terms: any TeamTermsStoring, outbox: TeamOutgoingStore,
         inbox: TeamInboxStore, agreement: TeamAgreementKeyCustody,
         deletionProgress: any TeamAccountDeletionProgressStoring,
         accountCleanup: any TeamAccountSecureCustodyDeleting,
         remote: any TeamWorkspaceRemoteTransport,
         clock: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) throws {
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        guard TeamAuthWire.identifier(teamID), TeamAuthWire.identifier(enrollmentID),
              outbox.sender.userId == session.accountID,
              outbox.teamId == teamID, outbox.sender.enrollmentId == enrollmentID,
              inbox.target.userId == session.accountID,
              inbox.teamId == teamID, inbox.target.enrollmentId == enrollmentID else {
            throw TeamWorkspaceError.bindingMismatch
        }
        self.accountID = session.accountID; self.teamID = teamID
        self.enrollmentID = enrollmentID; self.session = session
        self.sessions = sessions; self.terms = terms
        self.outbox = outbox; self.inbox = inbox; self.agreement = agreement
        self.deletionProgress = deletionProgress; self.accountCleanup = accountCleanup
        self.remote = try TeamWorkspaceSessionBoundRemote(ticket: ticket,
            sessions: sessions, remote: remote, clock: clock)
    }

    func sender() throws -> TeamManualNoteSendCoordinator {
        try TeamManualNoteSendCoordinator(accountID: accountID, teamID: teamID,
            enrollmentID: enrollmentID, outbox: outbox, terms: .init(store: terms),
            audience: remote, transport: remote)
    }
    func receiver() throws -> TeamForegroundInboxCoordinator {
        try TeamForegroundInboxCoordinator(teamID: teamID, enrollmentID: enrollmentID,
            inbox: inbox, custody: agreement, transport: remote)
    }
    func safety() throws -> TeamSafetyCoordinator {
        try TeamSafetyCoordinator(accountID: accountID, teamID: teamID, transport: remote)
    }
    func deletion() throws -> TeamAccountDeletionCoordinator {
        try TeamAccountDeletionCoordinator(accountID: accountID, teamID: teamID,
            transport: remote, progressStore: deletionProgress,
            cleanup: accountCleanup)
    }
}
