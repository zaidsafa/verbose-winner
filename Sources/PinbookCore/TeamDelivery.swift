import CryptoKit
import Foundation

/// Errors deliberately omit content, identifiers, hashes and underlying SQL text.
public enum TeamDeliveryError: Error, Equatable {
    case invalidIdentifier, invalidTime, invalidTargets, invalidScope
    case unsupportedVersion, invalidBody, checksumMismatch, unsupportedMedia
    case immutableConflict, queueFull, invalidLimit, storage(Int32), unsupportedSchema
}

public enum TeamDeliveryRules {
    public static let protocolVersion = 1
    public static let retentionMilliseconds: Int64 = 2_592_000_000
    public static let maximumTextBytes = 32 * 1024
    public static let maximumRecipients = 10

    public static func expiresAt(acceptedAt: Int64) throws -> Int64 {
        guard acceptedAt >= 0, acceptedAt <= Int64.max - retentionMilliseconds else {
            throw TeamDeliveryError.invalidTime
        }
        return acceptedAt + retentionMilliseconds
    }

    public static func textSHA256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func requireID(_ value: String) throws {
        guard (1...128).contains(value.utf8.count), value.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || $0 == 45 || $0 == 95
        }) else { throw TeamDeliveryError.invalidIdentifier }
    }

    // Frozen Kotlin Char.isWhitespace parity, not locale-dependent trimming.
    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            switch $0.value {
            case 0x09...0x0D, 0x1C...0x20, 0xA0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: true
            default: false
            }
        }
    }
}

public struct DeliveryTarget: Codable, Hashable, Sendable {
    public let userId: String
    public let deviceId: String
    public let enrollmentId: String

    public init(userId: String, deviceId: String, enrollmentId: String) throws {
        try TeamDeliveryRules.requireID(userId)
        try TeamDeliveryRules.requireID(deviceId)
        try TeamDeliveryRules.requireID(enrollmentId)
        self.userId = userId
        self.deviceId = deviceId
        self.enrollmentId = enrollmentId
    }

    func validate() throws {
        try TeamDeliveryRules.requireID(userId)
        try TeamDeliveryRules.requireID(deviceId)
        try TeamDeliveryRules.requireID(enrollmentId)
    }
}

public enum PayloadDeletionReason: String, Sendable {
    case allRecipientsSettled = "ALL_RECIPIENTS_SETTLED"
    case expired = "EXPIRED"
}

/// Server-policy reference only. Never deletes an on-device archive or authenticates an ACK.
public struct DeliveryRetention: Sendable {
    public let acceptedAt: Int64
    public let expiresAt: Int64
    public let targets: Set<DeliveryTarget>

    public init(acceptedAt: Int64, targets: Set<DeliveryTarget>, authorUserId: String) throws {
        try TeamDeliveryRules.requireID(authorUserId)
        for target in targets { try target.validate() }
        guard (1...TeamDeliveryRules.maximumRecipients).contains(targets.count),
              Set(targets.map(\.userId)).count == targets.count,
              Set(targets.map(\.deviceId)).count == targets.count,
              Set(targets.map(\.enrollmentId)).count == targets.count,
              !targets.contains(where: { $0.userId == authorUserId }) else {
            throw TeamDeliveryError.invalidTargets
        }
        self.acceptedAt = acceptedAt
        self.expiresAt = try TeamDeliveryRules.expiresAt(acceptedAt: acceptedAt)
        self.targets = targets
    }

    /// Caller supplies server-verified decisions; cancellation remains distinct from acknowledgement.
    public func deletionReason(serverNow: Int64, acknowledged: Set<DeliveryTarget>,
                               cancelled: Set<DeliveryTarget> = []) throws -> PayloadDeletionReason? {
        guard serverNow >= acceptedAt else { throw TeamDeliveryError.invalidTime }
        guard acknowledged.isSubset(of: targets), cancelled.isSubset(of: targets),
              acknowledged.isDisjoint(with: cancelled) else {
            throw TeamDeliveryError.invalidTargets
        }
        if serverNow >= expiresAt { return .expired }
        return acknowledged.union(cancelled).isSuperset(of: targets) ? .allRecipientsSettled : nil
    }
}

/// Decrypted LOCAL object, not a wire format. Authentication/decryption are future gates.
public struct TeamNoteEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let teamId: String
    public let deliveryId: String
    public let noteId: String
    public let authorUserId: String
    public let recipient: DeliveryTarget
    public let body: String
    public let bodySha256: String
    public let acceptedAt: Int64
    public let expiresAt: Int64
    public let attachmentCount: Int

    public init(protocolVersion: Int, teamId: String, deliveryId: String, noteId: String,
                authorUserId: String, recipient: DeliveryTarget, body: String, bodySha256: String,
                acceptedAt: Int64, expiresAt: Int64, attachmentCount: Int) {
        self.protocolVersion = protocolVersion
        self.teamId = teamId
        self.deliveryId = deliveryId
        self.noteId = noteId
        self.authorUserId = authorUserId
        self.recipient = recipient
        self.body = body
        self.bodySha256 = bodySha256
        self.acceptedAt = acceptedAt
        self.expiresAt = expiresAt
        self.attachmentCount = attachmentCount
    }

    public func validate(for target: DeliveryTarget, expectedTeamId: String) throws {
        guard protocolVersion == TeamDeliveryRules.protocolVersion else {
            throw TeamDeliveryError.unsupportedVersion
        }
        for id in [teamId, deliveryId, noteId, authorUserId, expectedTeamId] {
            try TeamDeliveryRules.requireID(id)
        }
        try recipient.validate()
        try target.validate()
        guard recipient == target, teamId == expectedTeamId, authorUserId != recipient.userId else {
            throw TeamDeliveryError.invalidScope
        }
        guard !TeamDeliveryRules.isBlank(body), body.utf8.count <= TeamDeliveryRules.maximumTextBytes else {
            throw TeamDeliveryError.invalidBody
        }
        guard bodySha256 == TeamDeliveryRules.textSHA256(body) else {
            throw TeamDeliveryError.checksumMismatch
        }
        guard expiresAt == (try TeamDeliveryRules.expiresAt(acceptedAt: acceptedAt)) else {
            throw TeamDeliveryError.invalidTime
        }
        guard attachmentCount == 0 else { throw TeamDeliveryError.unsupportedMedia }
    }

    /// Bounded, strict UTF-8 JSON input for local fixtures/future decrypted payload handling.
    /// It is deliberately not exposed as an authenticated network receive API.
    public static func decodeLocalJSON(_ data: Data) throws -> Self {
        guard data.count <= 256 * 1024, String(data: data, encoding: .utf8) != nil else {
            throw TeamDeliveryError.invalidBody
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
