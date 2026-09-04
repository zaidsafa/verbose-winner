import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class DeliveryPayloadFixtureBundleMarker: NSObject {}

private struct DeliveryPayloadVector: Decodable {
    let teamId: String
    let deliveryId: String
    let noteId: String
    let authorUserId: String
    let body: String
    let bodySha256: String
    let attachmentCount: Int
    let canonicalPayloadUtf8: String
    let canonicalPayloadBase64url: String
}

struct TeamDeliveryPayloadTests {
    private func fixture() throws -> DeliveryPayloadVector {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: DeliveryPayloadFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: "team-delivery-payload-v1",
            withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(DeliveryPayloadVector.self, from: Data(contentsOf: url))
    }

    private func value(_ fixture: DeliveryPayloadVector) -> TeamDeliveryPayload {
        TeamDeliveryPayload(teamId: fixture.teamId, deliveryId: fixture.deliveryId,
            noteId: fixture.noteId, authorUserId: fixture.authorUserId,
            body: fixture.body, bodySha256: fixture.bodySha256,
            attachmentCount: fixture.attachmentCount)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    @Test func androidServerPayloadVectorRoundTripsAndBuildsLocalEnvelope() throws {
        let fixture = try fixture()
        let payload = value(fixture)
        let encoded = try TeamDeliveryPayloadCodec.encode(payload)
        #expect(String(data: encoded, encoding: .utf8) == fixture.canonicalPayloadUtf8)
        #expect(base64URL(encoded) == fixture.canonicalPayloadBase64url)
        let decoded = try TeamDeliveryPayloadCodec.decode(encoded,
            expectedTeamId: fixture.teamId, expectedDeliveryId: fixture.deliveryId,
            expectedAuthorUserId: fixture.authorUserId)
        #expect(decoded == payload)
        #expect(Mirror(reflecting: decoded).children.isEmpty)
        let target = try DeliveryTarget(userId: "recipient_fixture",
            deviceId: "device_fixture", enrollmentId: "enrollment_fixture")
        let envelope = try decoded.localEnvelope(target: target, acceptedAt: 1_000,
                                                   expiresAt: 2_592_001_000)
        #expect(envelope.recipient == target)
        #expect(envelope.body == payload.body)
        #expect(envelope.noteId == payload.noteId)
    }

    @Test func expectedBindingsDigestAndServerTimesFailClosed() throws {
        let fixture = try fixture()
        let payload = value(fixture)
        let encoded = try TeamDeliveryPayloadCodec.encode(payload)
        for (team, delivery, author) in [
            ("other_team", payload.deliveryId, payload.authorUserId),
            (payload.teamId, "other_delivery", payload.authorUserId),
            (payload.teamId, payload.deliveryId, "other_author")
        ] {
            #expect(throws: TeamDeliveryPayloadError.bindingMismatch) {
                try TeamDeliveryPayloadCodec.decode(encoded, expectedTeamId: team,
                    expectedDeliveryId: delivery, expectedAuthorUserId: author)
            }
        }
        let changed = TeamDeliveryPayload(teamId: payload.teamId,
            deliveryId: payload.deliveryId, noteId: payload.noteId,
            authorUserId: payload.authorUserId, body: payload.body,
            bodySha256: String(repeating: "0", count: 64))
        #expect(throws: TeamDeliveryPayloadError.invalidInput) {
            try TeamDeliveryPayloadCodec.encode(changed)
        }
        let target = try DeliveryTarget(userId: "recipient_fixture",
            deviceId: "device_fixture", enrollmentId: "enrollment_fixture")
        #expect(throws: TeamDeliveryPayloadError.bindingMismatch) {
            try payload.localEnvelope(target: target, acceptedAt: 1_000,
                                      expiresAt: 2_592_001_001)
        }
    }

    @Test func noncanonicalExtendedAndMalformedPayloadsFailClosed() throws {
        let fixture = try fixture()
        let canonical = fixture.canonicalPayloadUtf8
        let body64 = base64URL(Data(fixture.body.utf8))
        let mutations = [canonical + " ",
            canonical.replacingOccurrences(of: ",0]", with: ",0.0]"),
            canonical.replacingOccurrences(of: ",0]", with: ",1]"),
            canonical.replacingOccurrences(of: body64, with: body64 + "="),
            canonical.replacingOccurrences(of: "\"\(fixture.noteId)\"",
                with: "\"\(fixture.noteId)\",\"extra\""),
            "\u{feff}" + canonical]
        for changed in mutations {
            #expect(throws: (any Error).self) {
                try TeamDeliveryPayloadCodec.decode(Data(changed.utf8),
                    expectedTeamId: fixture.teamId,
                    expectedDeliveryId: fixture.deliveryId,
                    expectedAuthorUserId: fixture.authorUserId)
            }
        }
        let malformed = "[\"pinbook-team-note-v1\",\"\(fixture.teamId)\"," +
            "\"\(fixture.deliveryId)\",\"\(fixture.noteId)\",\"\(fixture.authorUserId)\"," +
            "\"wyg\",\"\(fixture.bodySha256)\",0]"
        #expect(throws: TeamDeliveryPayloadError.invalidPayload) {
            try TeamDeliveryPayloadCodec.decode(Data(malformed.utf8),
                expectedTeamId: fixture.teamId, expectedDeliveryId: fixture.deliveryId,
                expectedAuthorUserId: fixture.authorUserId)
        }
    }

    @Test func bodyAndSerializedSizesAreStrictlyBounded() throws {
        let fixture = try fixture()
        let maximum = String(repeating: "a", count: TeamDeliveryRules.maximumTextBytes)
        let maximumValue = TeamDeliveryPayload(teamId: fixture.teamId,
            deliveryId: fixture.deliveryId, noteId: fixture.noteId,
            authorUserId: fixture.authorUserId, body: maximum,
            bodySha256: TeamDeliveryRules.textSHA256(maximum))
        let encoded = try TeamDeliveryPayloadCodec.encode(maximumValue)
        #expect(encoded.count <= TeamDeliveryPayloadCodec.maximumPlaintextBytes)
        #expect(try TeamDeliveryPayloadCodec.decode(encoded,
            expectedTeamId: fixture.teamId, expectedDeliveryId: fixture.deliveryId,
            expectedAuthorUserId: fixture.authorUserId) == maximumValue)
        let oversized = maximum + "a"
        let oversizedValue = TeamDeliveryPayload(teamId: fixture.teamId,
            deliveryId: fixture.deliveryId, noteId: fixture.noteId,
            authorUserId: fixture.authorUserId, body: oversized,
            bodySha256: TeamDeliveryRules.textSHA256(oversized))
        #expect(throws: TeamDeliveryPayloadError.invalidInput) {
            try TeamDeliveryPayloadCodec.encode(oversizedValue)
        }
        #expect(throws: TeamDeliveryPayloadError.invalidPayload) {
            try TeamDeliveryPayloadCodec.decode(Data(repeating: 32,
                count: TeamDeliveryPayloadCodec.maximumPlaintextBytes + 1),
                expectedTeamId: fixture.teamId, expectedDeliveryId: fixture.deliveryId,
                expectedAuthorUserId: fixture.authorUserId)
        }
    }
}
