import Darwin
import CryptoKit
import Foundation
import Security
import SQLite3

enum TeamWorkspaceError: Error, Equatable {
    case invalidInput
    case termsRequired
    case busy
    case unavailable
    case bindingMismatch
    case deletionPending
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

protocol TeamAccountTermsDeleting: Sendable {
    func removeAll(accountID: String) throws
}

/// Device-local, non-synchronizing consent record. It contains no invitation,
/// session, note or provider credential.
final class UserDefaultsTeamTermsStore: TeamTermsStoring, TeamAccountTermsDeleting,
    @unchecked Sendable {
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
    func removeAll(accountID: String) throws {
        guard TeamAuthWire.identifier(accountID) else { throw TeamWorkspaceError.invalidInput }
        lock.withLock {
            for (key, value) in defaults.dictionaryRepresentation()
                where key.hasPrefix("terms.") {
                guard let data = value as? Data,
                      let acceptance = try? JSONDecoder().decode(
                        TeamTermsAcceptance.self, from: data),
                      acceptance.accountID == accountID else { continue }
                defaults.removeObject(forKey: key)
            }
        }
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
    case unblockUser(userID: String)
}

enum TeamReportReason: String, CaseIterable, Codable, Sendable {
    case spam = "SPAM"
    case harassment = "HARASSMENT"
    case scam = "SCAM"
    case illegal = "ILLEGAL"
    case other = "OTHER"
}

enum TeamStoreComplianceRoute: String, Sendable {
    case acceptTerms = "store/terms/accept"
    case reportNote = "store/reports/note"
    case reportUser = "store/reports/user"
    case blockUser = "store/blocks/block"
    case unblockUser = "store/blocks/unblock"
    case requestDeletion = "account/deletion/request"
    case deletionStatus = "account/deletion/status"

    var requiresSession: Bool { self != .deletionStatus }
}

struct TeamStoreTermsReceipt: Equatable, Sendable {
    let acceptanceID: String
    let accountID: String
    let acceptedAt: Int64
}

protocol TeamStoreTermsTransport: Sendable {
    func acceptTerms(requestID: String) async throws -> TeamStoreTermsReceipt
}

/// Exact migration-027 store-compliance wire adapter. Construction is inert;
/// requests occur only from an explicit user action and only when a live ticket
/// was deliberately injected. Deletion status is the sole unauthenticated route.
struct TeamStoreComplianceHTTPTransport: TeamStoreTermsTransport,
    TeamSafetyTransport, TeamAccountDeletionDispatchTransport,
    TeamAccountDeletionStatusTransport, Sendable {
    static let termsVersion = "pinbook-terms-2026-09-05-v1"
    static let privacyVersion = "pinbook-privacy-2026-09-05-v1"
    private let http: TeamAuthHTTPClient
    private let ticket: TeamAccountAccessTicket?
    private let requestID: @Sendable () -> String

    init(http: TeamAuthHTTPClient, ticket: TeamAccountAccessTicket? = nil,
         requestID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.http = http
        self.ticket = ticket
        self.requestID = requestID
    }

    func acceptTerms(requestID: String) async throws -> TeamStoreTermsReceipt {
        let ticket = try protectedTicket()
        guard TeamAuthWire.identifier(requestID) else { throw TeamWorkspaceError.invalidInput }
        let response = try await http.storeCompliance(.acceptTerms, fields: [
            "type": "pinbook-terms-accept-v1", "requestId": requestID,
            "termsVersion": Self.termsVersion, "privacyVersion": Self.privacyVersion
        ], ticket: ticket)
        let value = try TeamAuthWire.object(response.data, keys: ["type", "acceptanceId",
            "accountId", "termsVersion", "privacyVersion", "acceptedAt", "retentionRule"])
        guard value["type"] as? String == "pinbook-terms-acceptance-v1",
              try TeamAuthWire.string(value, "acceptanceId") == requestID,
              try TeamAuthWire.string(value, "accountId") == ticket.accountID,
              value["termsVersion"] as? String == Self.termsVersion,
              value["privacyVersion"] as? String == Self.privacyVersion,
              value["retentionRule"] as? String == "ACCOUNT_LIFETIME_PLUS_37_DAYS" else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return .init(acceptanceID: requestID, accountID: ticket.accountID,
                     acceptedAt: try TeamAuthWire.time(value, "acceptedAt"))
    }

    func execute(accountID: String, teamID: String,
                 action: TeamSafetyAction) async throws {
        let ticket = try protectedTicket()
        guard accountID == ticket.accountID, TeamAuthWire.identifier(teamID) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        let requestID = requestID()
        guard TeamAuthWire.identifier(requestID) else { throw TeamWorkspaceError.invalidInput }
        let route: TeamStoreComplianceRoute
        let fields: [String: Any]
        switch action {
        case .reportNote(let noteID, let authorID, let reason):
            guard TeamAuthWire.identifier(noteID), TeamAuthWire.identifier(authorID),
                  let reason = TeamReportReason(rawValue: reason) else {
                throw TeamWorkspaceError.invalidInput
            }
            route = .reportNote
            fields = ["type": "pinbook-report-note-v1", "requestId": requestID,
                      "teamId": teamID, "noteId": noteID, "reasonCode": reason.rawValue]
        case .reportUser(let userID, let reason):
            guard TeamAuthWire.identifier(userID), userID != accountID,
                  let reason = TeamReportReason(rawValue: reason) else {
                throw TeamWorkspaceError.invalidInput
            }
            route = .reportUser
            fields = ["type": "pinbook-report-user-v1", "requestId": requestID,
                      "teamId": teamID, "reportedAccountId": userID,
                      "reasonCode": reason.rawValue]
        case .blockUser(let userID), .unblockUser(let userID):
            guard TeamAuthWire.identifier(userID), userID != accountID else {
                throw TeamWorkspaceError.invalidInput
            }
            let blocked: Bool
            if case .blockUser = action { blocked = true } else { blocked = false }
            route = blocked ? .blockUser : .unblockUser
            fields = ["type": blocked ? "pinbook-block-user-v1" : "pinbook-unblock-user-v1",
                      "requestId": requestID, "blockedAccountId": userID]
        }
        let response = try await http.storeCompliance(route, fields: fields, ticket: ticket)
        if route == .reportNote || route == .reportUser {
            try validateReport(response.data, requestID: requestID, teamID: teamID,
                               action: action, accountID: accountID)
        } else {
            try validateBlock(response.data, requestID: requestID,
                              action: action, accountID: accountID)
        }
    }

    func requestDeletion(binding: TeamAccountDeletionBinding,
                         request: TeamAccountDeletionRequest) async throws
        -> TeamAccountDeletionStatus {
        let ticket = try protectedTicket()
        guard binding.accountID == ticket.accountID,
              binding.providerID == ticket.scope.providerID,
              binding.origin + "/" == ticket.scope.origin.absoluteString else {
            throw TeamWorkspaceError.bindingMismatch
        }
        let response = try await http.storeCompliance(.requestDeletion, fields: [
            "type": request.type, "requestId": request.requestID,
            "confirmation": request.confirmation, "statusToken": request.statusToken
        ], ticket: ticket)
        return try deletion(response.data, binding: binding,
                            deletionID: request.requestID)
    }

    func deletionStatus(binding: TeamAccountDeletionBinding,
                        request: TeamAccountDeletionStatusRequest) async throws
        -> TeamAccountDeletionStatus {
        guard ticket == nil, TeamAuthWire.identifier(binding.accountID),
              TeamAuthWire.identifier(request.deletionID),
              TeamDeviceEnrollmentWire.canonicalAudience(binding.origin) else {
            throw TeamWorkspaceError.invalidInput
        }
        let response = try await http.storeCompliance(.deletionStatus, fields: [
            "type": request.type, "deletionId": request.deletionID,
            "statusToken": request.statusToken
        ], ticket: nil)
        return try deletion(response.data, binding: binding,
                            deletionID: request.deletionID)
    }

    private func protectedTicket() throws -> TeamAccountAccessTicket {
        guard let ticket else { throw TeamWorkspaceError.unavailable }
        return ticket
    }

    private func validateReport(_ data: Data, requestID: String, teamID: String,
                                action: TeamSafetyAction, accountID: String) throws {
        let value = try TeamAuthWire.object(data, keys: ["type", "reportId", "reportKind",
            "reporterAccountId", "teamId", "targetId", "reasonCode", "state",
            "receivedAt", "metadataExpiresAt"])
        let kind: String, target: String, reason: String
        switch action {
        case .reportNote(let noteID, _, let code): kind = "NOTE"; target = noteID; reason = code
        case .reportUser(let userID, let code): kind = "USER"; target = userID; reason = code
        default: throw TeamWorkspaceError.bindingMismatch
        }
        let received = try TeamAuthWire.time(value, "receivedAt")
        let expires = try TeamAuthWire.time(value, "metadataExpiresAt")
        let expected = received.addingReportingOverflow(7_776_000_000)
        guard value["type"] as? String == "pinbook-report-receipt-v1",
              try TeamAuthWire.string(value, "reportId") == requestID,
              value["reportKind"] as? String == kind,
              try TeamAuthWire.string(value, "reporterAccountId") == accountID,
              try TeamAuthWire.string(value, "teamId") == teamID,
              try TeamAuthWire.string(value, "targetId") == target,
              value["reasonCode"] as? String == reason,
              value["state"] as? String == "RECEIVED", !expected.overflow,
              expires == expected.partialValue else { throw TeamAuthHTTPError.invalidResponse }
    }

    private func validateBlock(_ data: Data, requestID: String,
                               action: TeamSafetyAction, accountID: String) throws {
        let value = try TeamAuthWire.object(data, keys: ["type", "requestId", "accountId",
            "blockedAccountId", "state", "changedAt", "retentionRule"])
        let blocked: Bool, target: String
        switch action {
        case .blockUser(let userID): blocked = true; target = userID
        case .unblockUser(let userID): blocked = false; target = userID
        default: throw TeamWorkspaceError.bindingMismatch
        }
        _ = try TeamAuthWire.time(value, "changedAt")
        guard value["type"] as? String == "pinbook-user-block-status-v1",
              try TeamAuthWire.string(value, "requestId") == requestID,
              try TeamAuthWire.string(value, "accountId") == accountID,
              try TeamAuthWire.string(value, "blockedAccountId") == target,
              value["state"] as? String == (blocked ? "BLOCKED" : "UNBLOCKED"),
              value["retentionRule"] as? String
                == (blocked ? "UNTIL_UNBLOCK_OR_ACCOUNT_DELETION" : "37_DAYS") else {
            throw TeamAuthHTTPError.invalidResponse
        }
    }

    private func deletion(_ data: Data, binding: TeamAccountDeletionBinding,
                          deletionID: String) throws -> TeamAccountDeletionStatus {
        _ = try TeamAuthWire.object(data, keys: ["type", "deletionId", "accountId", "state",
            "requestedAt", "authorityRevokedAt", "cleanupScheduledAt", "completedAt",
            "statusExpiresAt"])
        let result: TeamAccountDeletionStatus
        do { result = try JSONDecoder().decode(TeamAccountDeletionStatus.self, from: data) }
        catch { throw TeamAuthHTTPError.invalidResponse }
        guard result.deletionID == deletionID,
              result.accountID == binding.accountID else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return result
    }
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
        case .blockUser(let value), .unblockUser(let value): userID = value; reason = nil
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

/// Immutable account-level recovery scope. Team IDs are deliberately absent:
/// migration 027 permits only one deletion row per account.
struct TeamAccountDeletionBinding: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    static let currentVersion = 2
    let version: Int
    let origin: String
    let providerID: String
    let authorityEpoch: String
    let accountID: String
    let custodyID: String

    init(origin: String, providerID: String, authorityEpoch: String,
         accountID: String, custodyID: String) throws {
        guard TeamDeviceEnrollmentWire.canonicalAudience(origin),
              TeamAuthWire.identifier(providerID),
              TeamAuthWire.identifier(authorityEpoch),
              TeamAuthWire.identifier(accountID),
              TeamAuthWire.identifier(custodyID) else {
            throw TeamWorkspaceError.invalidInput
        }
        version = Self.currentVersion
        self.origin = origin; self.providerID = providerID
        self.authorityEpoch = authorityEpoch; self.accountID = accountID
        self.custodyID = custodyID
    }

    var digest: String {
        let fields = [String(version), origin, providerID, authorityEpoch,
                      accountID, custodyID].joined(separator: "\n")
        return SHA256.hash(data: Data(fields.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    var description: String { "TeamAccountDeletionBinding(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamAccountDeletionStatusCredential: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let bytes: Data
    init(bytes: Data) throws {
        guard bytes.count == 32 else { throw TeamWorkspaceError.invalidInput }
        self.bytes = bytes
    }
    var canonicalValue: String {
        TeamDeviceEnrollmentWire.encode(bytes)
    }
    var description: String { "TeamAccountDeletionStatusCredential(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamAccountDeletionCredentialReference: Codable, Equatable, Sendable {
    let credentialID: String
    let bindingDigest: String
}

enum TeamAccountDeletionServerState: String, Codable, Equatable, Sendable {
    case revocationRequired = "REVOCATION_REQUIRED"
    case cleanupSchedulingRequired = "CLEANUP_SCHEDULING_REQUIRED"
    case pendingErasure = "PENDING_ERASURE"
    case completed = "COMPLETED"
}

struct TeamAccountDeletionStatus: Codable, Equatable, Sendable {
    static let type = "pinbook-account-deletion-status-v1"
    let type: String
    let deletionID: String
    let accountID: String
    let state: TeamAccountDeletionServerState
    let requestedAt: Int64
    let authorityRevokedAt: Int64?
    let cleanupScheduledAt: Int64?
    let completedAt: Int64?
    let statusExpiresAt: Int64?

    enum CodingKeys: String, CodingKey {
        case type, state, requestedAt, authorityRevokedAt, cleanupScheduledAt,
             completedAt, statusExpiresAt
        case deletionID = "deletionId"
        case accountID = "accountId"
    }

    init(deletionID: String, accountID: String, state: TeamAccountDeletionServerState,
         requestedAt: Int64, authorityRevokedAt: Int64? = nil,
         cleanupScheduledAt: Int64? = nil, completedAt: Int64? = nil,
         statusExpiresAt: Int64? = nil) throws {
        type = Self.type; self.deletionID = deletionID; self.accountID = accountID
        self.state = state; self.requestedAt = requestedAt
        self.authorityRevokedAt = authorityRevokedAt
        self.cleanupScheduledAt = cleanupScheduledAt
        self.completedAt = completedAt; self.statusExpiresAt = statusExpiresAt
        try validate()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        deletionID = try values.decode(String.self, forKey: .deletionID)
        accountID = try values.decode(String.self, forKey: .accountID)
        state = try values.decode(TeamAccountDeletionServerState.self, forKey: .state)
        requestedAt = try values.decode(Int64.self, forKey: .requestedAt)
        authorityRevokedAt = try values.decodeIfPresent(Int64.self, forKey: .authorityRevokedAt)
        cleanupScheduledAt = try values.decodeIfPresent(Int64.self, forKey: .cleanupScheduledAt)
        completedAt = try values.decodeIfPresent(Int64.self, forKey: .completedAt)
        statusExpiresAt = try values.decodeIfPresent(Int64.self, forKey: .statusExpiresAt)
        try validate()
    }

    private func validate() throws {
        guard type == Self.type, TeamAuthWire.identifier(deletionID),
              TeamAuthWire.identifier(accountID), requestedAt >= 0 else {
            throw TeamWorkspaceError.invalidInput
        }
        switch state {
        case .revocationRequired:
            guard authorityRevokedAt == nil, cleanupScheduledAt == nil,
                  completedAt == nil, statusExpiresAt == nil else {
                throw TeamWorkspaceError.invalidInput
            }
        case .cleanupSchedulingRequired:
            guard let authorityRevokedAt, authorityRevokedAt >= requestedAt,
                  cleanupScheduledAt == nil, completedAt == nil,
                  statusExpiresAt == nil else { throw TeamWorkspaceError.invalidInput }
        case .pendingErasure:
            guard let authorityRevokedAt, let cleanupScheduledAt,
                  authorityRevokedAt >= requestedAt,
                  cleanupScheduledAt >= authorityRevokedAt,
                  completedAt == nil, statusExpiresAt == nil else {
                throw TeamWorkspaceError.invalidInput
            }
        case .completed:
            guard let authorityRevokedAt, let cleanupScheduledAt, let completedAt,
                  let statusExpiresAt, authorityRevokedAt >= requestedAt,
                  cleanupScheduledAt >= authorityRevokedAt,
                  completedAt >= cleanupScheduledAt else {
                throw TeamWorkspaceError.invalidInput
            }
            let expected = completedAt.addingReportingOverflow(3_196_800_000)
            guard !expected.overflow, statusExpiresAt == expected.partialValue else {
                throw TeamWorkspaceError.invalidInput
            }
        }
    }
}

struct TeamAccountDeletionRequest: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    static let type = "pinbook-account-deletion-request-v1"
    static let confirmation = "DELETE_ACCOUNT"
    let type: String
    let requestID: String
    let confirmation: String
    let statusToken: String
    enum CodingKeys: String, CodingKey {
        case type, confirmation, statusToken
        case requestID = "requestId"
    }
    init(requestID: String, credential: TeamAccountDeletionStatusCredential) throws {
        guard TeamAuthWire.identifier(requestID), credential.canonicalValue.utf8.count == 43,
              TeamDeviceEnrollmentWire.decode(credential.canonicalValue) == credential.bytes else {
            throw TeamWorkspaceError.invalidInput
        }
        type = Self.type; self.requestID = requestID
        confirmation = Self.confirmation; statusToken = credential.canonicalValue
    }
    var description: String { "TeamAccountDeletionRequest(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamAccountDeletionStatusRequest: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    static let type = "pinbook-account-deletion-status-request-v1"
    let type: String
    let deletionID: String
    let statusToken: String
    enum CodingKeys: String, CodingKey {
        case type, statusToken
        case deletionID = "deletionId"
    }
    init(deletionID: String, credential: TeamAccountDeletionStatusCredential) throws {
        guard TeamAuthWire.identifier(deletionID), credential.canonicalValue.utf8.count == 43,
              TeamDeviceEnrollmentWire.decode(credential.canonicalValue) == credential.bytes else {
            throw TeamWorkspaceError.invalidInput
        }
        type = Self.type; self.deletionID = deletionID
        statusToken = credential.canonicalValue
    }
    var description: String { "TeamAccountDeletionStatusRequest(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Uses the ordinary authenticated account session for an exact idempotent request.
protocol TeamAccountDeletionDispatchTransport: Sendable {
    func requestDeletion(binding: TeamAccountDeletionBinding,
                         request: TeamAccountDeletionRequest) async throws
        -> TeamAccountDeletionStatus
}

/// Unauthenticated status-only recovery. Invalid credentials and transport errors
/// remain ambiguous and must never be translated into a fabricated rejection.
protocol TeamAccountDeletionStatusTransport: Sendable {
    func deletionStatus(binding: TeamAccountDeletionBinding,
                        request: TeamAccountDeletionStatusRequest) async throws
        -> TeamAccountDeletionStatus
}

enum TeamAccountDeletionCleanupStep: String, Codable, CaseIterable, Sendable {
    case teamCacheAndArchive
    case agreementIdentity
    case deviceSigningIdentity
    case termsAcceptance
    case accountSession
}

enum TeamAccountDeletionPhase: String, Codable, Equatable, Sendable {
    case prepared = "PREPARED"
    case dispatched = "DISPATCHED"
    case uncertain = "UNCERTAIN"
    case authorityRevoked = "AUTHORITY_REVOKED"
    case serverCompleted = "SERVER_COMPLETED"

    var blocksTeamActions: Bool {
        true
    }
}

struct TeamAccountDeletionProgress: Codable, Equatable, Sendable {
    static let currentVersion = 3
    let version: Int
    let binding: TeamAccountDeletionBinding
    let operationID: String
    let credentialReference: TeamAccountDeletionCredentialReference
    var phase: TeamAccountDeletionPhase
    var completedSteps: [TeamAccountDeletionCleanupStep]
}

protocol TeamAccountDeletionProgressStoring: Sendable {
    func load(accountID: String) throws -> TeamAccountDeletionProgress?
    func loadAll() throws -> [TeamAccountDeletionProgress]
    func save(_ progress: TeamAccountDeletionProgress) throws
    func remove(_ progress: TeamAccountDeletionProgress) throws
}

/// Device-local account-global restart journal. SQLite EXTRA synchronization means
/// save returns only after the checkpoint commits. The dedicated protected
/// directory and database are excluded from backup; status tokens remain in Keychain.
final class SQLiteTeamAccountDeletionProgressStore:
    TeamAccountDeletionProgressStoring, @unchecked Sendable {
    private let lock = NSLock()
    let directoryURL: URL
    let databaseURL: URL
    private var database: OpaquePointer?

    convenience init() throws {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            throw TeamWorkspaceError.unavailable
        }
        try self.init(applicationSupportDirectory: root)
    }

    init(applicationSupportDirectory: URL) throws {
        guard applicationSupportDirectory.isFileURL else { throw TeamWorkspaceError.invalidInput }
        directoryURL = applicationSupportDirectory
            .appendingPathComponent("PinbookTeamAccountDeletion", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("account-deletion-v3.sqlite")
        let fm = FileManager.default
        var directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        var fileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        directoryAttributes[.protectionKey] = FileProtectionType.complete
        fileAttributes[.protectionKey] = FileProtectionType.complete
        #endif
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                               attributes: directoryAttributes)
        guard try directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamWorkspaceError.invalidInput
        }
        try fm.setAttributes(directoryAttributes, ofItemAtPath: directoryURL.path)
        try Self.excludeFromBackup(directoryURL)
        let descriptor = Darwin.open(databaseURL.path,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        if descriptor >= 0 { Darwin.close(descriptor) }
        else if errno != EEXIST { throw TeamWorkspaceError.unavailable }
        guard try databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw TeamWorkspaceError.invalidInput
        }
        try fm.setAttributes(fileAttributes, ofItemAtPath: databaseURL.path)
        try Self.excludeFromBackup(databaseURL)
        #if os(iOS) && !targetEnvironment(simulator)
        for url in [directoryURL, databaseURL] {
            guard try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? String
                    == FileProtectionType.complete.rawValue else {
                throw TeamWorkspaceError.unavailable
            }
        }
        #endif
        var handle: OpaquePointer?
        var flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        #if os(iOS)
        flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETE
        #endif
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw TeamWorkspaceError.unavailable
        }
        database = handle
        do {
            sqlite3_busy_timeout(database, 2_000)
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=EXTRA")
            try execute("PRAGMA fullfsync=ON")
            try execute("PRAGMA temp_store=MEMORY")
            try transaction {
                let version = try scalar("PRAGMA user_version")
                guard version == 0 || version == 3 else {
                    throw TeamWorkspaceError.bindingMismatch
                }
                if version == 0 {
                    try execute("CREATE TABLE deletion_progress (account_id TEXT PRIMARY KEY, payload BLOB NOT NULL) WITHOUT ROWID")
                    try execute("PRAGMA user_version=3")
                } else {
                    _ = try scalar("SELECT count(*) FROM deletion_progress")
                }
            }
        } catch {
            sqlite3_close(database); database = nil; throw error
        }
    }

    deinit { sqlite3_close(database) }

    func load(accountID: String) throws -> TeamAccountDeletionProgress? {
        try Self.validateIdentity(accountID)
        return try lock.withLock { try loadUnlocked(accountID: accountID) }
    }

    func loadAll() throws -> [TeamAccountDeletionProgress] {
        try lock.withLock {
            let statement = try prepare("SELECT account_id,payload FROM deletion_progress ORDER BY account_id")
            defer { sqlite3_finalize(statement) }
            var values = [TeamAccountDeletionProgress]()
            while try step(statement) == SQLITE_ROW {
                guard let rawAccount = sqlite3_column_text(statement, 0) else {
                    throw TeamWorkspaceError.bindingMismatch
                }
                let accountID = String(cString: rawAccount)
                let value = try decode(statement, column: 1)
                guard value.binding.accountID == accountID else {
                    throw TeamWorkspaceError.bindingMismatch
                }
                values.append(value)
            }
            return values
        }
    }

    func save(_ progress: TeamAccountDeletionProgress) throws {
        try Self.validate(progress)
        let payload = try JSONEncoder().encode(progress)
        try lock.withLock {
            try transaction {
                if let current = try loadUnlocked(accountID: progress.binding.accountID),
                   !Self.validTransition(from: current, to: progress) {
                    throw TeamWorkspaceError.bindingMismatch
                }
                try execute("INSERT INTO deletion_progress(account_id,payload) VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload",
                    [.text(progress.binding.accountID), .blob(payload)])
            }
        }
    }

    func remove(_ progress: TeamAccountDeletionProgress) throws {
        try Self.validate(progress)
        try lock.withLock {
            try transaction {
                guard let current = try loadUnlocked(accountID: progress.binding.accountID) else {
                    return
                }
                guard current == progress else { throw TeamWorkspaceError.bindingMismatch }
                try execute("DELETE FROM deletion_progress WHERE account_id=?",
                            [.text(progress.binding.accountID)])
            }
        }
    }

    private static func validateIdentity(_ accountID: String) throws {
        guard TeamAuthWire.identifier(accountID) else { throw TeamWorkspaceError.invalidInput }
    }
    private static func validate(_ progress: TeamAccountDeletionProgress) throws {
        try validateIdentity(progress.binding.accountID)
        let all = TeamAccountDeletionCleanupStep.allCases
        guard progress.version == TeamAccountDeletionProgress.currentVersion,
              progress.binding.version == TeamAccountDeletionBinding.currentVersion,
              TeamDeviceEnrollmentWire.canonicalAudience(progress.binding.origin),
              TeamAuthWire.identifier(progress.binding.providerID),
              TeamAuthWire.identifier(progress.binding.authorityEpoch),
              TeamAuthWire.identifier(progress.binding.custodyID),
              TeamAuthWire.identifier(progress.operationID),
              TeamAuthWire.identifier(progress.credentialReference.credentialID),
              progress.credentialReference.bindingDigest == progress.binding.digest,
              progress.completedSteps.count <= all.count,
              Array(all.prefix(progress.completedSteps.count)) == progress.completedSteps,
              [.authorityRevoked, .serverCompleted].contains(progress.phase)
                || progress.completedSteps.isEmpty else {
            throw TeamWorkspaceError.bindingMismatch
        }
    }
    private static func validTransition(from current: TeamAccountDeletionProgress,
                                        to next: TeamAccountDeletionProgress) -> Bool {
        guard current.version == next.version, current.binding == next.binding,
              current.operationID == next.operationID,
              current.credentialReference == next.credentialReference,
              next.completedSteps.starts(with: current.completedSteps) else { return false }
        if current.phase == next.phase {
            return [.authorityRevoked, .serverCompleted].contains(current.phase)
                || current.completedSteps == next.completedSteps
        }
        switch (current.phase, next.phase) {
        case (.prepared, .dispatched),
             (.dispatched, .uncertain),
             (.uncertain, .dispatched),
             (.dispatched, .authorityRevoked),
             (.dispatched, .serverCompleted),
             (.uncertain, .authorityRevoked),
             (.uncertain, .serverCompleted):
            return current.completedSteps.isEmpty && next.completedSteps.isEmpty
        case (.authorityRevoked, .serverCompleted):
            return current.completedSteps == next.completedSteps
        default:
            return false
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true else { throw TeamWorkspaceError.unavailable }
    }

    private enum Value { case text(String), blob(Data) }
    private func prepare(_ sql: String, _ values: [Value] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw TeamWorkspaceError.unavailable }
        do {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1), result: Int32
                switch value {
                case .text(let text):
                    result = sqlite3_bind_text(statement, index, text, -1, transient)
                case .blob(let data):
                    result = data.withUnsafeBytes {
                        sqlite3_bind_blob(statement, index, $0.baseAddress,
                                          Int32($0.count), transient)
                    }
                }
                guard result == SQLITE_OK else { throw TeamWorkspaceError.unavailable }
            }
        } catch { sqlite3_finalize(statement); throw error }
        return statement
    }
    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw TeamWorkspaceError.unavailable
        }
        return result
    }
    private func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        _ = try step(statement)
    }
    private func scalar(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { throw TeamWorkspaceError.unavailable }
        return sqlite3_column_int64(statement, 0)
    }
    private func decode(_ statement: OpaquePointer, column: Int32) throws
        -> TeamAccountDeletionProgress {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 64 * 1024,
              let bytes = sqlite3_column_blob(statement, column) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        do {
            let value = try JSONDecoder().decode(TeamAccountDeletionProgress.self,
                from: Data(bytes: bytes, count: count))
            try Self.validate(value)
            return value
        } catch {
            throw TeamWorkspaceError.bindingMismatch
        }
    }
    private func loadUnlocked(accountID: String) throws -> TeamAccountDeletionProgress? {
        let statement = try prepare("SELECT payload FROM deletion_progress WHERE account_id=?",
                                    [.text(accountID)])
        defer { sqlite3_finalize(statement) }
        guard try step(statement) == SQLITE_ROW else { return nil }
        let value = try decode(statement, column: 0)
        guard value.binding.accountID == accountID else {
            throw TeamWorkspaceError.bindingMismatch
        }
        return value
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
}

protocol TeamAccountDeletionCredentialStoring: Sendable {
    func load(_ reference: TeamAccountDeletionCredentialReference) throws
        -> TeamAccountDeletionStatusCredential?
    func insert(_ credential: TeamAccountDeletionStatusCredential,
                reference: TeamAccountDeletionCredentialReference) throws -> Bool
    func remove(_ reference: TeamAccountDeletionCredentialReference) throws
}

/// Device-only, non-synchronizing Keychain custody. This status credential cannot
/// enter iCloud Keychain, an app backup, the deletion journal or a portable backup.
struct KeychainTeamAccountDeletionCredentialStore:
    TeamAccountDeletionCredentialStoring, Sendable {
    private let service = "com.zaidsafa.pinbook.ios.team-account-deletion-status.v1"
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private func validate(_ reference: TeamAccountDeletionCredentialReference) throws {
        guard TeamAuthWire.identifier(reference.credentialID),
              reference.bindingDigest.utf8.count == 64,
              reference.bindingDigest.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else { throw TeamWorkspaceError.invalidInput }
    }
    private func base(_ reference: TeamAccountDeletionCredentialReference) throws
        -> [String: Any] {
        try validate(reference)
        return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.credentialID,
            kSecAttrGeneric as String: Data(reference.bindingDigest.utf8),
            kSecAttrAccessible as String: accessibility,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true]
    }
    func load(_ reference: TeamAccountDeletionCredentialReference) throws
        -> TeamAccountDeletionStatusCredential? {
        var query = try base(reference)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        var raw: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &raw)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let fields = raw as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == reference.credentialID,
              fields[kSecAttrGeneric as String] as? Data
                == Data(reference.bindingDigest.utf8),
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String == accessibility,
              let bytes = fields[kSecValueData as String] as? Data else {
            throw TeamWorkspaceError.bindingMismatch
        }
        return try TeamAccountDeletionStatusCredential(bytes: bytes)
    }
    func insert(_ credential: TeamAccountDeletionStatusCredential,
                reference: TeamAccountDeletionCredentialReference) throws -> Bool {
        var attributes = try base(reference)
        attributes[kSecValueData as String] = credential.bytes
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw TeamWorkspaceError.unavailable }
        return true
    }
    func remove(_ reference: TeamAccountDeletionCredentialReference) throws {
        let status = SecItemDelete(try base(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TeamWorkspaceError.unavailable
        }
    }
}

