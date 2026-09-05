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

    private func pending(_ fixture: JWEVector, jwe: Data,
                         sender: String = "author_fixture") -> TeamPendingDelivery {
        TeamPendingDelivery(deliveryID: "delivery_fixture", acceptedAt: 1_000,
            expiresAt: 2_592_001_000, jweBytes: jwe.count,
            jweSHA256: SHA256.hash(data: jwe).map { String(format: "%02x", $0) }.joined(),
            senderAccountID: sender, senderDeviceID: "author_device",
            senderEnrollmentID: "author_enrollment", audienceDigest: fixture.audienceDigest,
            agreementKeyThumbprint: fixture.recipients[0].kid)
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

    @Test func authenticatedFetchIsDecryptedArchivedAndQueuedBeforeAnyACK() throws {
        let fixture = try vector()
        let recipients = try fixture.recipients.map(agreement)
        let target = try DeliveryTarget(userId: "recipient_fixture_0",
            deviceId: "device_fixture_0", enrollmentId: "enrollment_fixture_0")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinbook-receive-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try TeamInboxStore(applicationSupportDirectory: root,
            target: target, teamId: "team_fixture")
        let jwe = Data(fixture.canonicalJwe.utf8)
        let pending = pending(fixture, jwe: jwe)
        let fetch = TeamDeliveryFetchResult(deliveryID: "delivery_fixture",
            acceptedAt: 1_000, expiresAt: 2_592_001_000, jweBytes: jwe.count,
            jweSHA256: SHA256.hash(data: jwe).map { String(format: "%02x", $0) }.joined(),
            audienceDigest: fixture.audienceDigest,
            agreementKeyThumbprint: fixture.recipients[0].kid, jwe: jwe)
        let binding = TeamDeviceRequestWire.Binding(audience: "https://pinbook.example.test",
            authorityEpoch: "epoch_fixture", accountID: target.userId,
            sessionID: "session_fixture", deviceID: target.deviceId,
            enrollmentID: target.enrollmentId, keyThumbprint: String(repeating: "A", count: 43),
            operation: .deliveryFetch, teamID: "team_fixture",
            requestID: "delivery_fixture", accessExpiresAt: 60_000)
        let receiver = TeamDeliveryReceiveCoordinator()

        let receipt = try receiver.archiveFetched(fetch, pending: pending, expectedBinding: binding,
            expectedRecipients: recipients,
            custody: custody(fixture.recipients[0], index: 0), inbox: inbox, savedAt: 2_000)
        #expect(receipt.deliveryId == "delivery_fixture")
        #expect(receipt.jweSHA256 == fetch.jweSHA256)
        #expect(String(data: try TeamDeliveryACKRequest(receipt: receipt).body,
            encoding: .utf8) == "{\"deliveryId\":\"delivery_fixture\",\"jweSha256\":\"\(fetch.jweSHA256)\",\"type\":\"pinbook-delivery-ack-v1\"}")
        #expect(try inbox.archived(deliveryId: "delivery_fixture")?.envelope.body.contains("Pinbook team hello") == true)
        #expect(try inbox.pendingReceipts() == [receipt])

        let otherCiphertextHash = TeamDeliveryFetchResult(deliveryID: fetch.deliveryID,
            acceptedAt: fetch.acceptedAt, expiresAt: fetch.expiresAt,
            jweBytes: fetch.jweBytes, jweSHA256: String(repeating: "0", count: 64),
            audienceDigest: fetch.audienceDigest,
            agreementKeyThumbprint: fetch.agreementKeyThumbprint, jwe: fetch.jwe)
        #expect(throws: TeamDeliveryReceiveError.bindingMismatch) {
            try receiver.archiveFetched(otherCiphertextHash, pending: pending, expectedBinding: binding,
                expectedRecipients: recipients,
                custody: custody(fixture.recipients[0], index: 0), inbox: inbox, savedAt: 3_000)
        }

        // Exact replay remains idempotent and never duplicates the pending ACK identity.
        #expect(try receiver.archiveFetched(fetch, pending: pending, expectedBinding: binding,
            expectedRecipients: recipients,
            custody: custody(fixture.recipients[0], index: 0), inbox: inbox, savedAt: 3_000) == receipt)
        #expect(try inbox.pendingReceipts() == [receipt])

        let ackBinding = TeamDeviceRequestWire.Binding(audience: binding.audience,
            authorityEpoch: binding.authorityEpoch, accountID: binding.accountID,
            sessionID: binding.sessionID, deviceID: binding.deviceID,
            enrollmentID: binding.enrollmentID, keyThumbprint: binding.keyThumbprint,
            operation: .deliveryACK, teamID: binding.teamID,
            requestID: receipt.deliveryId, accessExpiresAt: binding.accessExpiresAt)
        let ack = TeamDeliveryACKResult(deliveryID: receipt.deliveryId,
            settledAt: 2_500, expiresAt: fetch.expiresAt,
            jweSHA256: receipt.jweSHA256, purgeEligible: false)
        #expect(try TeamDeliveryReceiptCoordinator().apply(ack, receipt: receipt,
            expectedBinding: ackBinding, inbox: inbox) == .acknowledged(purgeEligible: false))
        #expect(try inbox.pendingReceipts().isEmpty)
        #expect(try inbox.archived(deliveryId: receipt.deliveryId) != nil)

        let archived = try #require(try inbox.archived(deliveryId: receipt.deliveryId))
        try inbox.receive(archived.envelope, jweSHA256: receipt.jweSHA256,
            savedAt: archived.savedAt)
        #expect(throws: TeamDeliveryReceiveError.invalidACK) {
            try TeamDeliveryReceiptCoordinator().applyAuthenticatedTerminal(
                .server(.uncertain), receipt: receipt,
                expectedBinding: ackBinding, inbox: inbox)
        }
        #expect(try inbox.pendingReceipts() == [receipt])
        #expect(try TeamDeliveryReceiptCoordinator().applyAuthenticatedTerminal(
            .server(.terminal), receipt: receipt,
            expectedBinding: ackBinding, inbox: inbox) == .cancelled)
        #expect(try inbox.pendingReceipts().isEmpty)
        #expect(try inbox.archived(deliveryId: receipt.deliveryId) != nil)
    }

    @Test func ackBodyRejectsPlaintextDigestAndMalformedReceiptMetadata() throws {
        let digest = String(repeating: "a", count: 64)
        let valid = PendingTeamReceipt(accountId: "account", teamId: "team",
            deliveryId: "delivery", deviceId: "device", enrollmentId: "enrollment",
            jweSHA256: digest)
        #expect(try TeamDeliveryACKRequest(receipt: valid).jweSHA256 == digest)
        for bad in ["", String(repeating: "A", count: 64), String(repeating: "0", count: 63)] {
            let receipt = PendingTeamReceipt(accountId: valid.accountId, teamId: valid.teamId,
                deliveryId: valid.deliveryId, deviceId: valid.deviceId,
                enrollmentId: valid.enrollmentId, jweSHA256: bad)
            #expect(throws: TeamAuthHTTPError.invalidRequest) {
                try TeamDeliveryACKRequest(receipt: receipt)
            }
        }
    }

    @Test func receiveFailsClosedBeforeArchiveForChangedBindingsOrCiphertext() throws {
        let fixture = try vector()
        let recipients = try fixture.recipients.map(agreement)
        let target = try DeliveryTarget(userId: "recipient_fixture_0",
            deviceId: "device_fixture_0", enrollmentId: "enrollment_fixture_0")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinbook-receive-fail-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try TeamInboxStore(applicationSupportDirectory: root,
            target: target, teamId: "team_fixture")
        let jwe = Data(fixture.canonicalJwe.utf8)
        let digest = SHA256.hash(data: jwe).map { String(format: "%02x", $0) }.joined()
        let pending = pending(fixture, jwe: jwe)
        let fetch = TeamDeliveryFetchResult(deliveryID: "delivery_fixture", acceptedAt: 1_000,
            expiresAt: 2_592_001_000, jweBytes: jwe.count, jweSHA256: digest,
            audienceDigest: fixture.audienceDigest,
            agreementKeyThumbprint: fixture.recipients[0].kid, jwe: jwe)
        let binding = TeamDeviceRequestWire.Binding(audience: "https://pinbook.example.test",
            authorityEpoch: "epoch_fixture", accountID: target.userId,
            sessionID: "session_fixture", deviceID: target.deviceId,
            enrollmentID: target.enrollmentId, keyThumbprint: String(repeating: "A", count: 43),
            operation: .deliveryFetch, teamID: "team_fixture",
            requestID: "delivery_fixture", accessExpiresAt: 60_000)
        let receiver = TeamDeliveryReceiveCoordinator()
        let badDigest = TeamDeliveryFetchResult(deliveryID: fetch.deliveryID,
            acceptedAt: fetch.acceptedAt, expiresAt: fetch.expiresAt, jweBytes: fetch.jweBytes,
            jweSHA256: String(repeating: "0", count: 64), audienceDigest: fetch.audienceDigest,
            agreementKeyThumbprint: fetch.agreementKeyThumbprint, jwe: fetch.jwe)

        #expect(throws: TeamDeliveryReceiveError.bindingMismatch) {
            try receiver.archiveFetched(badDigest, pending: pending, expectedBinding: binding,
                expectedRecipients: recipients,
                custody: custody(fixture.recipients[0], index: 0), inbox: inbox, savedAt: 2_000)
        }
        #expect(throws: TeamDeliveryReceiveError.invalidFetch) {
            try receiver.archiveFetched(fetch,
                pending: self.pending(fixture, jwe: jwe, sender: "different_author"),
                expectedBinding: binding, expectedRecipients: recipients,
                custody: custody(fixture.recipients[0], index: 0), inbox: inbox, savedAt: 2_000)
        }
        #expect(try inbox.archived(deliveryId: "delivery_fixture") == nil)
        #expect(try inbox.pendingReceipts().isEmpty)
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
