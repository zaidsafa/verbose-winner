import CryptoKit
import Foundation

protocol TeamDeviceRequestPayload: TeamOnboardingDiagnostic {
    var body: Data { get }
}

protocol TeamMembershipRevisionRequestPayload: TeamDeviceRequestPayload {
    var membershipRevision: Int64 { get }
}

struct TeamAudienceRevisionRequest: TeamMembershipRevisionRequestPayload {
    let membershipRevision: Int64
    let body: Data

    init(membershipRevision: Int64) throws {
        guard (0...TeamAuthWire.maximumSafeTime).contains(membershipRevision) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.membershipRevision = membershipRevision
        body = Data("{\"membershipRevision\":\(membershipRevision)}".utf8)
        guard body.count <= 100 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamAgreementEnrollmentRequest: TeamMembershipRevisionRequestPayload {
    let membershipRevision: Int64
    let agreement: TeamAgreementPublic
    let body: Data

    init(membershipRevision: Int64, agreement: TeamAgreementPublic) throws {
        let jwk = agreement.publicKey.jwk
        guard (0...TeamAuthWire.maximumSafeTime).contains(membershipRevision),
              agreement.keyThumbprint == agreement.publicKey.thumbprint,
              Set(jwk.keys) == ["kty", "crv", "x", "y"],
              jwk["kty"] == "EC", jwk["crv"] == "P-256",
              let x = jwk["x"], let y = jwk["y"] else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.membershipRevision = membershipRevision; self.agreement = agreement
        body = Data("{\"agreementKey\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"\(x)\",\"y\":\"\(y)\"},\"membershipRevision\":\(membershipRevision)}".utf8)
        guard body.count <= 256 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamDeliveryFetchRequest: TeamDeviceRequestPayload {
    let deliveryID: String
    let body: Data

    init(deliveryID: String) throws {
        guard TeamAuthWire.identifier(deliveryID) else { throw TeamAuthHTTPError.invalidRequest }
        self.deliveryID = deliveryID
        body = Data("{\"deliveryId\":\"\(deliveryID)\",\"type\":\"pinbook-delivery-fetch-v1\"}".utf8)
        guard body.count <= 256 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamDeliveryListCursor: Equatable, Sendable, TeamOnboardingDiagnostic {
    let afterAcceptedAt: Int64
    let afterDeliveryID: String

    init(afterAcceptedAt: Int64, afterDeliveryID: String) throws {
        guard (0...TeamAuthWire.maximumSafeTime).contains(afterAcceptedAt),
              TeamAuthWire.identifier(afterDeliveryID) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.afterAcceptedAt = afterAcceptedAt
        self.afterDeliveryID = afterDeliveryID
    }
}

struct TeamDeliveryListRequest: TeamDeviceRequestPayload {
    static let type = "pinbook-delivery-list-v1"
    let limit: Int
    let after: TeamDeliveryListCursor?
    let expectedAgreementKeyThumbprint: String
    let body: Data

    init(limit: Int = 50, after: TeamDeliveryListCursor? = nil,
         expectedAgreementKeyThumbprint: String) throws {
        guard (1...50).contains(limit),
              TeamAuthWire.credential(expectedAgreementKeyThumbprint) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.limit = limit
        self.after = after
        self.expectedAgreementKeyThumbprint = expectedAgreementKeyThumbprint
        let acceptedAt = after?.afterAcceptedAt ?? 0
        let deliveryID = after?.afterDeliveryID ?? ""
        body = Data(("{\"afterAcceptedAt\":" + String(acceptedAt) +
            ",\"afterDeliveryId\":\"" + deliveryID + "\",\"limit\":" + String(limit) +
            ",\"type\":\"" + Self.type + "\"}").utf8)
        guard body.count <= 512 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

/// Frozen ACK request and local target binding for the inactive authenticated relay.
struct TeamDeliveryACKRequest: TeamDeviceRequestPayload {
    static let type = "pinbook-delivery-ack-v1"
    let deliveryID: String
    let jweSHA256: String
    let accountID: String
    let teamID: String
    let deviceID: String
    let enrollmentID: String
    let body: Data

    init(receipt: PendingTeamReceipt) throws {
        guard TeamAuthWire.identifier(receipt.accountId), TeamAuthWire.identifier(receipt.teamId),
              TeamAuthWire.identifier(receipt.deliveryId), TeamAuthWire.identifier(receipt.deviceId),
              TeamAuthWire.identifier(receipt.enrollmentId),
              receipt.jweSHA256.utf8.count == 64,
              receipt.jweSHA256.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else { throw TeamAuthHTTPError.invalidRequest }
        deliveryID = receipt.deliveryId
        jweSHA256 = receipt.jweSHA256
        accountID = receipt.accountId
        teamID = receipt.teamId
        deviceID = receipt.deviceId
        enrollmentID = receipt.enrollmentId
        body = Data(("{\"deliveryId\":\"" + receipt.deliveryId +
            "\",\"jweSha256\":\"" + receipt.jweSHA256 +
            "\",\"type\":\"" + Self.type + "\"}").utf8)
        guard body.count <= 256 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamAudienceTarget: TeamOnboardingDiagnostic {
    let accountID: String
    let deviceID: String
    let enrollmentID: String
    let keyThumbprint: String
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
    let agreementKeyThumbprint: String
    let agreementPublicKey: TeamDeviceEnrollmentWire.PublicKey
}

struct TeamAudience: TeamOnboardingDiagnostic {
    let teamID: String
    let membershipRevision: Int64
    let targets: [TeamAudienceTarget]
}

struct TeamAgreementRegistration: TeamOnboardingDiagnostic {
    let teamID: String
    let membershipRevision: Int64
    let enrollmentID: String
    let agreementKeyThumbprint: String
    let agreementPublicKey: TeamDeviceEnrollmentWire.PublicKey
}

struct TeamDeliveryFetchResult: TeamOnboardingDiagnostic {
    let deliveryID: String
    let acceptedAt: Int64
    let expiresAt: Int64
    let jweBytes: Int
    let jweSHA256: String
    let audienceDigest: String
    let agreementKeyThumbprint: String
    let jwe: Data
}

struct TeamPendingDelivery: Equatable, TeamOnboardingDiagnostic {
    let deliveryID: String
    let acceptedAt: Int64
    let expiresAt: Int64
    let jweBytes: Int
    let jweSHA256: String
    let senderAccountID: String
    let senderDeviceID: String
    let senderEnrollmentID: String
    let audienceDigest: String
    let agreementKeyThumbprint: String
}

struct TeamPendingDeliveryPage: Equatable, TeamOnboardingDiagnostic {
    let deliveries: [TeamPendingDelivery]
    let hasMore: Bool
    let nextCursor: TeamDeliveryListCursor?
}

struct TeamDeliveryACKResult: Equatable, TeamOnboardingDiagnostic {
    let deliveryID: String
    let settledAt: Int64
    let expiresAt: Int64
    let jweSHA256: String
    let purgeEligible: Bool
}

struct TeamDeliveryStatusRequest: TeamDeviceRequestPayload {
    static let type = "pinbook-delivery-status-v1"
    let deliveryID: String
    let expectedJWESHA256: String
    let body: Data

    init(deliveryID: String, expectedJWESHA256: String) throws {
        guard TeamAuthWire.identifier(deliveryID),
              TeamDeviceRequestHTTPWire.validHexDigest(expectedJWESHA256) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.deliveryID = deliveryID
        self.expectedJWESHA256 = expectedJWESHA256
        body = Data(("{\"deliveryId\":\"" + deliveryID +
            "\",\"type\":\"" + Self.type + "\"}").utf8)
        guard body.count <= 256 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamDeliverySubmissionStatus: Equatable, TeamOnboardingDiagnostic {
    let deliveryID: String
    let state: TeamDeliveryReservationState
    let createdAt: Int64
    let reservationExpiresAt: Int64
    let acceptedAt: Int64?
    let expiresAt: Int64?
    let jweSHA256: String
}

struct TeamPreparedDeviceRequestChallenge: TeamOnboardingDiagnostic {
    let challengeID: String
    let expiresAt: Int64
    fileprivate let wire: Data

    init<Request: TeamDeviceRequestPayload>(validating wire: Data, expected: TeamDeviceRequestWire.Binding,
         publicKey: TeamDeviceEnrollmentWire.PublicKey,
         request: Request, now: Int64) throws {
        _ = try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now)
        let object = try TeamStrictJSON.object(wire)
        challengeID = try TeamAuthWire.string(object, "challengeId", secret: true)
        expiresAt = try TeamAuthWire.time(object, "expiresAt")
        self.wire = wire
    }

    func message<Request: TeamDeviceRequestPayload>(expected: TeamDeviceRequestWire.Binding,
                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                 request: Request, now: Int64) throws -> Data {
        try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now)
    }
}

struct TeamPreparedAgreementRequestChallenge: TeamOnboardingDiagnostic {
    let request: TeamPreparedDeviceRequestChallenge
    let server: TeamAgreementPublic
    fileprivate let wire: Data
    var challengeID: String { request.challengeID }
    var expiresAt: Int64 { request.expiresAt }

    init(validating wire: Data, expected: TeamDeviceRequestWire.Binding,
         publicKey: TeamDeviceEnrollmentWire.PublicKey,
         request: TeamAgreementEnrollmentRequest, now: Int64) throws {
        let extra: Set<String> = ["agreementServerKeyThumbprint", "agreementServerPublicKey"]
        _ = try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now, additionalChallengeKeys: extra)
        let object = try TeamAuthWire.object(wire, keys: ["audience", "authorityEpoch", "accountId", "sessionId",
            "deviceId", "enrollmentId", "keyThumbprint", "operation", "teamId", "requestId", "bodySha256",
            "challengeId", "nonce", "expiresAt", "agreementServerKeyThumbprint", "agreementServerPublicKey"])
        guard let jwk = object["agreementServerPublicKey"] as? [String: String] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let key: TeamDeviceEnrollmentWire.PublicKey
        do { key = try TeamDeviceEnrollmentWire.publicKey(jwk) }
        catch { throw TeamAuthHTTPError.invalidResponse }
        let thumbprint = try TeamAuthWire.string(object, "agreementServerKeyThumbprint", secret: true)
        guard key.thumbprint == thumbprint, thumbprint != request.agreement.keyThumbprint else {
            throw TeamAuthHTTPError.invalidResponse
        }
        var base = object
        base.removeValue(forKey: "agreementServerKeyThumbprint")
        base.removeValue(forKey: "agreementServerPublicKey")
        let baseWire = try JSONSerialization.data(withJSONObject: base, options: [.withoutEscapingSlashes])
        self.request = try TeamPreparedDeviceRequestChallenge(validating: baseWire,
            expected: expected, publicKey: publicKey, request: request, now: now)
        server = .init(keyThumbprint: thumbprint, publicKey: key)
        self.wire = wire
    }

    func message(expected: TeamDeviceRequestWire.Binding,
                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                 request: TeamAgreementEnrollmentRequest, now: Int64) throws -> Data {
        try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now,
            additionalChallengeKeys: ["agreementServerKeyThumbprint", "agreementServerPublicKey"])
    }
}

private enum TeamDeviceRequestHTTPWire {
    private static let deliveryLifetimeMilliseconds: Int64 = 2_592_000_000

    static func audience(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                         request: TeamAudienceRevisionRequest) throws -> TeamAudience {
        let object = try TeamAuthWire.object(data, keys: ["teamId", "membershipRevision", "targets"])
        let teamID = try TeamAuthWire.string(object, "teamId")
        let revision = try TeamAuthWire.time(object, "membershipRevision")
        guard teamID == expected.teamID, revision == request.membershipRevision,
              let rows = object["targets"] as? [[String: Any]], rows.count <= 9 else {
            throw TeamAuthHTTPError.invalidResponse
        }
        var accounts = Set<String>(), devices = Set<String>(), enrollments = Set<String>()
        let targets = try rows.map { row in
            guard Set(row.keys) == ["accountId", "deviceId", "enrollmentId", "keyThumbprint", "publicKey",
                "agreementKeyThumbprint", "agreementPublicKey"],
                  let jwk = row["publicKey"] as? [String: String],
                  let agreementJWK = row["agreementPublicKey"] as? [String: String] else {
                throw TeamAuthHTTPError.invalidResponse
            }
            let accountID = try TeamAuthWire.string(row, "accountId")
            let deviceID = try TeamAuthWire.string(row, "deviceId")
            let enrollmentID = try TeamAuthWire.string(row, "enrollmentId")
            let thumbprint = try TeamAuthWire.string(row, "keyThumbprint", secret: true)
            let agreementThumbprint = try TeamAuthWire.string(row, "agreementKeyThumbprint", secret: true)
            let key: TeamDeviceEnrollmentWire.PublicKey, agreementKey: TeamDeviceEnrollmentWire.PublicKey
            do {
                key = try TeamDeviceEnrollmentWire.publicKey(jwk)
                agreementKey = try TeamDeviceEnrollmentWire.publicKey(agreementJWK)
            }
            catch { throw TeamAuthHTTPError.invalidResponse }
            guard accountID != expected.accountID, key.thumbprint == thumbprint,
                  agreementKey.thumbprint == agreementThumbprint,
                  agreementThumbprint != thumbprint,
                  accounts.insert(accountID).inserted, devices.insert(deviceID).inserted,
                  enrollments.insert(enrollmentID).inserted else { throw TeamAuthHTTPError.invalidResponse }
            return TeamAudienceTarget(accountID: accountID, deviceID: deviceID,
                enrollmentID: enrollmentID, keyThumbprint: thumbprint, publicKey: key,
                agreementKeyThumbprint: agreementThumbprint, agreementPublicKey: agreementKey)
        }
        return TeamAudience(teamID: teamID, membershipRevision: revision, targets: targets)
    }

    static func agreement(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                          request: TeamAgreementEnrollmentRequest) throws -> TeamAgreementRegistration {
        let object = try TeamAuthWire.object(data, keys: ["teamId", "membershipRevision", "enrollmentId",
            "agreementKeyThumbprint", "agreementPublicKey"])
        guard let jwk = object["agreementPublicKey"] as? [String: String] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let key: TeamDeviceEnrollmentWire.PublicKey
        do { key = try TeamDeviceEnrollmentWire.publicKey(jwk) }
        catch { throw TeamAuthHTTPError.invalidResponse }
        let result = try TeamAgreementRegistration(teamID: TeamAuthWire.string(object, "teamId"),
            membershipRevision: TeamAuthWire.time(object, "membershipRevision"),
            enrollmentID: TeamAuthWire.string(object, "enrollmentId"),
            agreementKeyThumbprint: TeamAuthWire.string(object, "agreementKeyThumbprint", secret: true),
            agreementPublicKey: key)
        guard result.teamID == expected.teamID,
              result.membershipRevision == request.membershipRevision,
              result.enrollmentID == expected.enrollmentID,
              result.agreementKeyThumbprint == request.agreement.keyThumbprint,
              result.agreementPublicKey.thumbprint == result.agreementKeyThumbprint,
              result.agreementPublicKey.jwk == request.agreement.publicKey.jwk else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return result
    }

    static func delivery(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                         request: TeamDeliveryFetchRequest,
                         pending: TeamPendingDelivery) throws -> TeamDeliveryFetchResult {
        let object = try TeamStrictJSON.object(data,
            maximumBytes: TeamAuthWire.maximumDeliveryFetchResponseBytes)
        guard Set(object.keys) == ["deliveryId", "acceptedAt", "expiresAt", "jweBytes", "jweSha256",
                                    "audienceDigest", "agreementKeyThumbprint", "jwe"] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let deliveryID = try TeamAuthWire.string(object, "deliveryId")
        let acceptedAt = try TeamAuthWire.time(object, "acceptedAt")
        let expiresAt = try TeamAuthWire.time(object, "expiresAt")
        let count = try TeamAuthWire.time(object, "jweBytes")
        let audienceDigest = try TeamAuthWire.string(object, "audienceDigest", secret: true)
        let agreementKeyThumbprint = try TeamAuthWire.string(object, "agreementKeyThumbprint", secret: true)
        guard deliveryID == request.deliveryID, deliveryID == expected.requestID,
              deliveryID == pending.deliveryID,
              acceptedAt <= TeamAuthWire.maximumSafeTime - deliveryLifetimeMilliseconds,
              expiresAt == acceptedAt + deliveryLifetimeMilliseconds,
              (1...100_000).contains(count), let encoded = object["jwe"] as? String,
              let digest = object["jweSha256"] as? String,
              digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let jwe = decode(encoded, maximumBytes: 100_000), jwe.count == Int(count),
              sha256(jwe) == digest,
              acceptedAt == pending.acceptedAt, expiresAt == pending.expiresAt,
              Int(count) == pending.jweBytes, digest == pending.jweSHA256,
              audienceDigest == pending.audienceDigest,
              agreementKeyThumbprint == pending.agreementKeyThumbprint else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return .init(deliveryID: deliveryID, acceptedAt: acceptedAt, expiresAt: expiresAt,
            jweBytes: Int(count), jweSHA256: digest, audienceDigest: audienceDigest,
            agreementKeyThumbprint: agreementKeyThumbprint, jwe: jwe)
    }

    static func pending(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                        request: TeamDeliveryListRequest, receivedAt: Int64) throws -> TeamPendingDeliveryPage {
        let object = try TeamAuthWire.object(data, keys: ["deliveries", "hasMore", "nextCursor"])
        guard expected.operation == .deliveryList,
              let rows = object["deliveries"] as? [[String: Any]], rows.count <= request.limit else {
            throw TeamAuthHTTPError.invalidResponse
        }
        var seen = Set<String>()
        var previous = request.after.map { ($0.afterAcceptedAt, $0.afterDeliveryID) }
        let deliveries: [TeamPendingDelivery] = try rows.map { row in
            guard Set(row.keys) == ["deliveryId", "acceptedAt", "expiresAt", "jweBytes", "jweSha256",
                "senderAccountId", "senderDeviceId", "senderEnrollmentId", "audienceDigest",
                "agreementKeyThumbprint"] else { throw TeamAuthHTTPError.invalidResponse }
            let deliveryID = try TeamAuthWire.string(row, "deliveryId")
            let acceptedAt = try TeamAuthWire.time(row, "acceptedAt")
            let expiresAt = try TeamAuthWire.time(row, "expiresAt")
            let count = try TeamAuthWire.time(row, "jweBytes")
            let digest = try requiredHexDigest(row, "jweSha256")
            let result = try TeamPendingDelivery(deliveryID: deliveryID, acceptedAt: acceptedAt,
                expiresAt: expiresAt, jweBytes: Int(count), jweSHA256: digest,
                senderAccountID: TeamAuthWire.string(row, "senderAccountId"),
                senderDeviceID: TeamAuthWire.string(row, "senderDeviceId"),
                senderEnrollmentID: TeamAuthWire.string(row, "senderEnrollmentId"),
                audienceDigest: TeamAuthWire.string(row, "audienceDigest", secret: true),
                agreementKeyThumbprint: TeamAuthWire.string(row, "agreementKeyThumbprint", secret: true))
            let key = (acceptedAt, deliveryID)
            guard seen.insert(deliveryID).inserted,
                  acceptedAt <= TeamAuthWire.maximumSafeTime - deliveryLifetimeMilliseconds,
                  expiresAt == acceptedAt + deliveryLifetimeMilliseconds,
                  expiresAt > receivedAt, (1...100_000).contains(count),
                  result.agreementKeyThumbprint == request.expectedAgreementKeyThumbprint,
                  previous.map({ key.0 > $0.0 || (key.0 == $0.0 && key.1 > $0.1) }) ?? true else {
                throw TeamAuthHTTPError.invalidResponse
            }
            previous = key
            return result
        }
        let hasMore = try TeamAuthWire.boolean(object, "hasMore")
        let next: TeamDeliveryListCursor?
        if object["nextCursor"] is NSNull { next = nil }
        else {
            guard let cursor = object["nextCursor"] as? [String: Any],
                  Set(cursor.keys) == ["afterAcceptedAt", "afterDeliveryId"] else {
                throw TeamAuthHTTPError.invalidResponse
            }
            next = try .init(afterAcceptedAt: TeamAuthWire.time(cursor, "afterAcceptedAt"),
                afterDeliveryID: TeamAuthWire.string(cursor, "afterDeliveryId"))
        }
        guard hasMore == (next != nil), !hasMore || !deliveries.isEmpty else {
            throw TeamAuthHTTPError.invalidResponse
        }
        if hasMore {
            guard let last = deliveries.last, let next,
                  next.afterAcceptedAt == last.acceptedAt,
                  next.afterDeliveryID == last.deliveryID else {
                throw TeamAuthHTTPError.invalidResponse
            }
        }
        return .init(deliveries: deliveries, hasMore: hasMore, nextCursor: next)
    }

    static func ack(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                    request: TeamDeliveryACKRequest) throws -> TeamDeliveryACKResult {
        let object = try TeamAuthWire.object(data, keys: ["deliveryId", "state", "settledAt",
            "expiresAt", "jweSha256", "purgeEligible"])
        let deliveryID = try TeamAuthWire.string(object, "deliveryId")
        let settledAt = try TeamAuthWire.time(object, "settledAt")
        let expiresAt = try TeamAuthWire.time(object, "expiresAt")
        let digest = try requiredHexDigest(object, "jweSha256")
        guard object["state"] as? String == "ACKED", deliveryID == request.deliveryID,
              deliveryID == expected.requestID, digest == request.jweSHA256,
              settledAt <= expiresAt else { throw TeamAuthHTTPError.invalidResponse }
        return .init(deliveryID: deliveryID, settledAt: settledAt, expiresAt: expiresAt,
            jweSHA256: digest, purgeEligible: try TeamAuthWire.boolean(object, "purgeEligible"))
    }

    static func status(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                       request: TeamDeliveryStatusRequest) throws -> TeamDeliverySubmissionStatus {
        let object = try TeamAuthWire.object(data, keys: ["deliveryId", "state", "createdAt",
            "reservationExpiresAt", "acceptedAt", "expiresAt", "jweSha256"])
        let deliveryID = try TeamAuthWire.string(object, "deliveryId")
        guard let rawState = object["state"] as? String,
              let state = TeamDeliveryReservationState(rawValue: rawState) else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let createdAt = try TeamAuthWire.time(object, "createdAt")
        let reservationExpiresAt = try TeamAuthWire.time(object, "reservationExpiresAt")
        let digest = try requiredHexDigest(object, "jweSha256")
        let acceptedAt = try optionalTime(object, "acceptedAt")
        let expiresAt = try optionalTime(object, "expiresAt")
        let acceptedIsSafe = acceptedAt.map({
            $0 <= TeamAuthWire.maximumSafeTime - deliveryLifetimeMilliseconds
        }) ?? true
        let acceptedLifetimeMatches = acceptedAt.map({
            $0 + deliveryLifetimeMilliseconds == expiresAt
        }) ?? true
        guard deliveryID == request.deliveryID, deliveryID == expected.requestID,
              digest == request.expectedJWESHA256,
              reservationExpiresAt > createdAt,
              reservationExpiresAt <= createdAt + 900_000,
              (acceptedAt == nil) == (expiresAt == nil),
              acceptedIsSafe, acceptedLifetimeMatches else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return .init(deliveryID: deliveryID, state: state, createdAt: createdAt,
            reservationExpiresAt: reservationExpiresAt, acceptedAt: acceptedAt,
            expiresAt: expiresAt, jweSHA256: digest)
    }

    static func reservation(_ data: Data) throws -> TeamDeliverySubmissionReservation {
        let object = try TeamAuthWire.object(data, keys: ["deliveryId", "state", "createdAt",
            "reservationExpiresAt", "membershipRevision", "audienceDigest", "intentSha256",
            "jweBytes", "jweSha256", "objectId", "targets"])
        guard let rawState = object["state"] as? String,
              let state = TeamDeliveryReservationState(rawValue: rawState),
              let intentDigest = object["intentSha256"] as? String,
              let jweDigest = object["jweSha256"] as? String,
              let objectID = object["objectId"] as? String,
              validHexDigest(intentDigest), validHexDigest(jweDigest), validHexDigest(objectID),
              let rows = object["targets"] as? [[String: Any]],
              (1...TeamDeliveryRules.maximumRecipients).contains(rows.count) else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let count = try TeamAuthWire.time(object, "jweBytes")
        guard (1...Int64(TeamDeliveryJWE.maximumSerializedBytes)).contains(count) else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let targets: [TeamFrozenDeliveryTarget]
        do {
            targets = try rows.map { row in
                guard Set(row.keys) == ["userId", "deviceId", "enrollmentId", "agreementKeyThumbprint"] else {
                    throw TeamAuthHTTPError.invalidResponse
                }
                return try TeamFrozenDeliveryTarget(userId: TeamAuthWire.string(row, "userId"),
                    deviceId: TeamAuthWire.string(row, "deviceId"),
                    enrollmentId: TeamAuthWire.string(row, "enrollmentId"),
                    agreementKeyThumbprint: TeamAuthWire.string(row, "agreementKeyThumbprint", secret: true))
            }
        } catch {
            throw TeamAuthHTTPError.invalidResponse
        }
        return try .init(deliveryId: TeamAuthWire.string(object, "deliveryId"), state: state,
            createdAt: TeamAuthWire.time(object, "createdAt"),
            reservationExpiresAt: TeamAuthWire.time(object, "reservationExpiresAt"),
            membershipRevision: TeamAuthWire.time(object, "membershipRevision"),
            audienceDigest: TeamAuthWire.string(object, "audienceDigest", secret: true),
            intentSha256: intentDigest, jweBytes: Int(count), jweSha256: jweDigest,
            objectId: objectID, targets: targets)
    }

    private static func decode(_ value: String, maximumBytes: Int) -> Data? {
        guard !value.isEmpty,
              value.utf8.count <= (maximumBytes * 4 + 2) / 3,
              value.utf8.allSatisfy(TeamAuthWire.urlByte) else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let result = Data(base64Encoded: padded), result.count <= maximumBytes,
              TeamDeviceEnrollmentWire.encode(result) == value else { return nil }
        return result
    }

    private static func sha256(_ data: Data) -> String {
        let alphabet = Array("0123456789abcdef".utf8)
        var result = [UInt8](); result.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            result.append(alphabet[Int(byte >> 4)])
            result.append(alphabet[Int(byte & 15)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    static func validHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func requiredHexDigest(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String, validHexDigest(value) else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return value
    }

    private static func optionalTime(_ object: [String: Any], _ key: String) throws -> Int64? {
        if object[key] is NSNull { return nil }
        return try TeamAuthWire.time(object, key)
    }
}

extension TeamAuthHTTPClient {
    func deliveryListChallenge(expected: TeamDeviceRequestWire.Binding,
                               publicKey: TeamDeviceEnrollmentWire.PublicKey,
                               request: TeamDeliveryListRequest,
                               ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        try await deliveryRelayChallenge(expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryList, ticket: ticket)
    }

    func listPendingDeliveries(challenge: TeamPreparedDeviceRequestChallenge,
                               signature: Data, expected: TeamDeviceRequestWire.Binding,
                               publicKey: TeamDeviceEnrollmentWire.PublicKey,
                               request: TeamDeliveryListRequest,
                               ticket: TeamAccountAccessTicket) async throws -> TeamPendingDeliveryPage {
        let reply = try await executeDeliveryRelay(.deliveryPending, challenge: challenge,
            signature: signature, expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryList, ticket: ticket)
        return try TeamDeviceRequestHTTPWire.pending(reply.data, expected: expected,
            request: request, receivedAt: reply.receivedAt)
    }

    func deliveryACKChallenge(expected: TeamDeviceRequestWire.Binding,
                              publicKey: TeamDeviceEnrollmentWire.PublicKey,
                              request: TeamDeliveryACKRequest,
                              ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsACKBinding(expected, request: request) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        return try await deliveryRelayChallenge(expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryACK, ticket: ticket)
    }

    func acknowledgeDelivery(challenge: TeamPreparedDeviceRequestChallenge,
                             signature: Data, expected: TeamDeviceRequestWire.Binding,
                             publicKey: TeamDeviceEnrollmentWire.PublicKey,
                             request: TeamDeliveryACKRequest,
                             ticket: TeamAccountAccessTicket) async throws -> TeamDeliveryACKResult {
        guard acceptsACKBinding(expected, request: request) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await executeDeliveryRelay(.deliveryACK, challenge: challenge,
            signature: signature, expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryACK, ticket: ticket)
        return try TeamDeviceRequestHTTPWire.ack(reply.data, expected: expected, request: request)
    }

    func deliveryStatusChallenge(expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamDeliveryStatusRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard expected.requestID == request.deliveryID else { throw TeamAuthHTTPError.invalidRequest }
        return try await deliveryRelayChallenge(expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryStatus, ticket: ticket)
    }

    func deliveryStatus(challenge: TeamPreparedDeviceRequestChallenge,
                        signature: Data, expected: TeamDeviceRequestWire.Binding,
                        publicKey: TeamDeviceEnrollmentWire.PublicKey,
                        request: TeamDeliveryStatusRequest,
                        ticket: TeamAccountAccessTicket) async throws -> TeamDeliverySubmissionStatus {
        guard expected.requestID == request.deliveryID else { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await executeDeliveryRelay(.deliveryStatus, challenge: challenge,
            signature: signature, expected: expected, publicKey: publicKey,
            request: request, operation: .deliveryStatus, ticket: ticket)
        return try TeamDeviceRequestHTTPWire.status(reply.data, expected: expected, request: request)
    }

    func deviceRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                request: TeamAudienceRevisionRequest,
                                ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .teamAudience else { throw TeamAuthHTTPError.invalidRequest }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deviceRequestChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func executeDeviceRequest(challenge: TeamPreparedDeviceRequestChallenge,
                              signature: Data, expected: TeamDeviceRequestWire.Binding,
                              publicKey: TeamDeviceEnrollmentWire.PublicKey,
                              request: TeamAudienceRevisionRequest,
                              ticket: TeamAccountAccessTicket) async throws -> TeamAudience {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .teamAudience, signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do { message = try challenge.message(expected: expected, publicKey: publicKey,
            request: request, now: onboardingTime()) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await onboarding(.deviceRequestExecute, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body)
        ], ticket: ticket)
        return try TeamDeviceRequestHTTPWire.audience(reply.data, expected: expected, request: request)
    }

    func agreementRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                   publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                   request: TeamAgreementEnrollmentRequest,
                                   ticket: TeamAccountAccessTicket) async throws -> TeamPreparedAgreementRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .agreementEnroll else { throw TeamAuthHTTPError.invalidRequest }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.agreementChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest],
            "agreementPublicKey": request.agreement.publicKey.jwk
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func executeAgreementRequest(challenge: TeamPreparedAgreementRequestChallenge,
                                 signature: Data, confirmation: Data,
                                 expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamAgreementEnrollmentRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamAgreementRegistration {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .agreementEnroll, signature.count == 64, confirmation.count == 32,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do { message = try challenge.message(expected: expected, publicKey: publicKey,
            request: request, now: onboardingTime()) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await onboarding(.agreementExecute, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body),
            "confirmation": TeamDeviceEnrollmentWire.encode(confirmation)
        ], ticket: ticket)
        return try TeamDeviceRequestHTTPWire.agreement(reply.data, expected: expected, request: request)
    }

    func deliveryFetchChallenge(expected: TeamDeviceRequestWire.Binding,
                                publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                request: TeamDeliveryFetchRequest,
                                ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .deliveryFetch, expected.requestID == request.deliveryID else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deliveryChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func fetchDelivery(challenge: TeamPreparedDeviceRequestChallenge,
                       signature: Data, expected: TeamDeviceRequestWire.Binding,
                       publicKey: TeamDeviceEnrollmentWire.PublicKey,
                       request: TeamDeliveryFetchRequest,
                       pending: TeamPendingDelivery,
                       ticket: TeamAccountAccessTicket) async throws -> TeamDeliveryFetchResult {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .deliveryFetch, expected.requestID == request.deliveryID,
              signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do { message = try challenge.message(expected: expected, publicKey: publicKey,
            request: request, now: onboardingTime()) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await onboarding(.deliveryFetch, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body)
        ], ticket: ticket)
        return try TeamDeviceRequestHTTPWire.delivery(reply.data, expected: expected,
            request: request, pending: pending)
    }

    func deliverySubmitChallenge(expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamDeliveryReservationRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .deliverySubmit,
              expected.requestID == request.intent.deliveryId else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deliverySubmitChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func reserveDelivery(challenge: TeamPreparedDeviceRequestChallenge,
                         signature: Data, expected: TeamDeviceRequestWire.Binding,
                         publicKey: TeamDeviceEnrollmentWire.PublicKey,
                         request: TeamDeliveryReservationRequest,
                         expectedAudience: TeamAudience,
                         ticket: TeamAccountAccessTicket) async throws -> TeamDeliverySubmissionReservation {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .deliverySubmit,
              expected.requestID == request.intent.deliveryId,
              signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do {
            message = try challenge.message(expected: expected, publicKey: publicKey,
                request: request, now: onboardingTime())
        } catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await onboarding(.deliverySubmitReserve, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body),
            "jwe": TeamDeviceEnrollmentWire.encode(request.jwe)
        ], ticket: ticket)
        do {
            return try TeamDeliveryReservationValidator.validate(
                TeamDeviceRequestHTTPWire.reservation(reply.data),
                expectedBinding: expected, request: request,
                expectedAudience: expectedAudience, receivedAt: reply.receivedAt)
        } catch {
            throw TeamAuthHTTPError.invalidResponse
        }
    }

    private func acceptsDeviceRequestBinding(_ binding: TeamDeviceRequestWire.Binding,
                                             key: TeamDeviceEnrollmentWire.PublicKey,
                                             ticket: TeamAccountAccessTicket) -> Bool {
        let device = TeamDeviceEnrollmentWire.Binding(audience: binding.audience,
            authorityEpoch: binding.authorityEpoch, accountID: binding.accountID,
            sessionID: binding.sessionID, deviceID: binding.deviceID,
            keyThumbprint: binding.keyThumbprint, accessExpiresAt: binding.accessExpiresAt)
        return acceptsDeviceBinding(device, ticket: ticket) &&
            TeamAuthWire.identifier(binding.enrollmentID) && TeamAuthWire.identifier(binding.teamID) &&
            TeamAuthWire.identifier(binding.requestID) && key.thumbprint == binding.keyThumbprint
    }

    private func acceptsACKBinding(_ binding: TeamDeviceRequestWire.Binding,
                                   request: TeamDeliveryACKRequest) -> Bool {
        binding.operation == .deliveryACK && binding.requestID == request.deliveryID &&
            binding.accountID == request.accountID && binding.teamID == request.teamID &&
            binding.deviceID == request.deviceID && binding.enrollmentID == request.enrollmentID
    }

    private func deliveryRelayChallenge<Request: TeamDeviceRequestPayload>(
        expected: TeamDeviceRequestWire.Binding,
        publicKey: TeamDeviceEnrollmentWire.PublicKey,
        request: Request, operation: TeamDeviceRequestWire.Operation,
        ticket: TeamAccountAccessTicket
    ) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == operation,
              [.deliveryList, .deliveryACK, .deliveryStatus].contains(operation) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deliveryChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    private func executeDeliveryRelay<Request: TeamDeviceRequestPayload>(
        _ route: TeamOnboardingRoute, challenge: TeamPreparedDeviceRequestChallenge,
        signature: Data, expected: TeamDeviceRequestWire.Binding,
        publicKey: TeamDeviceEnrollmentWire.PublicKey, request: Request,
        operation: TeamDeviceRequestWire.Operation,
        ticket: TeamAccountAccessTicket
    ) async throws -> (data: Data, receivedAt: Int64) {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == operation,
              [.deliveryList, .deliveryACK, .deliveryStatus].contains(operation),
              signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do {
            message = try challenge.message(expected: expected, publicKey: publicKey,
                request: request, now: onboardingTime())
        } catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        return try await onboarding(route, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body)
        ], ticket: ticket)
    }
}
