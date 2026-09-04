import CryptoKit
import Foundation

enum TeamDeliveryJournalEventError: Error, Equatable {
    case invalidInput
    case bindingMismatch
}

/// Exact recipient identity frozen into ACCEPT, ACK and CANCEL journal events.
/// It is metadata only and does not grant access or prove current membership.
struct TeamFrozenDeliveryTarget: Hashable, Sendable, CustomStringConvertible,
                                 CustomDebugStringConvertible, CustomReflectable {
    let userId: String
    let deviceId: String
    let enrollmentId: String
    let agreementKeyThumbprint: String

    init(userId: String, deviceId: String, enrollmentId: String,
         agreementKeyThumbprint: String) throws {
        do {
            try TeamDeliveryRules.requireID(userId)
            try TeamDeliveryRules.requireID(deviceId)
            try TeamDeliveryRules.requireID(enrollmentId)
        } catch {
            throw TeamDeliveryJournalEventError.invalidInput
        }
        guard TeamAuthWire.credential(agreementKeyThumbprint) else {
            throw TeamDeliveryJournalEventError.invalidInput
        }
        self.userId = userId
        self.deviceId = deviceId
        self.enrollmentId = enrollmentId
        self.agreementKeyThumbprint = agreementKeyThumbprint
    }

    var description: String { "TeamFrozenDeliveryTarget(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    fileprivate var canonicalJSON: String {
        let fields = [
            "\"agreementKeyThumbprint\":\"" + agreementKeyThumbprint + "\"",
            "\"deviceId\":\"" + deviceId + "\"",
            "\"enrollmentId\":\"" + enrollmentId + "\"",
            "\"userId\":\"" + userId + "\"",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }
}

/// Immutable ACCEPT metadata matching the committed Android/server journal contract.
/// This does not activate a submit route, object store, journal or ACK behavior.
struct TeamDeliveryAcceptedEvent: Equatable, Sendable, CustomStringConvertible,
                                  CustomDebugStringConvertible, CustomReflectable {
    let eventId: String
    let kind: String
    let deliveryId: String
    let at: Int64
    let teamId: String
    let senderUserId: String
    let senderDeviceId: String
    let senderEnrollmentId: String
    let authorityEpoch: String
    let membershipRevision: Int64
    let audienceDigest: String
    let intentSha256: String
    let jweBytes: Int
    let jweSha256: String
    let objectId: String
    let createdAt: Int64
    let reservationExpiresAt: Int64
    let writeStartedAt: Int64
    let objectVerifiedAt: Int64
    let acceptedAt: Int64
    let expiresAt: Int64
    let targets: [TeamFrozenDeliveryTarget]

    fileprivate init(eventId: String, kind: String, deliveryId: String, at: Int64,
                     teamId: String, senderUserId: String, senderDeviceId: String,
                     senderEnrollmentId: String, authorityEpoch: String,
                     membershipRevision: Int64, audienceDigest: String,
                     intentSha256: String, jweBytes: Int, jweSha256: String,
                     objectId: String, createdAt: Int64, reservationExpiresAt: Int64,
                     writeStartedAt: Int64, objectVerifiedAt: Int64, acceptedAt: Int64,
                     expiresAt: Int64, targets: [TeamFrozenDeliveryTarget]) {
        self.eventId = eventId
        self.kind = kind
        self.deliveryId = deliveryId
        self.at = at
        self.teamId = teamId
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.senderEnrollmentId = senderEnrollmentId
        self.authorityEpoch = authorityEpoch
        self.membershipRevision = membershipRevision
        self.audienceDigest = audienceDigest
        self.intentSha256 = intentSha256
        self.jweBytes = jweBytes
        self.jweSha256 = jweSha256
        self.objectId = objectId
        self.createdAt = createdAt
        self.reservationExpiresAt = reservationExpiresAt
        self.writeStartedAt = writeStartedAt
        self.objectVerifiedAt = objectVerifiedAt
        self.acceptedAt = acceptedAt
        self.expiresAt = expiresAt
        self.targets = targets
    }

    var description: String { "TeamDeliveryAcceptedEvent(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamDeliveryAcknowledgementEvent: Equatable, Sendable, CustomStringConvertible,
                                         CustomDebugStringConvertible, CustomReflectable {
    let eventId: String
    let kind: String
    let deliveryId: String
    let at: Int64
    let target: TeamFrozenDeliveryTarget

    fileprivate init(eventId: String, kind: String, deliveryId: String, at: Int64,
                     target: TeamFrozenDeliveryTarget) {
        self.eventId = eventId
        self.kind = kind
        self.deliveryId = deliveryId
        self.at = at
        self.target = target
    }

    var description: String { "TeamDeliveryAcknowledgementEvent(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamDeliveryCancellationEvent: Equatable, Sendable, CustomStringConvertible,
                                      CustomDebugStringConvertible, CustomReflectable {
    let eventId: String
    let kind: String
    let deliveryId: String
    let at: Int64
    let target: TeamFrozenDeliveryTarget
    let actorUserId: String
    let reason: String

    fileprivate init(eventId: String, kind: String, deliveryId: String, at: Int64,
                     target: TeamFrozenDeliveryTarget, actorUserId: String, reason: String) {
        self.eventId = eventId
        self.kind = kind
        self.deliveryId = deliveryId
        self.at = at
        self.target = target
        self.actorUserId = actorUserId
        self.reason = reason
    }

    var description: String { "TeamDeliveryCancellationEvent(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum TeamDeliveryJournalEventCodec {
    static let acceptedKind = "ACCEPT"
    static let acknowledgementKind = "ACK"
    static let cancellationKind = "CANCEL"
    static let membershipRemovedReason = "MEMBERSHIP_REMOVED"
    static let maximumReservationMilliseconds: Int64 = 900_000
    static let maximumEventBytes = 8 * 1024

    static func accepted(intent: TeamDeliverySubmitIntent, canonicalIntent: Data,
                         teamId: String, senderUserId: String, senderDeviceId: String,
                         senderEnrollmentId: String, authorityEpoch: String,
                         createdAt: Int64, reservationExpiresAt: Int64,
                         writeStartedAt: Int64, objectVerifiedAt: Int64,
                         acceptedAt: Int64,
                         targets: [TeamFrozenDeliveryTarget]) throws -> TeamDeliveryAcceptedEvent {
        var intentBytes = canonicalIntent
        defer { intentBytes.resetBytes(in: intentBytes.startIndex..<intentBytes.endIndex) }
        guard intentBytes == (try? TeamDeliverySubmitIntentCodec.encode(intent)) else {
            throw TeamDeliveryJournalEventError.bindingMismatch
        }
        let event = TeamDeliveryAcceptedEvent(
            eventId: "accept-" + intent.jweSha256, kind: acceptedKind,
            deliveryId: intent.deliveryId, at: acceptedAt, teamId: teamId,
            senderUserId: senderUserId, senderDeviceId: senderDeviceId,
            senderEnrollmentId: senderEnrollmentId, authorityEpoch: authorityEpoch,
            membershipRevision: intent.membershipRevision,
            audienceDigest: intent.audienceDigest,
            intentSha256: hexSHA256(intentBytes), jweBytes: intent.jweBytes,
            jweSha256: intent.jweSha256, objectId: intent.jweSha256,
            createdAt: createdAt, reservationExpiresAt: reservationExpiresAt,
            writeStartedAt: writeStartedAt, objectVerifiedAt: objectVerifiedAt,
            acceptedAt: acceptedAt,
            expiresAt: try TeamDeliveryRules.expiresAt(acceptedAt: acceptedAt),
            targets: targets)
        try validate(event)
        return event
    }

    static func acknowledgement(eventId: String, deliveryId: String, at: Int64,
                                target: TeamFrozenDeliveryTarget) throws
        -> TeamDeliveryAcknowledgementEvent {
        let event = TeamDeliveryAcknowledgementEvent(eventId: eventId,
            kind: acknowledgementKind, deliveryId: deliveryId, at: at, target: target)
        try validate(event)
        return event
    }

    static func cancellation(eventId: String, deliveryId: String, at: Int64,
                             target: TeamFrozenDeliveryTarget, actorUserId: String,
                             reason: String = membershipRemovedReason) throws
        -> TeamDeliveryCancellationEvent {
        let event = TeamDeliveryCancellationEvent(eventId: eventId,
            kind: cancellationKind, deliveryId: deliveryId, at: at, target: target,
            actorUserId: actorUserId, reason: reason)
        try validate(event)
        return event
    }

    static func validate(_ event: TeamDeliveryAcceptedEvent) throws {
        try ids([event.deliveryId, event.teamId, event.senderUserId, event.senderDeviceId,
                 event.senderEnrollmentId, event.authorityEpoch, event.objectId])
        guard event.kind == acceptedKind,
              event.eventId == "accept-" + event.jweSha256,
              event.objectId == event.jweSha256,
              validHexDigest(event.intentSha256), validHexDigest(event.jweSha256),
              TeamAuthWire.credential(event.audienceDigest),
              validTime(event.at), validTime(event.createdAt),
              validTime(event.reservationExpiresAt), validTime(event.writeStartedAt),
              validTime(event.objectVerifiedAt), validTime(event.acceptedAt),
              validTime(event.expiresAt), event.at == event.acceptedAt,
              (0...TeamAuthWire.maximumSafeTime).contains(event.membershipRevision),
              (1...TeamDeliveryJWE.maximumSerializedBytes).contains(event.jweBytes),
              event.createdAt <= event.writeStartedAt,
              event.writeStartedAt <= event.objectVerifiedAt,
              event.objectVerifiedAt <= event.acceptedAt,
              event.acceptedAt < event.reservationExpiresAt,
              event.createdAt <= TeamAuthWire.maximumSafeTime - maximumReservationMilliseconds,
              event.reservationExpiresAt <= event.createdAt + maximumReservationMilliseconds,
              event.acceptedAt <= TeamAuthWire.maximumSafeTime - TeamDeliveryRules.retentionMilliseconds,
              event.expiresAt == event.acceptedAt + TeamDeliveryRules.retentionMilliseconds,
              (1...TeamDeliveryRules.maximumRecipients).contains(event.targets.count)
        else { throw TeamDeliveryJournalEventError.invalidInput }

        let users = event.targets.map(\.userId)
        let devices = event.targets.map(\.deviceId)
        let enrollments = event.targets.map(\.enrollmentId)
        let thumbprints = event.targets.map(\.agreementKeyThumbprint)
        let strictlyOrdered = zip(thumbprints, thumbprints.dropFirst()).allSatisfy {
            $0 < $1
        }
        guard !users.contains(event.senderUserId), Set(users).count == users.count,
              Set(devices).count == devices.count,
              Set(enrollments).count == enrollments.count,
              strictlyOrdered, audienceDigest(thumbprints) == event.audienceDigest
        else { throw TeamDeliveryJournalEventError.invalidInput }
    }

    static func validate(_ event: TeamDeliveryAcknowledgementEvent) throws {
        try ids([event.eventId, event.deliveryId])
        guard event.kind == acknowledgementKind, validTime(event.at) else {
            throw TeamDeliveryJournalEventError.invalidInput
        }
    }

    static func validate(_ event: TeamDeliveryCancellationEvent) throws {
        try ids([event.eventId, event.deliveryId, event.actorUserId])
        guard event.kind == cancellationKind, event.reason == membershipRemovedReason,
              validTime(event.at) else { throw TeamDeliveryJournalEventError.invalidInput }
    }

    static func canonicalData(_ event: TeamDeliveryAcceptedEvent) throws -> Data {
        try validate(event)
        let targetJSON = event.targets.map(\.canonicalJSON).joined(separator: ",")
        let fields = [
            "\"acceptedAt\":" + String(event.acceptedAt),
            "\"at\":" + String(event.at),
            "\"audienceDigest\":\"" + event.audienceDigest + "\"",
            "\"authorityEpoch\":\"" + event.authorityEpoch + "\"",
            "\"createdAt\":" + String(event.createdAt),
            "\"deliveryId\":\"" + event.deliveryId + "\"",
            "\"eventId\":\"" + event.eventId + "\"",
            "\"expiresAt\":" + String(event.expiresAt),
            "\"intentSha256\":\"" + event.intentSha256 + "\"",
            "\"jweBytes\":" + String(event.jweBytes),
            "\"jweSha256\":\"" + event.jweSha256 + "\"",
            "\"kind\":\"" + event.kind + "\"",
            "\"membershipRevision\":" + String(event.membershipRevision),
            "\"objectId\":\"" + event.objectId + "\"",
            "\"objectVerifiedAt\":" + String(event.objectVerifiedAt),
            "\"reservationExpiresAt\":" + String(event.reservationExpiresAt),
            "\"senderDeviceId\":\"" + event.senderDeviceId + "\"",
            "\"senderEnrollmentId\":\"" + event.senderEnrollmentId + "\"",
            "\"senderUserId\":\"" + event.senderUserId + "\"",
            "\"targets\":[" + targetJSON + "]",
            "\"teamId\":\"" + event.teamId + "\"",
            "\"writeStartedAt\":" + String(event.writeStartedAt),
        ]
        let text = "{" + fields.joined(separator: ",") + "}"
        let data = Data(text.utf8)
        guard data.count <= maximumEventBytes else {
            throw TeamDeliveryJournalEventError.invalidInput
        }
        return data
    }

    static func canonicalData(_ event: TeamDeliveryAcknowledgementEvent) throws -> Data {
        try validate(event)
        let fields = [
            "\"at\":" + String(event.at),
            "\"deliveryId\":\"" + event.deliveryId + "\"",
            "\"eventId\":\"" + event.eventId + "\"",
            "\"kind\":\"" + event.kind + "\"",
            "\"target\":" + event.target.canonicalJSON,
        ]
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    static func canonicalData(_ event: TeamDeliveryCancellationEvent) throws -> Data {
        try validate(event)
        let fields = [
            "\"actorUserId\":\"" + event.actorUserId + "\"",
            "\"at\":" + String(event.at),
            "\"deliveryId\":\"" + event.deliveryId + "\"",
            "\"eventId\":\"" + event.eventId + "\"",
            "\"kind\":\"" + event.kind + "\"",
            "\"reason\":\"" + event.reason + "\"",
            "\"target\":" + event.target.canonicalJSON,
        ]
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    private static func ids(_ values: [String]) throws {
        do { for value in values { try TeamDeliveryRules.requireID(value) } }
        catch { throw TeamDeliveryJournalEventError.invalidInput }
    }

    private static func validTime(_ value: Int64) -> Bool {
        (0...TeamAuthWire.maximumSafeTime).contains(value)
    }

    private static func validHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func audienceDigest(_ thumbprints: [String]) -> String {
        let input = "[" + thumbprints.map { "\"" + $0 + "\"" }.joined(separator: ",") + "]"
        return base64URL(Data(SHA256.hash(data: Data(input.utf8))))
    }

    private static func hexSHA256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
