import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private final class DeliveryJournalFixtureBundleMarker: NSObject {}

private struct JournalSubmitIntentVector: Decodable {
    let audienceDigest: String
    let deliveryId: String
    let jweBytes: Int
    let jweSha256: String
    let membershipRevision: Int64
    let canonicalIntentUtf8: String
}

private struct JournalJWERecipient: Decodable { let kid: String }
private struct JournalJWEVector: Decodable { let recipients: [JournalJWERecipient] }

struct TeamDeliveryJournalEventTests {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: DeliveryJournalFixtureBundleMarker.self)
        #endif
        let url = try #require(bundle.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func accepted() throws -> TeamDeliveryAcceptedEvent {
        let vector = try fixture("team-delivery-submit-intent-v1",
                                 as: JournalSubmitIntentVector.self)
        let recipients = try fixture("team-delivery-jwe-v1", as: JournalJWEVector.self).recipients
        let intent = TeamDeliverySubmitIntent(audienceDigest: vector.audienceDigest,
            deliveryId: vector.deliveryId, jweBytes: vector.jweBytes,
            jweSha256: vector.jweSha256, membershipRevision: vector.membershipRevision,
            type: TeamDeliverySubmitIntentCodec.type)
        let targets = try [
            TeamFrozenDeliveryTarget(userId: "alice", deviceId: "alice_phone",
                enrollmentId: "alice_enrollment", agreementKeyThumbprint: recipients[0].kid),
            TeamFrozenDeliveryTarget(userId: "bob", deviceId: "bob_phone",
                enrollmentId: "bob_enrollment", agreementKeyThumbprint: recipients[1].kid),
        ]
        return try TeamDeliveryJournalEventCodec.accepted(intent: intent,
            canonicalIntent: Data(vector.canonicalIntentUtf8.utf8), teamId: "team_fixture",
            senderUserId: "author_fixture", senderDeviceId: "author_phone",
            senderEnrollmentId: "author_enrollment", authorityEpoch: "epoch_fixture",
            createdAt: 700, reservationExpiresAt: 1_100, writeStartedAt: 800,
            objectVerifiedAt: 900, acceptedAt: 1_000, targets: targets)
    }

    @Test func acceptedEventBindsExactIntentObjectAudienceAndDeadlines() throws {
        let event = try accepted()
        #expect(event.eventId == "accept-" + event.jweSha256)
        #expect(event.objectId == event.jweSha256)
        #expect(event.at == event.acceptedAt)
        #expect(event.expiresAt == 2_592_001_000)
        #expect(event.targets.map(\.agreementKeyThumbprint) ==
            event.targets.map(\.agreementKeyThumbprint).sorted())
        #expect(Mirror(reflecting: event).children.isEmpty)
        #expect(Mirror(reflecting: event.targets[0]).children.isEmpty)

        let data = try TeamDeliveryJournalEventCodec.canonicalData(event)
        let text = try #require(String(data: data, encoding: .ascii))
        let canonicalDigest = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        #expect(event.intentSha256 ==
            "b39a539699af95520162e09fe08ee4044e66bf80de3968ee24f356e043561ddf")
        #expect(data.count == 1_079)
        #expect(canonicalDigest ==
            "253037999a2c6122c96de38e1123f7b3923202670e98c418575d34f9f23a4a7f")
        #expect(text.hasPrefix("{\"acceptedAt\":1000,\"at\":1000,"))
        #expect(text.contains("\"eventId\":\"accept-" + event.jweSha256 + "\""))
        #expect(text.contains("\"intentSha256\":\"" + event.intentSha256 + "\""))
        #expect(text.contains("\"objectId\":\"" + event.jweSha256 + "\""))
        #expect(text.contains("\"agreementKeyThumbprint\":\"" +
            event.targets[0].agreementKeyThumbprint + "\""))
        #expect(text.hasSuffix("\"teamId\":\"team_fixture\",\"writeStartedAt\":800}"))
    }

    @Test func changedAcceptedMetadataFailsClosed() throws {
        let event = try accepted()
        let intent = TeamDeliverySubmitIntent(audienceDigest: event.audienceDigest,
            deliveryId: event.deliveryId, jweBytes: event.jweBytes,
            jweSha256: event.jweSha256, membershipRevision: event.membershipRevision,
            type: TeamDeliverySubmitIntentCodec.type)
        let intentBytes = try TeamDeliverySubmitIntentCodec.encode(intent)
        let changes: [(String, Int64, Int64, [TeamFrozenDeliveryTarget])] = [
            (event.senderUserId, event.reservationExpiresAt, event.writeStartedAt,
             Array(event.targets.reversed())),
            (event.senderUserId, event.reservationExpiresAt, event.acceptedAt + 1,
             event.targets),
            (event.targets[0].userId,
             event.createdAt + TeamDeliveryJournalEventCodec.maximumReservationMilliseconds + 1,
             event.writeStartedAt, event.targets),
        ]
        for change in changes {
            #expect(throws: TeamDeliveryJournalEventError.invalidInput) {
                try TeamDeliveryJournalEventCodec.accepted(intent: intent,
                    canonicalIntent: intentBytes, teamId: event.teamId,
                    senderUserId: change.0, senderDeviceId: event.senderDeviceId,
                    senderEnrollmentId: event.senderEnrollmentId,
                    authorityEpoch: event.authorityEpoch, createdAt: event.createdAt,
                    reservationExpiresAt: change.1, writeStartedAt: change.2,
                    objectVerifiedAt: event.objectVerifiedAt, acceptedAt: event.acceptedAt,
                    targets: change.3)
            }
        }

        let wrongAudience = TeamDeliverySubmitIntent(
            audienceDigest: String(repeating: "A", count: 43),
            deliveryId: intent.deliveryId, jweBytes: intent.jweBytes,
            jweSha256: intent.jweSha256, membershipRevision: intent.membershipRevision,
            type: intent.type)
        #expect(throws: TeamDeliveryJournalEventError.invalidInput) {
            try TeamDeliveryJournalEventCodec.accepted(intent: wrongAudience,
                canonicalIntent: TeamDeliverySubmitIntentCodec.encode(wrongAudience),
                teamId: event.teamId, senderUserId: event.senderUserId,
                senderDeviceId: event.senderDeviceId,
                senderEnrollmentId: event.senderEnrollmentId,
                authorityEpoch: event.authorityEpoch, createdAt: event.createdAt,
                reservationExpiresAt: event.reservationExpiresAt,
                writeStartedAt: event.writeStartedAt,
                objectVerifiedAt: event.objectVerifiedAt, acceptedAt: event.acceptedAt,
                targets: event.targets)
        }
    }

    @Test func canonicalIntentMismatchCannotCreateAcceptedEvent() throws {
        let event = try accepted()
        let intent = TeamDeliverySubmitIntent(audienceDigest: event.audienceDigest,
            deliveryId: event.deliveryId, jweBytes: event.jweBytes,
            jweSha256: event.jweSha256, membershipRevision: event.membershipRevision,
            type: TeamDeliverySubmitIntentCodec.type)
        #expect(throws: TeamDeliveryJournalEventError.bindingMismatch) {
            try TeamDeliveryJournalEventCodec.accepted(intent: intent,
                canonicalIntent: Data("{}".utf8), teamId: event.teamId,
                senderUserId: event.senderUserId, senderDeviceId: event.senderDeviceId,
                senderEnrollmentId: event.senderEnrollmentId,
                authorityEpoch: event.authorityEpoch, createdAt: event.createdAt,
                reservationExpiresAt: event.reservationExpiresAt,
                writeStartedAt: event.writeStartedAt, objectVerifiedAt: event.objectVerifiedAt,
                acceptedAt: event.acceptedAt, targets: event.targets)
        }
    }

    @Test func ackAndCancelFreezeAgreementThumbprint() throws {
        let target = try accepted().targets[0]
        let ack = try TeamDeliveryJournalEventCodec.acknowledgement(
            eventId: "ack_fixture", deliveryId: "delivery_fixture", at: 2_000, target: target)
        let cancel = try TeamDeliveryJournalEventCodec.cancellation(
            eventId: "cancel_fixture", deliveryId: "delivery_fixture", at: 2_001,
            target: target, actorUserId: "owner_fixture")
        for data in [try TeamDeliveryJournalEventCodec.canonicalData(ack),
                     try TeamDeliveryJournalEventCodec.canonicalData(cancel)] {
            let text = try #require(String(data: data, encoding: .ascii))
            #expect(text.contains("\"agreementKeyThumbprint\":\"" +
                target.agreementKeyThumbprint + "\""))
            #expect(!text.contains("publicKey"))
        }
        #expect(Mirror(reflecting: ack).children.isEmpty)
        #expect(Mirror(reflecting: cancel).children.isEmpty)
        #expect(String(data: try TeamDeliveryJournalEventCodec.canonicalData(cancel),
                       encoding: .ascii)?.contains("\"reason\":\"MEMBERSHIP_REMOVED\"") == true)
    }
}