/// Every stage must be idempotent: a crash can occur after the secure deletion
/// commits but before its journal checkpoint. A production implementation must
/// enumerate and delete every team-scoped item belonging to the exact account,
/// and treat absence as success. The binding intentionally carries no team ID.
/// as success. No incomplete built-in implementation is provided.
protocol TeamAccountSecureCustodyDeleting: Sendable {
    func delete(step: TeamAccountDeletionCleanupStep,
                binding: TeamAccountDeletionBinding) throws
}

/// Production account-global local erasure. Each SQLite store is shared across
/// team scopes, so one bound handle removes every row for the account. Agreement
/// identities must include every enrollment discovered for the account before
/// deletion starts. Each step is idempotent for restart recovery.
struct TeamAccountLocalStoreCleanup: TeamAccountSecureCustodyDeleting, Sendable {
    let outbox: TeamOutgoingStore
    let inbox: TeamInboxStore
    let agreements: [TeamAgreementKeyCustody]
    let device: TeamDeviceCustody
    let joins: TeamJoinStore
    let terms: any TeamAccountTermsDeleting
    let sessions: TeamAccountSessionStore

    func delete(step: TeamAccountDeletionCleanupStep,
                binding: TeamAccountDeletionBinding) throws {
        guard let origin = URL(string: binding.origin) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        let scope = try TeamAccountSessionScope(
            origin: origin, providerID: binding.providerID)
        switch step {
        case .teamCacheAndArchive:
            try outbox.deleteAccountData(accountID: binding.accountID)
            try inbox.deleteAccountData(accountID: binding.accountID)
            try joins.deleteAccount(audience: binding.origin,
                                    accountID: binding.accountID,
                                    authorityEpoch: binding.authorityEpoch)
        case .agreementIdentity:
            for agreement in agreements { try agreement.deleteIdentity() }
        case .deviceSigningIdentity:
            try device.deleteAccount(audience: binding.origin,
                                     accountID: binding.accountID,
                                     authorityEpoch: binding.authorityEpoch)
        case .termsAcceptance:
            try terms.removeAll(accountID: binding.accountID)
        case .accountSession:
            try sessions.removeCurrent(scope: scope, consent: true)
        }
    }
}

