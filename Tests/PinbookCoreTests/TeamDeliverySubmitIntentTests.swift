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

private struct SubmitIntentJWEVector: Decodable { let canonicalJwe: String }

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
}
