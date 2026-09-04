import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct TeamDeviceEnrollmentWireTests {
    private func vector(_ name: String = "team-device-enrollment-v1") throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func binding(_ fixture: [String: Any], expiry: Int64 = 120_000) throws -> TeamDeviceEnrollmentWire.Binding {
        let key = try TeamDeviceEnrollmentWire.publicKey(#require(fixture["publicKey"] as? [String: String]))
        return .init(audience: "https://pinbook.example", authorityEpoch: "public-epoch",
            accountID: "public-account", sessionID: "public-session", deviceID: "public-device",
            keyThumbprint: key.thumbprint, accessExpiresAt: expiry)
    }
    @Test func nodeSignatureAndExactCanonicalMessageVerifyInCryptoKit() throws {
        try verifyCanonicalSignature(vector())
    }
    @Test func physicalAndroidQAKeySignatureAndEveryBindingVerifyInCryptoKit() throws {
        // Exact public Samsung AndroidKeyStore handoff; never includes a private
        // alias/key or real account authority. Verifies crypto, not live delivery.
        let fixture = try vector("team-device-enrollment-android-qa-v1")
        try verifyCanonicalSignature(fixture)
        try verifyChangedFields(fixture)
    }
    private func verifyCanonicalSignature(_ fixture: [String: Any]) throws {
        let expected = try binding(fixture)
        let key = try TeamDeviceEnrollmentWire.publicKey(#require(fixture["publicKey"] as? [String: String]))
        let challenge = try #require(fixture["challenge"] as? [String: Any])
        let message = try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: challenge), expected: expected, now: 1)
        #expect(String(decoding: message, as: UTF8.self) == fixture["message"] as? String)
        #expect(key.thumbprint == challenge["keyThumbprint"] as? String)
        let encodedSignature = try #require(fixture["signature"] as? String)
        let raw = try #require(TeamDeviceEnrollmentWire.decode(encodedSignature))
        #expect(raw.count == 64)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        #expect(key.key.isValidSignature(signature, for: message))
        #expect(!key.key.isValidSignature(signature, for: message + Data([10])))
        #expect(!key.key.isValidSignature(signature, for: Data(SHA256.hash(data: message))))
        #expect(throws: (any Error).self) { try P256.Signing.ECDSASignature(rawRepresentation: signature.derRepresentation) }
        #expect(try TeamDeviceEnrollmentWire.publicKey(key.key).jwk == key.jwk)
    }
    @Test func eachLocallyKnownBindingAndEverySignedFieldMatter() throws {
        try verifyChangedFields(vector())
    }
    private func verifyChangedFields(_ fixture: [String: Any]) throws {
        let expected = try binding(fixture)
        let original = try #require(fixture["challenge"] as? [String: Any])
        for field in ["audience", "authorityEpoch", "accountId", "sessionId", "deviceId", "keyThumbprint"] {
            var changed = original; changed[field] = "wrong"
            #expect(throws: TeamDeviceEnrollmentWireError.bindingMismatch) {
                try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: changed), expected: expected, now: 1)
            }
        }
        let key = try TeamDeviceEnrollmentWire.publicKey(#require(fixture["publicKey"] as? [String: String]))
        let encodedSignature = try #require(fixture["signature"] as? String)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: #require(TeamDeviceEnrollmentWire.decode(encodedSignature)))
        for field in ["challengeId", "nonce", "expiresAt"] {
            var changed = original
            changed[field] = field == "expiresAt" ? 119_999 : String(repeating: "A", count: 43)
            let message = try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: changed), expected: expected, now: 1)
            #expect(!key.key.isValidSignature(signature, for: message))
        }
    }
    @Test func malformedKeysAndNoncanonicalCoordinatesAreRejected() throws {
        let original = try #require(vector()["publicKey"] as? [String: String])
        for (field, value) in [("d", "private"), ("crv", "P-384"), ("kty", "RSA"), ("x", original["x"]! + "="), ("y", "invalid")] {
            var changed = original; changed[field] = value
            #expect(throws: TeamDeviceEnrollmentWireError.invalidKey) { try TeamDeviceEnrollmentWire.publicKey(changed) }
        }
        #expect(throws: TeamDeviceEnrollmentWireError.invalidKey) {
            try TeamDeviceEnrollmentWire.publicKey(["kty": "EC", "crv": "P-256", "x": String(repeating: "A", count: 43), "y": String(repeating: "A", count: 43)])
        }
    }
    @Test func canonicalAudienceRejectsPathCredentialsAndAlternateSpellings() {
        for value in ["https://pinbook.example", "https://pinbook.example:8443"] {
            #expect(TeamDeviceEnrollmentWire.canonicalAudience(value))
        }
        for value in ["http://pinbook.example", "https://pinbook.example/", "https://PINBOOK.example", "https://pinbook.example:443",
            "https://pinbook.example:08443", "https://pinbook.example:65536", "https://pinbook.example.", "https://127.0.0.1",
            "https://0x7f000001", "https://0x7f.1", "https://example.123", "https://example.0xff",
            "https://[::1]", "https://user@pinbook.example", "https://pinbook.example?q=a", "https://pinbook.example#x", "https://pinbook.example/path"] {
            #expect(!TeamDeviceEnrollmentWire.canonicalAudience(value))
        }
    }
    @Test func nativeGeneratedSignatureUsesRawSingleHashEncoding() throws {
        let fixture = try vector()
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = try TeamDeviceEnrollmentWire.publicKey(privateKey.publicKey)
        var challenge = try #require(fixture["challenge"] as? [String: Any])
        challenge["keyThumbprint"] = publicKey.thumbprint
        let expected = TeamDeviceEnrollmentWire.Binding(audience: "https://pinbook.example", authorityEpoch: "public-epoch",
            accountID: "public-account", sessionID: "public-session", deviceID: "public-device",
            keyThumbprint: publicKey.thumbprint, accessExpiresAt: 120_000)
        let message = try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: challenge), expected: expected, now: 1)
        // CryptoKit's Data overload performs SHA256 itself. Do not prehash this Data.
        let signature = try privateKey.signature(for: message)
        #expect(signature.rawRepresentation.count == 64)
        #expect(publicKey.key.isValidSignature(signature, for: message))
        if ProcessInfo.processInfo.environment["PINBOOK_PUBLIC_WIRE_VECTOR"] == "1" {
            let output = try JSONSerialization.data(withJSONObject: ["publicKey": publicKey.jwk, "challenge": challenge,
                "message": String(decoding: message, as: UTF8.self),
                "signature": TeamDeviceEnrollmentWire.encode(signature.rawRepresentation)], options: [.sortedKeys, .withoutEscapingSlashes])
            // Explicit local test command only. Public data, no private key or token.
            print("PINBOOK_PUBLIC_DEVICE_VECTOR=" + String(decoding: output, as: UTF8.self))
        }
    }
    @Test func malformedExpiredAndOutOfSessionChallengesCannotProduceBytes() throws {
        let fixture = try vector(), expected = try binding(fixture)
        let original = try #require(fixture["challenge"] as? [String: Any])
        for expiry: Any in [true, -1, 1, 120_002, 9_007_199_254_740_992, 1.5, "120000"] {
            var changed = original; changed["expiresAt"] = expiry
            #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) {
                try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: changed), expected: expected, now: 1)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: original)
        #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) { try TeamDeviceEnrollmentWire.message(challenge: data, expected: binding(fixture, expiry: 119_999), now: 1) }
        #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) { try TeamDeviceEnrollmentWire.message(challenge: data, expected: expected, now: -1) }
        for field in ["nonce", "challengeId"] {
            var changed = original; changed[field] = String(repeating: "B", count: 43)
            #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) { try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: changed), expected: expected, now: 1) }
        }
        var changed = original; changed["extra"] = true
        #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) { try TeamDeviceEnrollmentWire.message(challenge: JSONSerialization.data(withJSONObject: changed), expected: expected, now: 1) }
        #expect(throws: TeamDeviceEnrollmentWireError.invalidChallenge) { try TeamDeviceEnrollmentWire.message(challenge: Data(repeating: 32, count: 32_769), expected: expected, now: 1) }
    }
}

#if !SWIFT_PACKAGE
private final class FixtureBundleMarker: NSObject {}
#endif