struct TeamAccountDeletionStartupGate: Sendable {
    let progressStore: any TeamAccountDeletionProgressStoring
    func blocksTeamActions(accountID: String) throws -> Bool {
        guard TeamAuthWire.identifier(accountID) else { throw TeamWorkspaceError.invalidInput }
        return try progressStore.load(accountID: accountID)?
            .phase.blocksTeamActions == true
    }
    func requireTeamActionsAllowed(accountID: String) throws {
        if try blocksTeamActions(accountID: accountID) {
            throw TeamWorkspaceError.busy
        }
    }
}

/// PREPARED and DISPATCHED are synchronously durable before their following side
/// effects. Cleanup starts only after an authoritative status proves revocation;
/// the journal and status token remain until the server reaches COMPLETED.
actor TeamAccountDeletionCoordinator {
    static let confirmation = TeamAccountDeletionRequest.confirmation
    private let initialBinding: TeamAccountDeletionBinding
    private let dispatch: (any TeamAccountDeletionDispatchTransport)?
    private let status: any TeamAccountDeletionStatusTransport
    private let progressStore: any TeamAccountDeletionProgressStoring
    private let credentialStore: any TeamAccountDeletionCredentialStoring
    private let cleanup: any TeamAccountSecureCustodyDeleting
    private let operationID: @Sendable () -> String
    private let credentialID: @Sendable () -> String
    private let credentialBytes: @Sendable () throws -> Data
    private var working = false

    init(binding: TeamAccountDeletionBinding,
         dispatch: (any TeamAccountDeletionDispatchTransport)?,
         status: any TeamAccountDeletionStatusTransport,
         progressStore: any TeamAccountDeletionProgressStoring,
         credentialStore: any TeamAccountDeletionCredentialStoring,
         cleanup: any TeamAccountSecureCustodyDeleting,
         operationID: @escaping @Sendable () -> String = { UUID().uuidString },
         credentialID: @escaping @Sendable () -> String = { UUID().uuidString },
         credentialBytes: @escaping @Sendable () throws -> Data = {
             var bytes = Data(count: 32)
             let status = bytes.withUnsafeMutableBytes {
                 SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
             }
             guard status == errSecSuccess else { throw TeamWorkspaceError.unavailable }
             return bytes
         }) throws {
        guard binding.version == TeamAccountDeletionBinding.currentVersion else {
            throw TeamWorkspaceError.invalidInput
        }
        self.initialBinding = binding; self.dispatch = dispatch; self.status = status
        self.progressStore = progressStore; self.credentialStore = credentialStore
        self.cleanup = cleanup; self.operationID = operationID
        self.credentialID = credentialID; self.credentialBytes = credentialBytes
    }
    func delete(confirmation: String) async throws {
        guard confirmation == Self.confirmation else { throw TeamWorkspaceError.invalidInput }
        try await run(createIfMissing: true)
    }
    func resumePending() async throws -> Bool {
        guard try progressStore.load(accountID: initialBinding.accountID) != nil else {
            return false
        }
        try await run(createIfMissing: false)
        return true
    }
    /// Requires a freshly authenticated caller, but reuses the exact durable
    /// request ID and status token after an ambiguous HTTP boundary.
    func retryExactRequest(confirmation: String) async throws {
        guard confirmation == Self.confirmation, let dispatch else {
            throw TeamWorkspaceError.invalidInput
        }
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        guard var progress = try progressStore.load(accountID: initialBinding.accountID),
              [.dispatched, .uncertain].contains(progress.phase) else {
            throw TeamWorkspaceError.invalidInput
        }
        let credential = try requireCredential(progress)
        progress.phase = .dispatched
        try progressStore.save(progress)
        let remote: TeamAccountDeletionStatus
        do {
            remote = try await dispatch.requestDeletion(binding: progress.binding,
                request: try .init(requestID: progress.operationID, credential: credential))
        } catch {
            progress.phase = .uncertain
            try progressStore.save(progress)
            throw error
        }
        try finishRemote(remote, progress: &progress)
        try finishIfAuthorized(&progress)
    }
    func blocksTeamActionsOnStartup() throws -> Bool {
        try TeamAccountDeletionStartupGate(progressStore: progressStore)
            .blocksTeamActions(accountID: initialBinding.accountID)
    }
    private func run(createIfMissing: Bool) async throws {
        guard !working else { throw TeamWorkspaceError.busy }
        working = true; defer { working = false }
        var progress: TeamAccountDeletionProgress
        if let current = try progressStore.load(accountID: initialBinding.accountID) {
            progress = current
        } else {
            guard createIfMissing else { return }
            let operation = operationID(), credential = credentialID()
            guard TeamAuthWire.identifier(operation), TeamAuthWire.identifier(credential) else {
                throw TeamWorkspaceError.invalidInput
            }
            progress = .init(version: TeamAccountDeletionProgress.currentVersion,
                binding: initialBinding, operationID: operation,
                credentialReference: .init(credentialID: credential,
                                           bindingDigest: initialBinding.digest),
                phase: .prepared, completedSteps: [])
            try progressStore.save(progress)
        }
        switch progress.phase {
        case .prepared:
            guard let dispatch else { throw TeamWorkspaceError.deletionPending }
            let credential = try ensureCredential(progress)
            progress.phase = .dispatched
            try progressStore.save(progress)
            do {
                let remote = try await dispatch.requestDeletion(binding: progress.binding,
                    request: try .init(requestID: progress.operationID,
                                       credential: credential))
                try finishRemote(remote, progress: &progress)
            } catch {
                if progress.phase == .dispatched {
                    progress.phase = .uncertain
                    try progressStore.save(progress)
                }
                throw error
            }
        case .dispatched, .uncertain:
            let credential = try requireCredential(progress)
            do {
                let remote = try await status.deletionStatus(binding: progress.binding,
                    request: try .init(deletionID: progress.operationID,
                                       credential: credential))
                try finishRemote(remote, progress: &progress)
            } catch {
                if progress.phase == .dispatched {
                    progress.phase = .uncertain
                    try progressStore.save(progress)
                }
                throw error
            }
        case .authorityRevoked:
            try performLocalCleanup(&progress)
            let credential = try requireCredential(progress)
            let remote = try await status.deletionStatus(binding: progress.binding,
                request: try .init(deletionID: progress.operationID,
                                   credential: credential))
            try finishRemote(remote, progress: &progress)
        case .serverCompleted:
            break
        }
        try finishIfAuthorized(&progress)
    }
    private func finishIfAuthorized(_ progress: inout TeamAccountDeletionProgress) throws {
        guard [.authorityRevoked, .serverCompleted].contains(progress.phase) else {
            throw TeamWorkspaceError.deletionPending
        }
        try performLocalCleanup(&progress)
        if progress.phase == .serverCompleted {
            try credentialStore.remove(progress.credentialReference)
            try progressStore.remove(progress)
        } else {
            throw TeamWorkspaceError.deletionPending
        }
    }
    private func performLocalCleanup(_ progress: inout TeamAccountDeletionProgress) throws {
        for step in TeamAccountDeletionCleanupStep.allCases
            .dropFirst(progress.completedSteps.count) {
            try cleanup.delete(step: step, binding: progress.binding)
            progress.completedSteps.append(step)
            try progressStore.save(progress)
        }
    }
    private func ensureCredential(_ progress: TeamAccountDeletionProgress) throws
        -> TeamAccountDeletionStatusCredential {
        if let existing = try credentialStore.load(progress.credentialReference) {
            return existing
        }
        let candidate = try TeamAccountDeletionStatusCredential(bytes: credentialBytes())
        if try credentialStore.insert(candidate, reference: progress.credentialReference) {
            return candidate
        }
        return try requireCredential(progress)
    }
    private func requireCredential(_ progress: TeamAccountDeletionProgress) throws
        -> TeamAccountDeletionStatusCredential {
        guard let value = try credentialStore.load(progress.credentialReference) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        return value
    }
    private func finishRemote(_ remote: TeamAccountDeletionStatus,
                              progress: inout TeamAccountDeletionProgress) throws {
        guard remote.deletionID == progress.operationID,
              remote.accountID == progress.binding.accountID else {
            throw TeamWorkspaceError.bindingMismatch
        }
        switch remote.state {
        case .revocationRequired:
            break
        case .cleanupSchedulingRequired, .pendingErasure:
            guard remote.authorityRevokedAt != nil else {
                throw TeamWorkspaceError.bindingMismatch
            }
            progress.phase = .authorityRevoked
            try progressStore.save(progress)
        case .completed:
            guard remote.authorityRevokedAt != nil else {
                throw TeamWorkspaceError.bindingMismatch
            }
            progress.phase = .serverCompleted
            try progressStore.save(progress)
        }
    }
}

