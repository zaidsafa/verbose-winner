import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct TeamAgreementPossessionTests {
    private func fixture() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: AgreementPossessionFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: "team-agreement-possession-v1",
            withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func publicJWK(_ value: Any?) throws -> [String: String] {
        var result = try #require(value as? [String: String])
        result.removeValue(forKey: "d")
        return result
    }

    private func decodeBase64URL(_ value: String) throws -> Data {
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        return try #require(Data(base64Encoded: padded))
    }

    @Test func androidServerAgreementPossessionVectorMatchesCryptoKitExactly() throws {
        let value = try fixture()
        let signingKey = try TeamDeviceEnrollmentWire.publicKey(
            #require(value["signingPublicKey"] as? [String: String]))
        let clientJWK = try publicJWK(value["clientAgreementJwk"])
        let serverJWK = try publicJWK(value["serverEphemeralJwk"])
        let clientPublic = try TeamDeviceEnrollmentWire.publicKey(clientJWK)
        let serverPublic = try TeamDeviceEnrollmentWire.publicKey(serverJWK)
        let clientThumbprint = try #require(value["clientAgreementKeyThumbprint"] as? String)
        let serverThumbprint = try #require(value["serverEphemeralKeyThumbprint"] as? String)
        #expect(clientPublic.thumbprint == clientThumbprint)
        #expect(serverPublic.thumbprint == serverThumbprint)

        let clientFields = try #require(value["clientAgreementJwk"] as? [String: String])
        let serverFields = try #require(value["serverEphemeralJwk"] as? [String: String])
        let clientD = try #require(clientFields["d"])
        let serverD = try #require(serverFields["d"])
        let clientPrivateBytes = try #require(TeamDeviceEnrollmentWire.decode(clientD))
        let serverPrivateBytes = try #require(TeamDeviceEnrollmentWire.decode(serverD))
        let clientPrivate = try P256.KeyAgreement.PrivateKey(rawRepresentation: clientPrivateBytes)
        let serverPrivate = try P256.KeyAgreement.PrivateKey(rawRepresentation: serverPrivateBytes)
        let decodedClientPublic = try P256.KeyAgreement.PublicKey(
            x963Representation: clientPublic.key.x963Representation)
        #expect(clientPrivate.publicKey.x963Representation == decodedClientPublic.x963Representation)

        var shared = try clientPrivate.sharedSecretFromKeyAgreement(with: serverPrivate.publicKey)
            .withUnsafeBytes { Data($0) }
        defer { shared.resetBytes(in: shared.startIndex..<shared.endIndex) }
        #expect(TeamDeviceEnrollmentWire.encode(shared) == value["sharedSecretBase64url"] as? String)

        let challenge = try #require(value["challenge"] as? [String: Any])
        let challengeID = try #require(challenge["challengeId"] as? String)
        var confirmationKey = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: shared,
            algorithm: TeamAgreementPossession.algorithm, partyU: Data(challengeID.utf8),
            partyV: Data(clientThumbprint.utf8), bits: 256)
        defer { confirmationKey.resetBytes(in: confirmationKey.startIndex..<confirmationKey.endIndex) }
        #expect(TeamDeviceEnrollmentWire.encode(confirmationKey) == value["confirmationKeyBase64url"] as? String)

        let encodedBody = try #require(value["bodyBase64url"] as? String)
        let body = try decodeBase64URL(encodedBody)
        let agreement = TeamAgreementPublic(keyThumbprint: clientThumbprint, publicKey: clientPublic)
        let request = try TeamAgreementEnrollmentRequest(membershipRevision: 2, agreement: agreement)
        #expect(request.body == body)
        let expiresAt = try #require(challenge["expiresAt"] as? NSNumber).int64Value
        let expected = TeamDeviceRequestWire.Binding(
            audience: try #require(challenge["audience"] as? String),
            authorityEpoch: try #require(challenge["authorityEpoch"] as? String),
            accountID: try #require(challenge["accountId"] as? String),
            sessionID: try #require(challenge["sessionId"] as? String),
            deviceID: try #require(challenge["deviceId"] as? String),
            enrollmentID: try #require(challenge["enrollmentId"] as? String),
            keyThumbprint: try #require(challenge["keyThumbprint"] as? String),
            operation: .agreementEnroll,
            teamID: try #require(challenge["teamId"] as? String),
            requestID: try #require(challenge["requestId"] as? String),
            accessExpiresAt: expiresAt)
        var fullChallenge = challenge
        fullChallenge["agreementServerKeyThumbprint"] = serverThumbprint
        fullChallenge["agreementServerPublicKey"] = serverJWK
        let wire = try JSONSerialization.data(withJSONObject: fullChallenge, options: [.sortedKeys])
        let prepared = try TeamPreparedAgreementRequestChallenge(validating: wire,
            expected: expected, publicKey: signingKey, request: request, now: expiresAt - 60_000)
        var requestMessage = try prepared.message(expected: expected, publicKey: signingKey,
            request: request, now: expiresAt - 60_000)
        defer { requestMessage.resetBytes(in: requestMessage.startIndex..<requestMessage.endIndex) }
        #expect(String(decoding: requestMessage, as: UTF8.self) == value["requestMessageUtf8"] as? String)

        let confirmation = try TeamAgreementPossession.confirmation(key: confirmationKey,
            requestMessage: requestMessage, agreementKeyThumbprint: clientThumbprint,
            serverKeyThumbprint: serverThumbprint)
        #expect(TeamDeviceEnrollmentWire.encode(confirmation) == value["confirmation"] as? String)
        let encodedRequest = TeamDeviceEnrollmentWire.encode(requestMessage)
        let possessionMessage = try JSONSerialization.data(withJSONObject: [TeamAgreementPossession.purpose,
            encodedRequest, clientThumbprint, serverThumbprint], options: [.withoutEscapingSlashes])
        #expect(String(decoding: possessionMessage, as: UTF8.self) == value["possessionMessageUtf8"] as? String)

        let changedThumbprint = String(repeating: "A", count: 43)
        let changed = try TeamAgreementPossession.confirmation(key: confirmationKey,
            requestMessage: requestMessage, agreementKeyThumbprint: changedThumbprint,
            serverKeyThumbprint: serverThumbprint)
        #expect(changed != confirmation)
    }

    @Test func agreementChallengeRejectsPrivateForeignAndReflectedServerKeys() throws {
        let value = try fixture()
        let signingKey = try TeamDeviceEnrollmentWire.publicKey(
            #require(value["signingPublicKey"] as? [String: String]))
        let clientJWK = try publicJWK(value["clientAgreementJwk"])
        let client = try TeamDeviceEnrollmentWire.publicKey(clientJWK)
        let agreement = TeamAgreementPublic(keyThumbprint: client.thumbprint, publicKey: client)
        let request = try TeamAgreementEnrollmentRequest(membershipRevision: 2, agreement: agreement)
        let base = try #require(value["challenge"] as? [String: Any])
        let expiresAt = try #require(base["expiresAt"] as? NSNumber).int64Value
        let binding = TeamDeviceRequestWire.Binding(
            audience: try #require(base["audience"] as? String),
            authorityEpoch: try #require(base["authorityEpoch"] as? String),
            accountID: try #require(base["accountId"] as? String),
            sessionID: try #require(base["sessionId"] as? String),
            deviceID: try #require(base["deviceId"] as? String),
            enrollmentID: try #require(base["enrollmentId"] as? String),
            keyThumbprint: signingKey.thumbprint, operation: .agreementEnroll,
            teamID: try #require(base["teamId"] as? String),
            requestID: try #require(base["requestId"] as? String), accessExpiresAt: expiresAt)

        var reflected = base
        reflected["agreementServerKeyThumbprint"] = client.thumbprint
        reflected["agreementServerPublicKey"] = clientJWK
        #expect(throws: TeamAuthHTTPError.invalidResponse) {
            try TeamPreparedAgreementRequestChallenge(validating:
                JSONSerialization.data(withJSONObject: reflected), expected: binding,
                publicKey: signingKey, request: request, now: expiresAt - 60_000)
        }
        var privateServer = try #require(value["serverEphemeralJwk"] as? [String: String])
        var leaking = base
        leaking["agreementServerKeyThumbprint"] = value["serverEphemeralKeyThumbprint"]
        leaking["agreementServerPublicKey"] = privateServer
        #expect(throws: TeamAuthHTTPError.invalidResponse) {
            try TeamPreparedAgreementRequestChallenge(validating:
                JSONSerialization.data(withJSONObject: leaking), expected: binding,
                publicKey: signingKey, request: request, now: expiresAt - 60_000)
        }
        privateServer.removeValue(forKey: "d")
        var wrongThumbprint = base
        wrongThumbprint["agreementServerKeyThumbprint"] = String(repeating: "B", count: 43)
        wrongThumbprint["agreementServerPublicKey"] = privateServer
        #expect(throws: TeamAuthHTTPError.invalidResponse) {
            try TeamPreparedAgreementRequestChallenge(validating:
                JSONSerialization.data(withJSONObject: wrongThumbprint), expected: binding,
                publicKey: signingKey, request: request, now: expiresAt - 60_000)
        }
    }
}

#if !SWIFT_PACKAGE
private final class AgreementPossessionFixtureBundleMarker: NSObject {}
#endif
