import CryptoKit
import Foundation

enum TeamDeviceRequestWireError: Error, Equatable {
    case invalidChallenge, bindingMismatch, invalidBody
}

/// Inactive request-proof wire primitive. It only validates local bindings and
/// constructs canonical bytes; it performs no signing, custody mutation or I/O.
enum TeamDeviceRequestWire {
    static let maximumBodyBytes = 64 * 1024

    enum Operation: String, CaseIterable, Sendable {
        case agreementEnroll = "agreement-enroll"
        case teamAudience = "team-audience"
        case deliverySubmit = "delivery-submit"
        case deliveryList = "delivery-list"
        case deliveryFetch = "delivery-fetch"
        case deliveryACK = "delivery-ack"
        case deliveryStatus = "delivery-status"
    }

    struct Binding: TeamOnboardingDiagnostic {
        let audience: String
        let authorityEpoch: String
        let accountID: String
        let sessionID: String
        let deviceID: String
        let enrollmentID: String
        let keyThumbprint: String
        let operation: Operation
        let teamID: String
        let requestID: String
        let accessExpiresAt: Int64
    }

    static func bodySHA256(_ body: Data) throws -> String {
        guard (1...maximumBodyBytes).contains(body.count) else {
            throw TeamDeviceRequestWireError.invalidBody
        }
        let alphabet = Array("0123456789abcdef".utf8)
        var result = [UInt8](); result.reserveCapacity(64)
        for byte in SHA256.hash(data: body) {
            result.append(alphabet[Int(byte >> 4)]); result.append(alphabet[Int(byte & 15)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// Rebuilds the exact domain-separated UTF-8 message after checking every
    /// locally selected account, device and request binding plus the actual body.
    static func message(challenge data: Data, expected: Binding,
                        publicKey: TeamDeviceEnrollmentWire.PublicKey,
                        body: Data, now: Int64,
                        additionalChallengeKeys: Set<String> = []) throws -> Data {
        let fields: [String: Any]
        do {
            let baseKeys: Set<String> = ["audience", "authorityEpoch", "accountId", "sessionId",
                "deviceId", "enrollmentId", "keyThumbprint", "operation", "teamId", "requestId", "bodySha256",
                "challengeId", "nonce", "expiresAt"]
            fields = try TeamAuthWire.object(data, keys: baseKeys.union(additionalChallengeKeys))
        } catch { throw TeamDeviceRequestWireError.invalidChallenge }

        guard TeamDeviceEnrollmentWire.canonicalAudience(expected.audience),
              TeamAuthWire.identifier(expected.authorityEpoch), TeamAuthWire.identifier(expected.accountID),
              TeamAuthWire.identifier(expected.sessionID), TeamAuthWire.identifier(expected.deviceID),
              TeamAuthWire.identifier(expected.enrollmentID), TeamAuthWire.identifier(expected.teamID),
              TeamAuthWire.identifier(expected.requestID), TeamAuthWire.credential(expected.keyThumbprint),
              publicKey.thumbprint == expected.keyThumbprint,
              fields["audience"] as? String == expected.audience,
              fields["authorityEpoch"] as? String == expected.authorityEpoch,
              fields["accountId"] as? String == expected.accountID,
              fields["sessionId"] as? String == expected.sessionID,
              fields["deviceId"] as? String == expected.deviceID,
              fields["enrollmentId"] as? String == expected.enrollmentID,
              fields["keyThumbprint"] as? String == expected.keyThumbprint,
              fields["operation"] as? String == expected.operation.rawValue,
              fields["teamId"] as? String == expected.teamID,
              fields["requestId"] as? String == expected.requestID
        else { throw TeamDeviceRequestWireError.bindingMismatch }

        let digest = try bodySHA256(body)
        guard let bodyDigest = fields["bodySha256"] as? String,
              bodyDigest.utf8.count == 64,
              bodyDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              bodyDigest == digest,
              let challengeID = fields["challengeId"] as? String, TeamAuthWire.credential(challengeID),
              let nonce = fields["nonce"] as? String, TeamAuthWire.credential(nonce),
              let expiry = try? TeamAuthWire.time(fields, "expiresAt"),
              now >= 0, now <= TeamAuthWire.maximumSafeTime,
              expected.accessExpiresAt <= TeamAuthWire.maximumSafeTime,
              expiry > now, expiry <= expected.accessExpiresAt, expiry - now <= 60_000
        else { throw TeamDeviceRequestWireError.invalidChallenge }

        return try JSONSerialization.data(withJSONObject: ["pinbook-device-request-v1", expected.audience,
            expected.authorityEpoch, expected.accountID, expected.sessionID, expected.deviceID,
            expected.enrollmentID, expected.keyThumbprint, expected.operation.rawValue, expected.teamID,
            expected.requestID, bodyDigest, challengeID, nonce, expiry], options: [.withoutEscapingSlashes])
    }
}
