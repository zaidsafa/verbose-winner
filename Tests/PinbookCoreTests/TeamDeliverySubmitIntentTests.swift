import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class DeliverySubmitIntentFixtureBundleMarker: NSObject {}

private struct DeliverySubmitIntentVector: Decodable {
    let audienceDigest: String
    let deliveryId: String
    let jweBytes: Int
    let jweSha256: String
    let membershipRevision: Int64
    let type: String
    let canonicalIntentUtf8: String
    let canonicalIntentBase64url: String
}

private struct SubmitIntentJWEVector: Decodable {
    struct JWK: Decodable {
        let kty: String
        let crv: String
        let x: String
        let y: String
        var publicFields: [String: String] { ["kty": kty, "crv": crv, "x": x, "y": y] }
    }
    struct Recipient: Decodable {
        let kid: String
        let recipientJwk: JWK
    }
    let recipients: [Recipient]
    let canonicalJwe: String
}

struct TeamDeliverySubmitIntentTests {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: DeliverySubmitIntentFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func reservationFixture() throws
        -> (TeamDeliveryReservationRequest, TeamDeviceRequestWire.Binding,
            TeamAudience, TeamDeliverySubmissionReservation, Int64) {
        let vector = try fixture("team-delivery-submit-intent-v1",
                                 as: DeliverySubmitIntentVector.self)
        let jweVector = try fixture("team-delivery-jwe-v1", as: SubmitIntentJWEVector.self)
        let intent = try TeamDeliverySubmitIntentCodec.fromCanonicalJWE(
            deliveryId: vector.deliveryId, membershipRevision: vector.membershipRevision,
            audienceDigest: vector.audienceDigest, serialized: jweVector.canonicalJwe)
        let request = try TeamDeliveryReservationRequest(intent: intent,
            canonicalJWE: jweVector.canonicalJwe)
        let signing = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
        let binding = TeamDeviceRequestWire.Binding(audience: "https://pinbook.example.test",
            authorityEpoch: "epoch_fixture", accountID: "sender_account",
            sessionID: "session_fixture", deviceID: "sender_device",
            enrollmentID: "sender_enrollment", keyThumbprint: signing.thumbprint,
            operation: .deliverySubmit, teamID: "team_fixture",
            requestID: vector.deliveryId, accessExpiresAt: 1_800_001_000_000)
        var targets = [TeamAudienceTarget]()
        for (index, recipient) in jweVector.recipients.enumerated() {
            let agreement = try TeamDeviceEnrollmentWire.publicKey(recipient.recipientJwk.publicFields)
            #expect(agreement.thumbprint == recipient.kid)
            let signingKey = try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PrivateKey().publicKey)
            targets.append(.init(accountID: "target_account_\(index)", deviceID: "target_device_\(index)",
                enrollmentID: "target_enrollment_\(index)", keyThumbprint: signingKey.thumbprint,
                publicKey: signingKey, agreementKeyThumbprint: recipient.kid,
                agreementPublicKey: agreement))
        }
        let audience = TeamAudience(teamID: binding.teamID,
            membershipRevision: intent.membershipRevision, targets: Array(targets.reversed()))
        let frozen = try targets.sorted { $0.agreementKeyThumbprint < $1.agreementKeyThumbprint }.map {
            try TeamFrozenDeliveryTarget(userId: $0.accountID, deviceId: $0.deviceID,
                enrollmentId: $0.enrollmentID,
                agreementKeyThumbprint: $0.agreementKeyThumbprint)
        }
        let created: Int64 = 1_800_000_000_000
        let reservation = TeamDeliverySubmissionReservation(deliveryId: intent.deliveryId,
            state: .reserved, createdAt: created, reservationExpiresAt: created + 900_000,
            membershipRevision: intent.membershipRevision, audienceDigest: intent.audienceDigest,
            intentSha256: sha256Hex(request.body),
            jweBytes: intent.jweBytes, jweSha256: intent.jweSha256,
            objectId: intent.jweSha256, targets: frozen)
        return (request, binding, audience, reservation, created + 1)
    }

    @Test func androidServerIntentVectorPinsExactJWEAndMetadata() throws {
        let vector = try fixture("team-delivery-submit-intent-v1",
                                 as: DeliverySubmitIntentVector.self)
        let jwe = try fixture("team-delivery-jwe-v1", as: SubmitIntentJWEVector.self).canonicalJwe
        let intent = try TeamDeliverySubmitIntentCodec.fromCanonicalJWE(
            deliveryId: vector.deliveryId, membershipRevision: vector.membershipRevision,
            audienceDigest: vector.audienceDigest, serialized: jwe)
        #expect(intent.jweBytes == vector.jweBytes)
        #expect(intent.jweSha256 == vector.jweSha256)
        #expect(intent.type == vector.type)
        #expect(Mirror(reflecting: intent).children.isEmpty)
        let encoded = try TeamDeliverySubmitIntentCodec.encode(intent)
        #expect(String(data: encoded, encoding: .ascii) == vector.canonicalIntentUtf8)
        #expect(base64URL(encoded) == vector.canonicalIntentBase64url)
        #expect(try TeamDeliverySubmitIntentCodec.decode(encoded,
            expectedDeliveryId: intent.deliveryId,
            expectedMembershipRevision: intent.membershipRevision,
            expectedAudienceDigest: intent.audienceDigest) == intent)
        try intent.verifyCanonicalJWE(jwe)
    }

    @Test func changedJWEOrExpectedAuthorityBindingsFailClosed() throws {
        let vector = try fixture("team-delivery-submit-intent-v1",
                                 as: DeliverySubmitIntentVector.self)
        let jwe = try fixture("team-delivery-jwe-v1", as: SubmitIntentJWEVector.self).canonicalJwe
        let intent = try TeamDeliverySubmitIntentCodec.fromCanonicalJWE(
            deliveryId: vector.deliveryId, membershipRevision: vector.membershipRevision,
            audienceDigest: vector.audienceDigest, serialized: jwe)
        #expect(throws: TeamDeliverySubmitIntentError.jweMismatch) {
            try intent.verifyCanonicalJWE(jwe + " ")
        }
        let firstV = try #require(jwe.firstIndex(of: "v"))
        var changedJWE = jwe
        changedJWE.replaceSubrange(firstV...firstV, with: "w")
        #expect(throws: TeamDeliverySubmitIntentError.jweMismatch) {
            try intent.verifyCanonicalJWE(changedJWE)
        }
        let encoded = try TeamDeliverySubmitIntentCodec.encode(intent)
        #expect(throws: TeamDeliverySubmitIntentError.bindingMismatch) {
            try TeamDeliverySubmitIntentCodec.decode(encoded,
                expectedDeliveryId: "other_delivery",
                expectedMembershipRevision: intent.membershipRevision,
                expectedAudienceDigest: intent.audienceDigest)
        }
        #expect(throws: TeamDeliverySubmitIntentError.bindingMismatch) {
            try TeamDeliverySubmitIntentCodec.decode(encoded,
                expectedDeliveryId: intent.deliveryId,
                expectedMembershipRevision: intent.membershipRevision + 1,
                expectedAudienceDigest: intent.audienceDigest)
        }
        #expect(throws: TeamDeliverySubmitIntentError.bindingMismatch) {
            try TeamDeliverySubmitIntentCodec.decode(encoded,
                expectedDeliveryId: intent.deliveryId,
                expectedMembershipRevision: intent.membershipRevision,
                expectedAudienceDigest: String(repeating: "A", count: 43))
        }
    }

    @Test func extensionsReorderingAndAlternateNumbersAreNotCanonical() throws {
        let vector = try fixture("team-delivery-submit-intent-v1",
                                 as: DeliverySubmitIntentVector.self)
        let canonical = vector.canonicalIntentUtf8
        let changed = [canonical + " ",
            canonical.replacingOccurrences(of: "\"jweBytes\":1403",
                                             with: "\"jweBytes\":1403.0"),
            canonical.replacingOccurrences(of: "\"membershipRevision\":7",
                                             with: "\"membershipRevision\":7.0"),
            canonical.replacingOccurrences(of: "{\"audienceDigest\"",
                                             with: "{\"extra\":0,\"audienceDigest\""),
            canonical.replacingOccurrences(
                of: "\"audienceDigest\":\"\(vector.audienceDigest)\",\"deliveryId\":\"\(vector.deliveryId)\"",
                with: "\"deliveryId\":\"\(vector.deliveryId)\",\"audienceDigest\":\"\(vector.audienceDigest)\""),
            "\u{feff}" + canonical]
        for value in changed {
            #expect(throws: (any Error).self) {
                try TeamDeliverySubmitIntentCodec.decode(Data(value.utf8),
                    expectedDeliveryId: vector.deliveryId,
                    expectedMembershipRevision: vector.membershipRevision,
                    expectedAudienceDigest: vector.audienceDigest)
            }
        }
    }

    @Test func authenticatedReservationPinsExactSubmitProofAudienceAndJWE() throws {
        let (request, binding, audience, reservation, receivedAt) = try reservationFixture()
        let result = try TeamDeliveryReservationValidator.validate(reservation,
            expectedBinding: binding, request: request,
            expectedAudience: audience, receivedAt: receivedAt)
        #expect(result == reservation)
        #expect(result.targets.map(\.agreementKeyThumbprint)
            == result.targets.map(\.agreementKeyThumbprint).sorted())
        #expect(request.body == (try TeamDeliverySubmitIntentCodec.encode(request.intent)))
        #expect(Mirror(reflecting: request).children.isEmpty)
        #expect(Mirror(reflecting: result).children.isEmpty)
        #expect(TeamDeliveryReservationState.allCases.count == 10)
    }

    @Test func reservationRejectsChangedIdentityMetadataTargetsLifetimeAndCiphertext() throws {
        let (request, binding, audience, reservation, receivedAt) = try reservationFixture()
        func changed(deliveryId: String? = nil,
                     state: TeamDeliveryReservationState? = nil,
                     createdAt: Int64? = nil, reservationExpiresAt: Int64? = nil,
                     membershipRevision: Int64? = nil, audienceDigest: String? = nil,
                     intentSha256: String? = nil, jweBytes: Int? = nil,
                     jweSha256: String? = nil, objectId: String? = nil,
                     targets: [TeamFrozenDeliveryTarget]? = nil)
            -> TeamDeliverySubmissionReservation {
            .init(deliveryId: deliveryId ?? reservation.deliveryId,
                state: state ?? reservation.state,
                createdAt: createdAt ?? reservation.createdAt,
                reservationExpiresAt: reservationExpiresAt ?? reservation.reservationExpiresAt,
                membershipRevision: membershipRevision ?? reservation.membershipRevision,
                audienceDigest: audienceDigest ?? reservation.audienceDigest,
                intentSha256: intentSha256 ?? reservation.intentSha256,
                jweBytes: jweBytes ?? reservation.jweBytes,
                jweSha256: jweSha256 ?? reservation.jweSha256,
                objectId: objectId ?? reservation.objectId,
                targets: targets ?? reservation.targets)
        }
        let bad = [
            changed(deliveryId: "other_delivery"),
            changed(reservationExpiresAt: reservation.createdAt),
            changed(reservationExpiresAt: reservation.createdAt + 900_001),
            changed(membershipRevision: reservation.membershipRevision + 1),
            changed(audienceDigest: String(repeating: "A", count: 43)),
            changed(intentSha256: String(repeating: "a", count: 64)),
            changed(jweBytes: reservation.jweBytes + 1),
            changed(jweSha256: String(repeating: "b", count: 64)),
            changed(objectId: "other_object"),
            changed(targets: Array(reservation.targets.reversed())),
        ]
        for value in bad {
            #expect(throws: TeamDeliveryReservationError.invalidReservation) {
                try TeamDeliveryReservationValidator.validate(value,
                    expectedBinding: binding, request: request,
                    expectedAudience: audience, receivedAt: receivedAt)
            }
        }
        #expect(throws: TeamDeliveryReservationError.invalidReservation) {
            try TeamDeliveryReservationValidator.validate(reservation,
                expectedBinding: binding, request: request,
                expectedAudience: audience,
                receivedAt: reservation.reservationExpiresAt)
        }
        let wrongOperation = TeamDeviceRequestWire.Binding(audience: binding.audience,
            authorityEpoch: binding.authorityEpoch, accountID: binding.accountID,
            sessionID: binding.sessionID, deviceID: binding.deviceID,
            enrollmentID: binding.enrollmentID, keyThumbprint: binding.keyThumbprint,
            operation: .teamAudience, teamID: binding.teamID,
            requestID: binding.requestID, accessExpiresAt: binding.accessExpiresAt)
        #expect(throws: TeamDeliveryReservationError.bindingMismatch) {
            try TeamDeliveryReservationValidator.validate(reservation,
                expectedBinding: wrongOperation, request: request,
                expectedAudience: audience, receivedAt: receivedAt)
        }
        let canonical = try #require(String(data: request.jwe, encoding: .ascii))
        #expect(throws: TeamDeliveryReservationError.invalidRequest) {
            try TeamDeliveryReservationRequest(intent: request.intent,
                canonicalJWE: canonical + " ")
        }
    }
}