enum TeamAccountDeletionRecoveryOutcome: Equatable, Sendable {
    case authenticationRequired
    case pending
    case completed
    case ambiguous
}

struct TeamAccountDeletionRecoveryResult: Equatable, Sendable {
    let accountID: String
    let outcome: TeamAccountDeletionRecoveryOutcome
}

/// Runs before ordinary session restoration and enumerates every durable account
/// record. It never needs or recreates a TeamAccountSessionSnapshot.
struct TeamAccountDeletionAppStartRecovery: Sendable {
    let status: any TeamAccountDeletionStatusTransport
    let progressStore: any TeamAccountDeletionProgressStoring
    let credentialStore: any TeamAccountDeletionCredentialStoring
    let cleanup: any TeamAccountSecureCustodyDeleting
    let statusRequestTimeoutNanoseconds: UInt64

    init(status: any TeamAccountDeletionStatusTransport,
         progressStore: any TeamAccountDeletionProgressStoring,
         credentialStore: any TeamAccountDeletionCredentialStoring,
         cleanup: any TeamAccountSecureCustodyDeleting,
         statusRequestTimeoutNanoseconds: UInt64 = 15_000_000_000) {
        self.status = status; self.progressStore = progressStore
        self.credentialStore = credentialStore; self.cleanup = cleanup
        self.statusRequestTimeoutNanoseconds = statusRequestTimeoutNanoseconds
    }

