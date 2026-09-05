import CoreFoundation
import CryptoKit
import Foundation

enum TeamDeliverySubmitIntentError: Error, Equatable {
    case invalidInput
    case invalidIntent
    case bindingMismatch
    case jweMismatch
}

/// Signed metadata for a future staged object submit. Not upload or acceptance.
struct TeamDeliverySubmitIntent: Equatable, Sendable, CustomStringConvertible,
                                 CustomDebugStringConvertible, CustomReflectable {
    let audienceDigest: String
    let deliveryId: String
    let jweBytes: Int
    let jweSha256: String
    let membershipRevision: Int64
    let type: String

    var description: String { "TeamDeliverySubmitIntent(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func verifyCanonicalJWE(_ serialized: String) throws {
        guard serialized.utf8.count == jweBytes,
              (1...TeamDeliveryJWE.maximumSerializedBytes).contains(serialized.utf8.count),
              serialized.utf8.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            throw TeamDeliverySubmitIntentError.jweMismatch
        }
        var bytes = Data(serialized.utf8)
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        guard TeamDeliverySubmitIntentCodec.sha256(bytes) == jweSha256 else {
            throw TeamDeliverySubmitIntentError.jweMismatch
        }
    }
}

enum TeamDeliverySubmitIntentCodec {
    static let type = "pinbook-delivery-submit-v1"
    static let maximumIntentBytes = 512

    static func fromCanonicalJWE(deliveryId: String, membershipRevision: Int64,
                                 audienceDigest: String,
                                 serialized: String) throws -> TeamDeliverySubmitIntent {
        guard (1...TeamDeliveryJWE.maximumSerializedBytes).contains(serialized.utf8.count),
              serialized.utf8.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            throw TeamDeliverySubmitIntentError.invalidInput
        }
        var bytes = Data(serialized.utf8)
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        let value = TeamDeliverySubmitIntent(audienceDigest: audienceDigest,
            deliveryId: deliveryId, jweBytes: bytes.count, jweSha256: sha256(bytes),
            membershipRevision: membershipRevision, type: type)
        try validate(value)
        try value.verifyCanonicalJWE(serialized)
        return value
    }

    static func validate(_ value: TeamDeliverySubmitIntent) throws {
        do { try TeamDeliveryRules.requireID(value.deliveryId) }
        catch { throw TeamDeliverySubmitIntentError.invalidInput }
        guard value.type == type,
              (0...TeamAuthWire.maximumSafeTime).contains(value.membershipRevision),
              (1...TeamDeliveryJWE.maximumSerializedBytes).contains(value.jweBytes),
              validHexDigest(value.jweSha256),
              TeamAuthWire.credential(value.audienceDigest) else {
            throw TeamDeliverySubmitIntentError.invalidInput
        }
    }

    static func encode(_ value: TeamDeliverySubmitIntent) throws -> Data {
        try validate(value)
        let text = "{\"audienceDigest\":\"\(value.audienceDigest)\"," +
            "\"deliveryId\":\"\(value.deliveryId)\",\"jweBytes\":\(value.jweBytes)," +
            "\"jweSha256\":\"\(value.jweSha256)\"," +
            "\"membershipRevision\":\(value.membershipRevision),\"type\":\"\(value.type)\"}"
        let result = Data(text.utf8)
        guard (1...maximumIntentBytes).contains(result.count),
              result.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            throw TeamDeliverySubmitIntentError.invalidInput
        }
        return result
    }

    static func decode(_ bytes: Data, expectedDeliveryId: String,
                       expectedMembershipRevision: Int64,
                       expectedAudienceDigest: String) throws -> TeamDeliverySubmitIntent {
        guard (1...maximumIntentBytes).contains(bytes.count),
              !bytes.starts(with: [0xef, 0xbb, 0xbf]),
              bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            throw TeamDeliverySubmitIntentError.invalidIntent
        }
        do { try TeamDeliveryRules.requireID(expectedDeliveryId) }
        catch { throw TeamDeliverySubmitIntentError.invalidInput }
        guard (0...TeamAuthWire.maximumSafeTime).contains(expectedMembershipRevision),
              TeamAuthWire.credential(expectedAudienceDigest) else {
            throw TeamDeliverySubmitIntentError.invalidInput
        }
        let object: [String: Any]
        do { object = try TeamStrictJSON.object(bytes, maximumBytes: maximumIntentBytes) }
        catch { throw TeamDeliverySubmitIntentError.invalidIntent }
        guard Set(object.keys) == ["audienceDigest", "deliveryId", "jweBytes",
                                   "jweSha256", "membershipRevision", "type"],
              let audience = object["audienceDigest"] as? String,
              let delivery = object["deliveryId"] as? String,
              let jweSize = exactInteger(object["jweBytes"]),
              jweSize <= Int64(Int.max),
              let jweDigest = object["jweSha256"] as? String,
              let revision = exactInteger(object["membershipRevision"]),
              let wireType = object["type"] as? String else {
            throw TeamDeliverySubmitIntentError.invalidIntent
        }
        let value = TeamDeliverySubmitIntent(audienceDigest: audience,
            deliveryId: delivery, jweBytes: Int(jweSize), jweSha256: jweDigest,
            membershipRevision: revision, type: wireType)
        do { try validate(value) }
        catch { throw TeamDeliverySubmitIntentError.invalidIntent }
        guard value.deliveryId == expectedDeliveryId,
              value.membershipRevision == expectedMembershipRevision,
              value.audienceDigest == expectedAudienceDigest else {
            throw TeamDeliverySubmitIntentError.bindingMismatch
        }
        var canonical = try encode(value)
        defer { canonical.resetBytes(in: canonical.startIndex..<canonical.endIndex) }
        guard canonical == bytes else { throw TeamDeliverySubmitIntentError.invalidIntent }
        return value
    }

    fileprivate static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func validHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func exactInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.int64Value
    }
}

