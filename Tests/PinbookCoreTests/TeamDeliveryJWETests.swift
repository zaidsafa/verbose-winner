import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class JWEFixtureBundleMarker: NSObject {}

private struct JWEVector: Decodable {
    struct JWK: Decodable {
        let kty: String
        let crv: String
        let x: String
        let y: String
        let d: String
        var publicFields: [String: String] { ["kty": kty, "crv": crv, "x": x, "y": y] }
    }
    struct Recipient: Decodable {
        let kid: String
        let recipientJwk: JWK
        let ephemeralJwk: JWK
        let encryptedKey: String
        let apu: String
        let apv: String
    }
    let plaintextUtf8: String
    let plaintextBase64url: String
    let contentEncryptionKey: String
    let initializationVector: String
    let audienceDigest: String
    let protected: String
    let recipients: [Recipient]
    let canonicalJwe: String
}

private struct JWEFixtureStore: TeamAgreementKeyStoring {
    let sealed: Data
    func load(scope: String) throws -> Data? { sealed }
    func insert(scope: String, sealed: Data) throws -> Bool { false }
}

private final class JWEFixtureKeys: TeamAgreementKeyProviding, @unchecked Sendable {
    let sealed: Data
    let privateKey: P256.KeyAgreement.PrivateKey
    init(sealed: Data, privateKey: P256.KeyAgreement.PrivateKey) {
        self.sealed = sealed
        self.privateKey = privateKey
    }
    func generate() throws -> TeamAgreementKeyMaterial {
        .init(sealed: sealed, publicKey: try wire(privateKey.publicKey))
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        guard sealed == self.sealed else { throw TeamAgreementKeyError.keyUnavailable }
        return try wire(privateKey.publicKey)
    }
    func agree(sealed: Data, peer: TeamDeviceEnrollmentWire.PublicKey) throws -> Data {
        guard sealed == self.sealed else { throw TeamAgreementKeyError.keyUnavailable }
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: peer.key.x963Representation)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Data($0) }
    }
    private func wire(_ key: P256.KeyAgreement.PublicKey) throws -> TeamDeviceEnrollmentWire.PublicKey {
        try TeamDeviceEnrollmentWire.publicKey(
            P256.Signing.PublicKey(x963Representation: key.x963Representation))
    }
}

private final class JWEFixtureInputs {
    var entropy: [Data]
    var ephemerals: [P256.KeyAgreement.PrivateKey]
    init(entropy: [Data], ephemerals: [P256.KeyAgreement.PrivateKey]) {
        self.entropy = entropy
        self.ephemerals = ephemerals
    }
    func nextEntropy(_ count: Int) throws -> Data {
        guard !entropy.isEmpty else { throw TeamDeliveryJWEError.invalidInput }
        let result = entropy.removeFirst()
        guard result.count == count else { throw TeamDeliveryJWEError.invalidInput }
        return result
    }
    func nextEphemeral() throws -> P256.KeyAgreement.PrivateKey {
        guard !ephemerals.isEmpty else { throw TeamDeliveryJWEError.invalidInput }
        return ephemerals.removeFirst()
    }
}