    func resumeAll() async -> [TeamAccountDeletionRecoveryResult] {
        let pending: [TeamAccountDeletionProgress]
        do { pending = try progressStore.loadAll() }
        catch { return [.init(accountID: "unknown", outcome: .ambiguous)] }
        var results = [TeamAccountDeletionRecoveryResult]()
        for progress in pending {
            if progress.phase == .prepared {
                results.append(.init(accountID: progress.binding.accountID,
                                     outcome: .authenticationRequired))
                continue
            }
            do {
                let coordinator = try TeamAccountDeletionCoordinator(
                    binding: progress.binding, dispatch: nil,
                    status: TeamAccountDeletionBoundedStatusTransport(
                        base: status, timeoutNanoseconds: statusRequestTimeoutNanoseconds),
                    progressStore: progressStore, credentialStore: credentialStore,
                    cleanup: cleanup)
                _ = try await coordinator.resumePending()
                results.append(.init(accountID: progress.binding.accountID,
                                     outcome: .completed))
            } catch TeamWorkspaceError.deletionPending {
                results.append(.init(accountID: progress.binding.accountID,
                                     outcome: .pending))
            } catch {
                results.append(.init(accountID: progress.binding.accountID,
                                     outcome: .ambiguous))
            }
        }
        return results
    }
}

