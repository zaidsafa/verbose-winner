import CoreFoundation
import Foundation

enum TeamDeliveryPayloadError: Error, Equatable {
    case invalidInput
    case invalidPayload
    case bindingMismatch
}

/// The only plaintext currently accepted inside a team-delivery JWE.
/// Server acceptance time and recipient authority deliberately remain outside it.
struct TeamDeliveryPayload: Equatable, Sendable, CustomStringConvertible,
                            CustomDebugStringConvertible, CustomReflectable {
    let teamId: String
    let deliveryId: String
    let noteId: String
    let authorUserId: String
    let body: String
    let bodySha256: String
    let attachmentCount: Int

    init(teamId: String, deliveryId: String, noteId: String, authorUserId: String,
         body: String, bodySha256: String, attachmentCount: Int = 0) {
        self.teamId = teamId
        self.deliveryId = deliveryId
        self.noteId = noteId
        self.authorUserId = authorUserId
        self.body = body
        self.bodySha256 = bodySha256
        self.attachmentCount = attachmentCount
    }

    var description: String { "TeamDeliveryPayload(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func localEnvelope(target: DeliveryTarget, acceptedAt: Int64,
                       expiresAt: Int64) throws -> TeamNoteEnvelope {
        try TeamDeliveryPayloadCodec.validate(self)
        guard expiresAt == (try TeamDeliveryRules.expiresAt(acceptedAt: acceptedAt)) else {
            throw TeamDeliveryPayloadError.bindingMismatch
        }
        let result = TeamNoteEnvelope(protocolVersion: TeamDeliveryRules.protocolVersion,
            teamId: teamId, deliveryId: deliveryId, noteId: noteId,
            authorUserId: authorUserId, recipient: target, body: body,
            bodySha256: bodySha256, acceptedAt: acceptedAt, expiresAt: expiresAt,
            attachmentCount: attachmentCount)
        do { try result.validate(for: target, expectedTeamId: teamId) }
        catch { throw TeamDeliveryPayloadError.bindingMismatch }
        return result
    }
}

enum TeamDeliveryPayloadCodec {
    static let type = "pinbook-team-note-v1"
    static let maximumPlaintextBytes = 45 * 1024

    static func validate(_ value: TeamDeliveryPayload) throws {
        do {
            for id in [value.teamId, value.deliveryId, value.noteId, value.authorUserId] {
                try TeamDeliveryRules.requireID(id)
            }
        } catch { throw TeamDeliveryPayloadError.invalidInput }
        guard !TeamDeliveryRules.isBlank(value.body),
              value.body.utf8.count <= TeamDeliveryRules.maximumTextBytes,
              value.bodySha256.utf8.count == 64,
              value.bodySha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              value.bodySha256 == TeamDeliveryRules.textSHA256(value.body),
              value.attachmentCount == 0 else {
            throw TeamDeliveryPayloadError.invalidInput
        }
    }

    static func encode(_ value: TeamDeliveryPayload) throws -> Data {
        try validate(value)
        var body = Data(value.body.utf8)
        defer { body.resetBytes(in: body.startIndex..<body.endIndex) }
        let text = "[\"\(type)\",\"\(value.teamId)\",\"\(value.deliveryId)\"," +
            "\"\(value.noteId)\",\"\(value.authorUserId)\",\"\(base64URL(body))\"," +
            "\"\(value.bodySha256)\",0]"
        let result = Data(text.utf8)
        guard (1...maximumPlaintextBytes).contains(result.count) else {
            throw TeamDeliveryPayloadError.invalidInput
        }
        return result
    }

    static func decode(_ bytes: Data, expectedTeamId: String,
                       expectedDeliveryId: String,
                       expectedAuthorUserId: String) throws -> TeamDeliveryPayload {
        guard (1...maximumPlaintextBytes).contains(bytes.count),
              !bytes.starts(with: [0xef, 0xbb, 0xbf]) else {
            throw TeamDeliveryPayloadError.invalidPayload
        }
        do {
            try TeamDeliveryRules.requireID(expectedTeamId)
            try TeamDeliveryRules.requireID(expectedDeliveryId)
            try TeamDeliveryRules.requireID(expectedAuthorUserId)
        } catch { throw TeamDeliveryPayloadError.invalidInput }
        let values: [Any]
        do {
            values = try TeamStrictJSON.array(bytes, maximumBytes: maximumPlaintextBytes,
                                               maximumDepth: 1)
        } catch { throw TeamDeliveryPayloadError.invalidPayload }
        guard values.count == 8,
              values[0] as? String == type,
              let teamId = values[1] as? String,
              let deliveryId = values[2] as? String,
              let noteId = values[3] as? String,
              let authorUserId = values[4] as? String,
              let encodedBody = values[5] as? String,
              let bodySha256 = values[6] as? String,
              let attachment = values[7] as? NSNumber,
              CFGetTypeID(attachment) != CFBooleanGetTypeID(),
              attachment.int64Value == 0,
              var bodyBytes = decodeBody(encodedBody) else {
            throw TeamDeliveryPayloadError.invalidPayload
        }
        defer { bodyBytes.resetBytes(in: bodyBytes.startIndex..<bodyBytes.endIndex) }
        guard let body = String(data: bodyBytes, encoding: .utf8) else {
            throw TeamDeliveryPayloadError.invalidPayload
        }
        let result = TeamDeliveryPayload(teamId: teamId, deliveryId: deliveryId,
            noteId: noteId, authorUserId: authorUserId, body: body,
            bodySha256: bodySha256, attachmentCount: 0)
        do { try validate(result) }
        catch { throw TeamDeliveryPayloadError.invalidPayload }
        guard result.teamId == expectedTeamId,
              result.deliveryId == expectedDeliveryId,
              result.authorUserId == expectedAuthorUserId else {
            throw TeamDeliveryPayloadError.bindingMismatch
        }
        var canonical = try encode(result)
        defer { canonical.resetBytes(in: canonical.startIndex..<canonical.endIndex) }
        guard canonical == bytes else { throw TeamDeliveryPayloadError.invalidPayload }
        return result
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBody(_ value: String) -> Data? {
        guard value.utf8.count <= (TeamDeliveryRules.maximumTextBytes * 4 + 2) / 3,
              value.utf8.allSatisfy(TeamAuthWire.urlByte) else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let body = Data(base64Encoded: padded),
              body.count <= TeamDeliveryRules.maximumTextBytes,
              base64URL(body) == value else { return nil }
        return body
    }
}