enum TeamDeliveryReservationError: Error, Equatable {
    case invalidRequest
    case invalidReservation
    case bindingMismatch
}

enum TeamDeliveryReservationState: String, CaseIterable, Sendable {
    case reserved = "RESERVED"
    case writeStarted = "WRITE_STARTED"
    case verifyRequired = "VERIFY_REQUIRED"
    case objectVerified = "OBJECT_VERIFIED"
    case authorized = "AUTHORIZED"
    case journalPending = "JOURNAL_PENDING"
    case journalCommitted = "JOURNAL_COMMITTED"
    case accepted = "ACCEPTED"
    case cleanupPending = "CLEANUP_PENDING"
    case purged = "PURGED"
}

/// Exact signed intent and encrypted bytes for the inactive reservation boundary.
/// This does not add a retry policy, object-provider dispatch or normal runtime.
struct TeamDeliveryReservationRequest: TeamDeviceRequestPayload {
    let intent: TeamDeliverySubmitIntent
    let body: Data
    let jwe: Data

    init(intent: TeamDeliverySubmitIntent, canonicalJWE: String) throws {
        let encoded: Data
        do {
            encoded = try TeamDeliverySubmitIntentCodec.encode(intent)
            _ = try TeamDeliverySubmitIntentCodec.decode(encoded,
                expectedDeliveryId: intent.deliveryId,
                expectedMembershipRevision: intent.membershipRevision,
                expectedAudienceDigest: intent.audienceDigest)
            try intent.verifyCanonicalJWE(canonicalJWE)
        } catch {
            throw TeamDeliveryReservationError.invalidRequest
        }
        let encrypted = Data(canonicalJWE.utf8)
        guard (1...TeamDeliveryJWE.maximumSerializedBytes).contains(encrypted.count),
              encrypted.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            throw TeamDeliveryReservationError.invalidRequest
        }
        self.intent = intent
        body = encoded
        jwe = encrypted
    }
}

/// Typed server result frozen by the authenticated reservation HTTP contract.
struct TeamDeliverySubmissionReservation: Equatable, TeamOnboardingDiagnostic {
    let deliveryId: String
    let state: TeamDeliveryReservationState
    let createdAt: Int64
    let reservationExpiresAt: Int64
    let membershipRevision: Int64
    let audienceDigest: String
    let intentSha256: String
    let jweBytes: Int
    let jweSha256: String
    let objectId: String
    let targets: [TeamFrozenDeliveryTarget]
}