private actor TeamAccountDeletionStatusDeadlineRace {
    enum Outcome: Sendable {
        case value(TeamAccountDeletionStatus)
        case failed
    }
    private var outcome: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    func wait() async -> Outcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            if let outcome { continuation.resume(returning: outcome) }
            else { waiter = continuation }
        }
    }

    func deliver(_ value: Outcome) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else if outcome == nil {
            outcome = value
        }
    }
}

private struct TeamAccountDeletionBoundedStatusTransport:
    TeamAccountDeletionStatusTransport, Sendable {
    let base: any TeamAccountDeletionStatusTransport
    let timeoutNanoseconds: UInt64

    func deletionStatus(binding: TeamAccountDeletionBinding,
                        request: TeamAccountDeletionStatusRequest) async throws
        -> TeamAccountDeletionStatus {
        guard timeoutNanoseconds > 0 else { throw TeamWorkspaceError.unavailable }
        let race = TeamAccountDeletionStatusDeadlineRace()
        let requestTask = Task {
            do {
                let value = try await base.deletionStatus(binding: binding, request: request)
                await race.deliver(.value(value))
            } catch {
                await race.deliver(.failed)
            }
        }
        let timeoutTask = Task {
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            await race.deliver(.failed)
        }
        defer { requestTask.cancel(); timeoutTask.cancel() }
        switch await race.wait() {
        case .value(let value): return value
        case .failed: throw TeamWorkspaceError.unavailable
        }
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

struct TeamWorkspacePublicBuildConfiguration: Equatable, Sendable {
    static let serviceOriginKey = "PinbookTeamServiceOrigin"
    static let appleClientIDKey = "PinbookTeamAppleClientID"
    static let googleNativeClientIDKey = "PinbookTeamGoogleNativeClientID"
    static let googleServerClientIDKey = "PinbookTeamGoogleServerClientID"
    static let authorityEpochKey = "PinbookTeamAuthorityEpoch"
    static let termsURLKey = "PinbookTeamTermsURL"
    static let privacyURLKey = "PinbookTeamPrivacyURL"
    static let invitationHostKey = "PinbookTeamInvitationHost"

    let serviceOrigin: URL
    let appleClientID: String
    let googleNativeClientID: String
    let googleServerClientID: String
    let authorityEpoch: String
    let termsURL: URL
    let privacyURL: URL
    let invitationHost: String

    static func parse(_ values: [String: String]) throws -> TeamWorkspaceBuildConfiguration {
        let keys = [serviceOriginKey, appleClientIDKey, googleNativeClientIDKey,
                    googleServerClientIDKey, authorityEpochKey, termsURLKey,
                    privacyURLKey, invitationHostKey]
        let normalized = Dictionary(uniqueKeysWithValues: keys.map {
            ($0, values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })
        if normalized.values.allSatisfy(\.isEmpty) { return .disabled }
        guard normalized.values.allSatisfy({ !$0.isEmpty }),
              let service = URL(string: normalized[serviceOriginKey]!),
              let terms = URL(string: normalized[termsURLKey]!),
              let privacy = URL(string: normalized[privacyURLKey]!),
              validOrigin(service), validPolicyURL(terms), validPolicyURL(privacy),
              validClientID(normalized[appleClientIDKey]!),
              validClientID(normalized[googleNativeClientIDKey]!),
              validClientID(normalized[googleServerClientIDKey]!),
              TeamAuthWire.identifier(normalized[authorityEpochKey]!),
              validHost(normalized[invitationHostKey]!),
              service.host?.lowercased() == normalized[invitationHostKey]!.lowercased() else {
            throw TeamAuthHTTPError.invalidConfiguration
        }
        return .enabled(.init(serviceOrigin: service,
            appleClientID: normalized[appleClientIDKey]!,
            googleNativeClientID: normalized[googleNativeClientIDKey]!,
            googleServerClientID: normalized[googleServerClientIDKey]!,
            authorityEpoch: normalized[authorityEpochKey]!, termsURL: terms,
            privacyURL: privacy, invitationHost: normalized[invitationHostKey]!.lowercased()))
    }

    static func parse(bundle: Bundle) throws -> TeamWorkspaceBuildConfiguration {
        let keys = [serviceOriginKey, appleClientIDKey, googleNativeClientIDKey,
                    googleServerClientIDKey, authorityEpochKey, termsURLKey,
                    privacyURLKey, invitationHostKey]
        return try parse(Dictionary(uniqueKeysWithValues: keys.map {
            ($0, bundle.object(forInfoDictionaryKey: $0) as? String ?? "")
        }))
    }

    private static func validOrigin(_ url: URL) -> Bool {
        guard canonicalHTTPS(url), url.path.isEmpty || url.path == "/" else { return false }
        return url.query == nil && url.fragment == nil
    }
    private static func validPolicyURL(_ url: URL) -> Bool {
        canonicalHTTPS(url) && !url.path.isEmpty && url.path != "/"
            && url.query == nil && url.fragment == nil
    }
    private static func canonicalHTTPS(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, let host = url.host, validHost(host) else { return false }
        return url.absoluteString.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value <= 0x7e }
    }
    private static func validHost(_ host: String) -> Bool {
        guard host == host.lowercased(), host.count <= 253, host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix("."),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0)
                  || $0 == 45 || $0 == 46 }) else { return false }
        var ipv4 = in_addr(), ipv6 = in6_addr()
        return host.withCString { inet_pton(AF_INET, $0, &ipv4) } != 1
            && host.withCString { inet_pton(AF_INET6, $0, &ipv6) } != 1
    }
    private static func validClientID(_ value: String) -> Bool {
        (3...512).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }
}

enum TeamWorkspaceBuildConfiguration: Equatable, Sendable {
    case disabled
    case enabled(TeamWorkspacePublicBuildConfiguration)
}

