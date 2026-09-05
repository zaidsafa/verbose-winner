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
    func deleteAccount(accountID: String) async throws
}

/// Default-off account-deletion seam for a future authenticated server route.
/// The UI must require the exact visible confirmation phrase before calling it.
struct TeamAccountDeletionCoordinator: Sendable {
    static let confirmation = "DELETE"
    let accountID: String
    let transport: any TeamAccountDeletionTransport
    init(accountID: String, transport: any TeamAccountDeletionTransport) throws {
        guard TeamAuthWire.identifier(accountID) else { throw TeamWorkspaceError.invalidInput }
        self.accountID = accountID; self.transport = transport
    }
    func delete(confirmation: String) async throws {
        guard confirmation == Self.confirmation else { throw TeamWorkspaceError.invalidInput }
        try await transport.deleteAccount(accountID: accountID)
    }
}