enum TeamDeliveryReservationValidator {
    private static let maximumReservationLifetime: Int64 = 900_000

    static func validate(_ value: TeamDeliverySubmissionReservation,
                         expectedBinding: TeamDeviceRequestWire.Binding,
                         request: TeamDeliveryReservationRequest,
                         expectedAudience: TeamAudience,
                         receivedAt: Int64) throws -> TeamDeliverySubmissionReservation {
        let intent = request.intent
        guard expectedBinding.operation == .deliverySubmit,
              expectedBinding.requestID == intent.deliveryId,
              expectedBinding.teamID == expectedAudience.teamID,
              expectedAudience.membershipRevision == intent.membershipRevision,
              receivedAt >= 0, receivedAt <= TeamAuthWire.maximumSafeTime else {
            throw TeamDeliveryReservationError.bindingMismatch
        }
        let canonicalBody: Data
        do {
            canonicalBody = try TeamDeliverySubmitIntentCodec.encode(intent)
            _ = try TeamDeliverySubmitIntentCodec.decode(request.body,
                expectedDeliveryId: intent.deliveryId,
                expectedMembershipRevision: intent.membershipRevision,
                expectedAudienceDigest: intent.audienceDigest)
        } catch {
            throw TeamDeliveryReservationError.invalidRequest
        }
        guard request.body == canonicalBody,
              let serializedJWE = String(data: request.jwe, encoding: .ascii),
              request.jwe.count == intent.jweBytes,
              TeamDeliverySubmitIntentCodec.sha256(request.jwe) == intent.jweSha256 else {
            throw TeamDeliveryReservationError.invalidRequest
        }

        let orderedAudience = expectedAudience.targets.sorted {
            $0.agreementKeyThumbprint < $1.agreementKeyThumbprint
        }
        guard (1...TeamDeliveryRules.maximumRecipients).contains(orderedAudience.count),
              Set(orderedAudience.map(\.accountID)).count == orderedAudience.count,
              Set(orderedAudience.map(\.deviceID)).count == orderedAudience.count,
              Set(orderedAudience.map(\.enrollmentID)).count == orderedAudience.count,
              Set(orderedAudience.map(\.agreementKeyThumbprint)).count == orderedAudience.count,
              orderedAudience.allSatisfy({ $0.accountID != expectedBinding.accountID }) else {
            throw TeamDeliveryReservationError.bindingMismatch
        }
        let expectedTargets: [TeamFrozenDeliveryTarget]
        do {
            expectedTargets = try orderedAudience.map {
                try TeamFrozenDeliveryTarget(userId: $0.accountID, deviceId: $0.deviceID,
                    enrollmentId: $0.enrollmentID,
                    agreementKeyThumbprint: $0.agreementKeyThumbprint)
            }
            try TeamDeliveryJWE().validate(serializedJWE,
                expectedRecipients: orderedAudience.map {
                    TeamAgreementPublic(keyThumbprint: $0.agreementKeyThumbprint,
                        publicKey: $0.agreementPublicKey)
                })
        } catch {
            throw TeamDeliveryReservationError.invalidRequest
        }

        guard value.deliveryId == intent.deliveryId,
              value.membershipRevision == intent.membershipRevision,
              value.audienceDigest == intent.audienceDigest,
              value.intentSha256 == TeamDeliverySubmitIntentCodec.sha256(request.body),
              value.jweBytes == intent.jweBytes,
              value.jweSha256 == intent.jweSha256,
              value.objectId == intent.jweSha256,
              value.createdAt >= 0,
              value.createdAt <= TeamAuthWire.maximumSafeTime - maximumReservationLifetime,
              value.reservationExpiresAt > value.createdAt,
              value.reservationExpiresAt <= value.createdAt + maximumReservationLifetime,
              value.reservationExpiresAt > receivedAt,
              value.targets == expectedTargets else {
            throw TeamDeliveryReservationError.invalidReservation
        }
        return value
    }
}