/// Concrete, inert network foundation. The same strict client implements the
/// frozen auth, onboarding, device registration, invitation, audience and
/// delivery HTTP contracts; compliance adds migration 027. No request is made
/// during construction and there is no fallback endpoint.
struct TeamWorkspaceHTTPComposition: Sendable {
    let configuration: TeamWorkspacePublicBuildConfiguration
    let http: TeamAuthHTTPClient
    let sessions: TeamAccountSessionStore
    let accounts: TeamWorkspaceAccountComposition
    let deletionStatus: TeamStoreComplianceHTTPTransport

    init(configuration: TeamWorkspacePublicBuildConfiguration,
         sessions: TeamAccountSessionStore = .init()) throws {
        let http = try TeamAuthHTTPClient(origin: configuration.serviceOrigin)
        self.configuration = configuration
        self.http = http
        self.sessions = sessions
        self.accounts = .init(sessions: sessions, transport: http)
        self.deletionStatus = .init(http: http)
    }

    func scope(for provider: TeamNativeSignInProvider) throws -> TeamAccountSessionScope {
        try .init(origin: configuration.serviceOrigin,
                  providerID: provider == .apple ? "apple" : "google")
    }

    func compliance(for snapshot: TeamAccountSessionSnapshot) throws
        -> TeamStoreComplianceHTTPTransport {
        .init(http: http, ticket: try TeamAccountAccessTicket(snapshot: snapshot))
    }
}

struct TeamWorkspaceProductionComposition: Sendable {
    let accounts: TeamWorkspaceAccountComposition
    let deletionRecovery: TeamAccountDeletionAppStartRecovery
    let sessionBootstrap: any TeamWorkspaceSessionBootstrapping
    let invitationRouter: TeamWorkspaceInvitationRouter
    let userActions: any TeamWorkspaceUserActionHandling
}

protocol TeamWorkspaceSessionBootstrapping: Sendable {
    func bootstrap(blockedAccountIDs: Set<String>) async throws
}

enum TeamWorkspaceUserAction: Equatable, Sendable {
    case signIn(TeamNativeSignInProvider)
    case createTeam
    case issueInvitation(TeamInvitationRole)
    case acceptTerms
    case sendNote(String)
    case refreshInbox
    case reportNote(noteID: String, authorID: String, reason: String)
    case reportUser(userID: String, reason: String)
    case blockUser(userID: String)
    case unblockUser(userID: String)
    case openInvitation(URL)
    case deleteAccount(confirmation: String)
}

protocol TeamWorkspaceUserActionHandling: Sendable {
    func perform(_ action: TeamWorkspaceUserAction) async throws
}

struct TeamWorkspacePresentedNote: Identifiable, Equatable, Sendable {
    let id: String
    let authorID: String
    let body: String
    let savedAt: Int64
}

struct TeamWorkspacePresentedMember: Identifiable, Equatable, Sendable {
    let id: String
    let isBlocked: Bool
}

struct TeamWorkspacePresentation: Equatable, Sendable {
    static let empty = Self(notes: [], members: [], invitation: nil)
    let notes: [TeamWorkspacePresentedNote]
    let members: [TeamWorkspacePresentedMember]
    let invitation: TeamInvitationShareItem?
}

protocol TeamWorkspacePresentationProviding: Sendable {
    func presentation() async throws -> TeamWorkspacePresentation
}

struct TeamWorkspaceInvitationRouter: Sendable {
    let expectedOrigin: String

    init(expectedOrigin: String) throws {
        _ = try TeamInvitationLink(origin: expectedOrigin,
            token: String(repeating: "A", count: 43))
        self.expectedOrigin = expectedOrigin
    }

    func route(_ url: URL) throws -> TeamInvitationLink {
        try TeamInvitationLink(validating: url, expectedOrigin: expectedOrigin)
    }
}

enum TeamWorkspaceStartupState: Equatable, Sendable {
    case recovering
    case disabled
    case ready([TeamAccountDeletionRecoveryResult])
    case failed

    var recoveryResults: [TeamAccountDeletionRecoveryResult] {
        if case .ready(let results) = self { return results }
        return []
    }

    var allowsTeamWorkspace: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Normal app composition is disabled. A future release host must deliberately
/// inject every approved server/custody dependency; this type stores no origin,
/// credential or fallback endpoint of its own.
enum TeamWorkspaceRuntimeConfiguration: Sendable {
    case disabled
    case injected(TeamWorkspaceProductionComposition)