struct TeamDeliveryJWETests {
    private func vector() throws -> JWEVector {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: JWEFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: "team-delivery-jwe-v1",
            withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JWEVector.self, from: Data(contentsOf: url))
    }

    private func decode(_ value: String) throws -> Data {
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        return try #require(Data(base64Encoded: padded))
    }

    private func encode(_ value: Data) -> String {
        value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func privateKey(_ jwk: JWEVector.JWK) throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: decode(jwk.d))
    }

    private func agreement(_ row: JWEVector.Recipient) throws -> TeamAgreementPublic {
        let key = try TeamDeviceEnrollmentWire.publicKey(row.recipientJwk.publicFields)
        #expect(key.thumbprint == row.kid)
        return TeamAgreementPublic(keyThumbprint: row.kid, publicKey: key)
    }

    private func custody(_ row: JWEVector.Recipient, index: Int) throws -> TeamAgreementKeyCustody {
        let key = try privateKey(row.recipientJwk)
        let sealed = Data("fixture-\(index)".utf8)
        #expect(try TeamDeviceEnrollmentWire.publicKey(row.recipientJwk.publicFields).key.x963Representation
            == P256.Signing.PublicKey(x963Representation: key.publicKey.x963Representation).x963Representation)
        return try TeamAgreementKeyCustody(origin: "https://pinbook.example.test",
            accountID: "account_fixture", authorityEpoch: "epoch_fixture",
            enrollmentID: "enrollment_fixture_\(index)",
            storage: JWEFixtureStore(sealed: sealed),
            keys: JWEFixtureKeys(sealed: sealed, privateKey: key), requireAccess: {})
    }

    @Test func androidServerVectorEncryptsCanonicalJWEAndBothRecipientsDecrypt() throws {
        let fixture = try vector()
        let recipients = try fixture.recipients.map(agreement)
        let plaintext = try decode(fixture.plaintextBase64url)
        #expect(String(data: plaintext, encoding: .utf8) == fixture.plaintextUtf8)
        let inputs = try JWEFixtureInputs(
            entropy: [decode(fixture.contentEncryptionKey), decode(fixture.initializationVector)],
            ephemerals: fixture.recipients.map { try privateKey($0.ephemeralJwk) })
        let profile = TeamDeliveryJWE(entropy: inputs.nextEntropy, ephemeral: inputs.nextEphemeral)
        let canonical = try profile.encrypt(plaintext, recipients: Array(recipients.reversed()))
        #expect(canonical == fixture.canonicalJwe)
        #expect(!canonical.contains(fixture.plaintextUtf8))
        let parsedProtected = try #require(
            TeamStrictJSON.object(Data(canonical.utf8), maximumDepth: 5)["protected"] as? String)
        #expect(fixture.protected == parsedProtected)
        for (index, row) in fixture.recipients.enumerated() {
            let decrypted = try TeamDeliveryJWE().decrypt(canonical,
                custody: custody(row, index: index),
                expectedRecipients: Array(recipients.reversed()))
            #expect(decrypted == plaintext)
            let payload = try TeamDeliveryPayloadCodec.decode(decrypted,
                expectedTeamId: "team_fixture", expectedDeliveryId: "delivery_fixture",
                expectedAuthorUserId: "author_fixture")
            #expect(payload.bodySha256 == TeamDeliveryRules.textSHA256(payload.body))
        }
    }

    @Test func changedCiphertextAudienceHeadersRecipientsAndTagFailClosed() throws {
        let fixture = try vector()
        let recipients = try fixture.recipients.map(agreement)
        let own = try custody(fixture.recipients[0], index: 0)
        let root = try TeamStrictJSON.object(Data(fixture.canonicalJwe.utf8), maximumDepth: 5)
        let ciphertext = try #require(root["ciphertext"] as? String)
        let tag = try #require(root["tag"] as? String)
        let changedCiphertext = fixture.canonicalJwe.replacingOccurrences(
            of: "\"ciphertext\":\"\(ciphertext)",
            with: "\"ciphertext\":\"\(ciphertext.first == "A" ? "B" : "A")\(ciphertext.dropFirst())")
        let changedKid = fixture.canonicalJwe.replacingOccurrences(
            of: recipients[0].keyThumbprint, with: String(repeating: "A", count: 43))
        let extraHeader = fixture.canonicalJwe.replacingOccurrences(
            of: "\"tag\":", with: "\"unprotected\":{},\"tag\":")
        let changedTag = fixture.canonicalJwe.replacingOccurrences(
            of: "\"tag\":\"\(tag)",
            with: "\"tag\":\"\(tag.first == "A" ? "B" : "A")\(tag.dropFirst())")
        let first = fixture.recipients[0]
        let changedEncryptedKey = fixture.canonicalJwe.replacingOccurrences(
            of: first.encryptedKey,
            with: "\(first.encryptedKey.first == "A" ? "B" : "A")\(first.encryptedKey.dropFirst())")
        let changedApu = fixture.canonicalJwe.replacingOccurrences(
            of: first.apu, with: "\(first.apu.first == "A" ? "B" : "A")\(first.apu.dropFirst())")
        let changedApv = fixture.canonicalJwe.replacingOccurrences(
            of: first.apv, with: "\(first.apv.first == "A" ? "B" : "A")\(first.apv.dropFirst())")
        let protectedText = try #require(String(data: decode(fixture.protected), encoding: .utf8))
        let changedProtectedText = protectedText.replacingOccurrences(
            of: fixture.audienceDigest, with: String(repeating: "A", count: 43))
        let changedProtected = encode(Data(changedProtectedText.utf8))
        let changedAudience = fixture.canonicalJwe.replacingOccurrences(
            of: fixture.protected, with: changedProtected)
        let firstEpk = fixture.recipients[0].ephemeralJwk
        let secondEpk = fixture.recipients[1].ephemeralJwk
        let repeatedEphemeral = fixture.canonicalJwe
            .replacingOccurrences(of: secondEpk.x, with: firstEpk.x)
            .replacingOccurrences(of: secondEpk.y, with: firstEpk.y)
        for changed in [changedCiphertext, changedKid, extraHeader, changedTag,
                        changedEncryptedKey, changedApu, changedApv, changedAudience,
                        repeatedEphemeral, fixture.canonicalJwe + " "] {
            #expect(throws: (any Error).self) {
                try TeamDeliveryJWE().decrypt(changed, custody: own,
                    expectedRecipients: recipients)
            }
        }
        #expect(throws: (any Error).self) {
            try TeamDeliveryJWE().decrypt(fixture.canonicalJwe, custody: own,
                expectedRecipients: Array(recipients.prefix(1)))
        }
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE().decrypt(fixture.canonicalJwe, custody: own,
                expectedRecipients: recipients + [recipients[0]])
        }
    }

    @Test func encryptionRejectsBoundsDuplicatesAndReusedEphemeralKeys() throws {
        let fixture = try vector()
        let recipients = try fixture.recipients.map(agreement)
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE().encrypt(Data(), recipients: recipients)
        }
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE().encrypt(Data(repeating: 0,
                count: TeamDeliveryJWE.maximumPlaintextBytes + 1), recipients: recipients)
        }
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE().encrypt(Data([1]), recipients: recipients + [recipients[0]])
        }
        let repeated = try privateKey(fixture.recipients[0].ephemeralJwk)
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE(entropy: { Data(repeating: 0, count: $0) },
                ephemeral: { repeated }).encrypt(Data([1]), recipients: recipients)
        }
        #expect(throws: TeamDeliveryJWEError.invalidInput) {
            try TeamDeliveryJWE(entropy: { Data(repeating: 0, count: $0 - 1) })
                .encrypt(Data([1]), recipients: recipients)
        }
    }
}
