import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct TeamDeviceRequestWireTests {
    private func vector() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: RequestFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: "team-device-request-v1", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func values() throws -> ([String: Any], [String: Any], TeamDeviceEnrollmentWire.PublicKey,
                                     TeamDeviceRequestWire.Binding, Data) {
        let fixture = try vector(), challenge = try #require(fixture["challenge"] as? [String: Any])
        func string(_ key: String) throws -> String { try #require(challenge[key] as? String) }
        let key = try TeamDeviceEnrollmentWire.publicKey(#require(fixture["publicKey"] as? [String: String]))
        let operation = try #require(TeamDeviceRequestWire.Operation(rawValue: string("operation")))
        let expiry = try #require(challenge["expiresAt"] as? NSNumber).int64Value
        let binding = TeamDeviceRequestWire.Binding(audience: try string("audience"), authorityEpoch: try string("authorityEpoch"),
            accountID: try string("accountId"), sessionID: try string("sessionId"), deviceID: try string("deviceId"),
            enrollmentID: try string("enrollmentId"), keyThumbprint: try string("keyThumbprint"), operation: operation,
            teamID: try string("teamId"), requestID: try string("requestId"), accessExpiresAt: expiry)
        let encodedBody = try #require(fixture["bodyBase64url"] as? String)
        let body = try #require(TeamDeviceEnrollmentWire.decode(encodedBody))
        return (fixture, challenge, key, binding, body)
    }
    private func wire(_ challenge: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: challenge, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    @Test func androidBackendVectorRebuildsAndVerifiesInCryptoKit() throws {
        let (fixture, challenge, key, expected, body) = try values()
        let expiry = try #require(challenge["expiresAt"] as? NSNumber).int64Value
        let message = try TeamDeviceRequestWire.message(challenge: wire(challenge), expected: expected,
            publicKey: key, body: body, now: expiry - 60_000)
        #expect(String(decoding: message, as: UTF8.self) == fixture["messageUtf8"] as? String)
        #expect(try TeamDeviceRequestWire.bodySHA256(body) == challenge["bodySha256"] as? String)
        let messageDigest = SHA256.hash(data: message).map { String(format: "%02x", $0) }.joined()
        #expect(messageDigest == fixture["messageSha256"] as? String)
        let encodedSignature = try #require(fixture["signature"] as? String)
        let raw = try #require(TeamDeviceEnrollmentWire.decode(encodedSignature))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        #expect(raw.count == 64 && key.key.isValidSignature(signature, for: message))
        #expect(!key.key.isValidSignature(signature, for: message + Data([10])))
    }

    @Test func everyLocalBindingBodyAndKeySubstitutionIsRejected() throws {
        let (_, challenge, key, expected, body) = try values()
        let expiry = try #require(challenge["expiresAt"] as? NSNumber).int64Value
        for field in ["audience", "authorityEpoch", "accountId", "sessionId", "deviceId", "enrollmentId",
                      "keyThumbprint", "operation", "teamId", "requestId"] {
            var changed = challenge
            changed[field] = field == "keyThumbprint" ? String(repeating: "A", count: 43) :
                (field == "operation" ? "delivery-fetch" : "other")
            #expect(throws: TeamDeviceRequestWireError.bindingMismatch) {
                try TeamDeviceRequestWire.message(challenge: wire(changed), expected: expected,
                    publicKey: key, body: body, now: expiry - 60_000)
            }
        }
        var changedBodyDigest = challenge; changedBodyDigest["bodySha256"] = String(repeating: "0", count: 64)
        #expect(throws: TeamDeviceRequestWireError.invalidChallenge) {
            try TeamDeviceRequestWire.message(challenge: wire(changedBodyDigest), expected: expected,
                publicKey: key, body: body, now: expiry - 60_000)
        }
        #expect(throws: TeamDeviceRequestWireError.invalidChallenge) {
            try TeamDeviceRequestWire.message(challenge: wire(challenge), expected: expected,
                publicKey: key, body: body + Data([10]), now: expiry - 60_000)
        }
        let otherKey = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        #expect(throws: TeamDeviceRequestWireError.bindingMismatch) {
            try TeamDeviceRequestWire.message(challenge: wire(challenge), expected: expected,
                publicKey: otherKey, body: body, now: expiry - 60_000)
        }
    }

    @Test func boundsDeadlineStrictShapeAndSignedFieldsFailClosed() throws {
        let (fixture, challenge, key, expected, body) = try values()
        let expiry = try #require(challenge["expiresAt"] as? NSNumber).int64Value
        #expect(throws: TeamDeviceRequestWireError.invalidBody) { try TeamDeviceRequestWire.bodySHA256(Data()) }
        #expect(throws: TeamDeviceRequestWireError.invalidBody) { try TeamDeviceRequestWire.bodySHA256(Data(repeating: 0, count: 65_537)) }
        #expect(throws: TeamDeviceRequestWireError.invalidChallenge) {
            try TeamDeviceRequestWire.message(challenge: wire(challenge), expected: expected,
                publicKey: key, body: body, now: expiry)
        }
        var late = challenge; late["expiresAt"] = expiry + 1
        #expect(throws: TeamDeviceRequestWireError.invalidChallenge) {
            try TeamDeviceRequestWire.message(challenge: wire(late), expected: expected,
                publicKey: key, body: body, now: expiry - 60_000)
        }
        var extra = challenge; extra["extra"] = true
        #expect(throws: TeamDeviceRequestWireError.invalidChallenge) {
            try TeamDeviceRequestWire.message(challenge: wire(extra), expected: expected,
                publicKey: key, body: body, now: expiry - 60_000)
        }
        let encodedSignature = try #require(fixture["signature"] as? String)
        let raw = try #require(TeamDeviceEnrollmentWire.decode(encodedSignature))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        for field in ["challengeId", "nonce", "expiresAt"] {
            var changed = challenge
            if field == "challengeId" { changed[field] = challenge["nonce"] }
            else if field == "nonce" { changed[field] = challenge["challengeId"] }
            else { changed[field] = expiry - 1 }
            let message = try TeamDeviceRequestWire.message(challenge: wire(changed), expected: expected,
                publicKey: key, body: body, now: expiry - 60_000)
            #expect(!key.key.isValidSignature(signature, for: message))
        }
    }
}

#if !SWIFT_PACKAGE
private final class RequestFixtureBundleMarker: NSObject {}
#endif