    static let productionDefault: Self = .disabled
    var isEnabled: Bool {
        if case .injected = self { return true }
        return false
    }
    var userActions: (any TeamWorkspaceUserActionHandling)? {
        guard case .injected(let composition) = self else { return nil }
        return composition.userActions
    }
    func presentation() async throws -> TeamWorkspacePresentation {
        guard case .injected(let composition) = self,
              let provider = composition.userActions as? any TeamWorkspacePresentationProviding else {
            return .empty
        }
        return try await provider.presentation()
    }
    func invitation(from url: URL) -> TeamInvitationLink? {
        guard case .injected(let composition) = self else { return nil }
        return try? composition.invitationRouter.route(url)
    }
    func prepareForAppStart() async -> TeamWorkspaceStartupState {
        guard case .injected(let composition) = self else { return .disabled }
        let results = await composition.deletionRecovery.resumeAll()
        let blocked = Set(results.compactMap {
            $0.outcome == .completed || $0.accountID == "unknown" ? nil : $0.accountID
        })
        do {
            try await composition.sessionBootstrap.bootstrap(blockedAccountIDs: blocked)
            return .ready(results)
        } catch {
            return .failed
        }
    }
}

/// Approved production implementations conform once they can satisfy every
/// frozen workspace operation. There is intentionally no default HTTP conformer:
/// deletion 027 is frozen, but server 028 workers and Infrastructure staging are
/// still required before any network activation.
protocol TeamWorkspaceRemoteTransport: TeamWorkspaceAudienceProviding,
    TeamWorkspaceSubmissionTransport, TeamWorkspaceInboxTransport,
    TeamSafetyTransport, TeamAccountDeletionDispatchTransport {}

/// Adds exact-generation session checks around every injected remote operation.
/// Access credentials remain volatile inside `TeamAccountAccessTicket` and are
/// never copied into workspace models, URLs, defaults, logs or SQLite stores.
actor TeamWorkspaceSessionBoundRemote: TeamWorkspaceRemoteTransport {
    private let ticket: TeamAccountAccessTicket
    private let sessions: TeamAccountSessionStore
    private let remote: any TeamWorkspaceRemoteTransport
    private let deletionGate: TeamAccountDeletionStartupGate
    private let clock: @Sendable () -> Int64

    init(ticket: TeamAccountAccessTicket, sessions: TeamAccountSessionStore,
         remote: any TeamWorkspaceRemoteTransport,
         deletionGate: TeamAccountDeletionStartupGate,
         clock: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) throws {
        try sessions.requireCurrentAccess(ticket, now: clock())
        self.ticket = ticket; self.sessions = sessions
        self.remote = remote; self.deletionGate = deletionGate; self.clock = clock
    }

    func audience(teamID: String, enrollmentID: String) async throws -> TeamAudience {
        try checkProtected(); let value = try await remote.audience(teamID: teamID, enrollmentID: enrollmentID)
        try checkProtected(); return value
    }
    func reserve(_ plan: TeamWorkspaceSendPlan) async throws -> TeamDeliverySubmissionReservation {
        try checkProtected(); let value = try await remote.reserve(plan)
        try checkProtected(); return value
    }
    func status(deliveryID: String, jweSHA256: String) async throws -> TeamDeliverySubmissionStatus {
        try checkProtected(); let value = try await remote.status(deliveryID: deliveryID, jweSHA256: jweSHA256)
        try checkProtected(); return value
    }
    func pending(after: TeamDeliveryListCursor?, limit: Int) async throws -> TeamPendingDeliveryPage {
        try checkProtected(); let value = try await remote.pending(after: after, limit: limit)
        try checkProtected(); return value
    }
    func fetch(_ pending: TeamPendingDelivery) async throws -> TeamWorkspaceFetchedDelivery {
        try checkProtected(); let value = try await remote.fetch(pending)
        try checkProtected(); return value
    }
    func acknowledge(_ receipt: PendingTeamReceipt) async throws -> TeamWorkspaceACKReply {
        try checkProtected(); let value = try await remote.acknowledge(receipt)
        try checkProtected(); return value
    }
    func execute(accountID: String, teamID: String, action: TeamSafetyAction) async throws {
        guard accountID == ticket.accountID else { throw TeamWorkspaceError.bindingMismatch }
        try checkProtected(); try await remote.execute(accountID: accountID, teamID: teamID, action: action)
        try checkProtected()
    }
    func requestDeletion(binding: TeamAccountDeletionBinding,
                         request: TeamAccountDeletionRequest) async throws
        -> TeamAccountDeletionStatus {
        guard binding.accountID == ticket.accountID,
              binding.providerID == ticket.scope.providerID,
              binding.origin + "/" == ticket.scope.origin.absoluteString,
              TeamAuthWire.identifier(request.requestID) else {
            throw TeamWorkspaceError.bindingMismatch
        }
        try checkSession()
        let value = try await remote.requestDeletion(binding: binding, request: request)
        // A successful remote deletion may invalidate the session immediately,
        // so no post-dispatch session assertion is valid for this one operation.
        return value
    }

    private func checkProtected() throws {
        try checkSession()
        try deletionGate.requireTeamActionsAllowed(accountID: ticket.accountID)
        try Task.checkCancellation()
    }

    private func checkSession() throws {
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
    let deletionBinding: TeamAccountDeletionBinding
    let deletionStatus: any TeamAccountDeletionStatusTransport
    let deletionProgress: any TeamAccountDeletionProgressStoring
    let deletionCredentials: any TeamAccountDeletionCredentialStoring
    let accountCleanup: any TeamAccountSecureCustodyDeleting

    init(session: TeamAccountSessionSnapshot, sessions: TeamAccountSessionStore,
         teamID: String, enrollmentID: String,
         terms: any TeamTermsStoring, outbox: TeamOutgoingStore,
         inbox: TeamInboxStore, agreement: TeamAgreementKeyCustody,
         deletionBinding: TeamAccountDeletionBinding,
         deletionStatus: any TeamAccountDeletionStatusTransport,
         deletionProgress: any TeamAccountDeletionProgressStoring,
         deletionCredentials: any TeamAccountDeletionCredentialStoring,
         accountCleanup: any TeamAccountSecureCustodyDeleting,
         remote: any TeamWorkspaceRemoteTransport,
         clock: @escaping @Sendable () -> Int64 = {
             Int64(Date().timeIntervalSince1970 * 1_000)
         }) throws {
        let ticket = try TeamAccountAccessTicket(snapshot: session)
        let expectedAgreement = try TeamAgreementScope(
            origin: deletionBinding.origin, accountID: session.accountID,
            authorityEpoch: deletionBinding.authorityEpoch,
            enrollmentID: enrollmentID)
        guard TeamAuthWire.identifier(teamID), TeamAuthWire.identifier(enrollmentID),
              outbox.sender.userId == session.accountID,
              outbox.teamId == teamID, outbox.sender.enrollmentId == enrollmentID,
              inbox.target.userId == session.accountID,
              inbox.teamId == teamID, inbox.target.enrollmentId == enrollmentID,
              deletionBinding.accountID == session.accountID,
              deletionBinding.providerID == session.scope.providerID,
              deletionBinding.origin + "/" == session.scope.origin.absoluteString,
              deletionBinding.custodyID == session.generation.uuidString,
              agreement.scope == expectedAgreement else {
            throw TeamWorkspaceError.bindingMismatch
        }
        self.accountID = session.accountID; self.teamID = teamID
        self.enrollmentID = enrollmentID; self.session = session
        self.sessions = sessions; self.terms = terms
        self.outbox = outbox; self.inbox = inbox; self.agreement = agreement
        self.deletionBinding = deletionBinding; self.deletionStatus = deletionStatus
        self.deletionProgress = deletionProgress
        self.deletionCredentials = deletionCredentials
        self.accountCleanup = accountCleanup
        self.remote = try TeamWorkspaceSessionBoundRemote(ticket: ticket,
            sessions: sessions, remote: remote,
            deletionGate: .init(progressStore: deletionProgress), clock: clock)
    }

    func sender() throws -> TeamManualNoteSendCoordinator {
        try requireTeamActionsAllowed()
        return try TeamManualNoteSendCoordinator(accountID: accountID, teamID: teamID,
            enrollmentID: enrollmentID, outbox: outbox, terms: .init(store: terms),
            audience: remote, transport: remote)
    }
    func receiver() throws -> TeamForegroundInboxCoordinator {
        try requireTeamActionsAllowed()
        return try TeamForegroundInboxCoordinator(teamID: teamID, enrollmentID: enrollmentID,
            inbox: inbox, custody: agreement, transport: remote)
    }
    func safety() throws -> TeamSafetyCoordinator {
        try requireTeamActionsAllowed()
        return try TeamSafetyCoordinator(accountID: accountID, teamID: teamID, transport: remote)
    }
    func deletion() throws -> TeamAccountDeletionCoordinator {
        try TeamAccountDeletionCoordinator(binding: deletionBinding,
            dispatch: remote, status: deletionStatus,
            progressStore: deletionProgress, credentialStore: deletionCredentials,
            cleanup: accountCleanup)
    }
    private func requireTeamActionsAllowed() throws {
        try TeamAccountDeletionStartupGate(progressStore: deletionProgress)
            .requireTeamActionsAllowed(accountID: accountID)
    }
}

/// Functional user-action owner for an already authenticated, registered and
/// joined account. It drives the real protected stores and frozen HTTP contracts;
/// pre-connection sign-in/create/join remains the responsibility of the explicit
/// onboarding owner so no UI action can invent missing authority.
actor TeamWorkspaceConnectedActionHandler: TeamWorkspaceUserActionHandling,
    TeamWorkspacePresentationProviding {
    private let connected: TeamWorkspaceConnectedComposition
    private let http: TeamAuthHTTPClient
    private let termsTransport: any TeamStoreTermsTransport
    private let invitationOrigin: String
    private var latestInvitation: TeamInvitationShareItem?
    private var blockedAccountIDs = Set<String>()
    private var working = false

    init(connected: TeamWorkspaceConnectedComposition, http: TeamAuthHTTPClient,
         termsTransport: any TeamStoreTermsTransport,
         invitationOrigin: String) throws {
        _ = try TeamWorkspaceInvitationRouter(expectedOrigin: invitationOrigin)
        self.connected = connected
        self.http = http
        self.termsTransport = termsTransport
        self.invitationOrigin = invitationOrigin
    }

    func perform(_ action: TeamWorkspaceUserAction) async throws {
        guard !working else { throw TeamWorkspaceError.busy }
        working = true
        defer { working = false }
        switch action {
        case .acceptTerms:
            if try connected.terms.load(accountID: connected.accountID,
                                        teamID: connected.teamID) != nil { return }
            let receipt = try await termsTransport.acceptTerms(requestID: UUID().uuidString)
            guard receipt.accountID == connected.accountID else {
                throw TeamWorkspaceError.bindingMismatch
            }
            _ = try TeamTermsGate(store: connected.terms).accept(
                accountID: connected.accountID, teamID: connected.teamID,
                acceptedAt: receipt.acceptedAt, explicitConsent: true)
        case .sendNote(let body):
            _ = try await connected.sender().queueAndSubmit(body: body)
        case .refreshInbox:
            _ = try await connected.receiver().refresh()
        case .reportNote(let noteID, let authorID, let reason):
            try await connected.safety().execute(.reportNote(
                noteID: noteID, authorID: authorID, reason: reason))
        case .reportUser(let userID, let reason):
            try await connected.safety().execute(.reportUser(userID: userID, reason: reason))
        case .blockUser(let userID):
            try await connected.safety().execute(.blockUser(userID: userID))
            blockedAccountIDs.insert(userID)
        case .unblockUser(let userID):
            try await connected.safety().execute(.unblockUser(userID: userID))
            blockedAccountIDs.remove(userID)
        case .issueInvitation(let role):
            let issued = try await http.issueInvitation(teamID: connected.teamID,
                enrollmentID: connected.enrollmentID, role: role,
                session: connected.session)
            latestInvitation = try TeamInvitationShareItem(origin: invitationOrigin,
                                                            issued: issued)
        case .deleteAccount(let confirmation):
            try await connected.deletion().delete(confirmation: confirmation)
        case .signIn, .createTeam, .openInvitation:
            throw TeamWorkspaceError.invalidInput
        }
    }

    func presentation() async throws -> TeamWorkspacePresentation {
        let notes = try connected.inbox.archivePage(limit: 50).notes.map {
            TeamWorkspacePresentedNote(id: $0.envelope.noteId,
                authorID: $0.envelope.authorUserId, body: $0.envelope.body,
                savedAt: $0.savedAt)
        }
        let audience = try await connected.remote.audience(
            teamID: connected.teamID, enrollmentID: connected.enrollmentID)
        let accountIDs = Set(audience.targets.map(\.accountID))
            .subtracting([connected.accountID]).sorted()
        let members = accountIDs.map {
            TeamWorkspacePresentedMember(id: $0,
                isBlocked: blockedAccountIDs.contains($0))
        }
        return .init(notes: notes, members: members, invitation: latestInvitation)
    }
}
