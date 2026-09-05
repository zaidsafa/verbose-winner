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

/// Frozen ACK request body only. No HTTP route is activated until the server
/// publishes the complete authenticated response and idempotency contract.
struct TeamDeliveryACKRequest: TeamDeviceRequestPayload {
    static let type = "pinbook-delivery-ack-v1"
    let deliveryID: String
    let jweSHA256: String
    let body: Data

    init(receipt: PendingTeamReceipt) throws {
        guard TeamAuthWire.identifier(receipt.deliveryId),
              receipt.jweSHA256.utf8.count == 64,
              receipt.jweSHA256.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else { throw TeamAuthHTTPError.invalidRequest }
        deliveryID = receipt.deliveryId
        jweSHA256 = receipt.jweSHA256
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
    let jwe: Data
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
                         request: TeamDeliveryFetchRequest) throws -> TeamDeliveryFetchResult {
        let object = try TeamStrictJSON.object(data,
            maximumBytes: TeamAuthWire.maximumDeliveryFetchResponseBytes)
        guard Set(object.keys) == ["deliveryId", "acceptedAt", "expiresAt", "jweBytes", "jweSha256", "jwe"] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let deliveryID = try TeamAuthWire.string(object, "deliveryId")
        let acceptedAt = try TeamAuthWire.time(object, "acceptedAt")
        let expiresAt = try TeamAuthWire.time(object, "expiresAt")
        let count = try TeamAuthWire.time(object, "jweBytes")
        guard deliveryID == request.deliveryID, deliveryID == expected.requestID,
              acceptedAt <= TeamAuthWire.maximumSafeTime - deliveryLifetimeMilliseconds,
              expiresAt == acceptedAt + deliveryLifetimeMilliseconds,
              (1...100_000).contains(count), let encoded = object["jwe"] as? String,
              let digest = object["jweSha256"] as? String,
              digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let jwe = decode(encoded, maximumBytes: 100_000), jwe.count == Int(count),
              sha256(jwe) == digest else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return .init(deliveryID: deliveryID, acceptedAt: acceptedAt, expiresAt: expiresAt,
            jweBytes: Int(count), jweSHA256: digest, jwe: jwe)
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

    private static func validHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

extension TeamAuthHTTPClient {
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
        return try TeamDeviceRequestHTTPWire.delivery(reply.data, expected: expected, request: request)
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
}
