import CryptoKit
import Foundation

enum TeamAgreementPossessionError: Error, Equatable {
    case invalidInput
}

/// Frozen application-specific agreement-private-key proof. This is not JWE,
/// device attestation, transport activation, or a general group protocol.
enum TeamAgreementPossession {
    static let purpose = "pinbook-agreement-possession-v1"
    static let algorithm = "pinbook-agreement-confirm-v1"

    static func confirmation(key: Data, requestMessage: Data,
                             agreementKeyThumbprint: String,
                             serverKeyThumbprint: String) throws -> Data {
        guard key.count == 32, (1...4096).contains(requestMessage.count),
              TeamAuthWire.credential(agreementKeyThumbprint),
              TeamAuthWire.credential(serverKeyThumbprint),
              agreementKeyThumbprint != serverKeyThumbprint else {
            throw TeamAgreementPossessionError.invalidInput
        }
        let encoded = TeamDeviceEnrollmentWire.encode(requestMessage)
        guard let message = try? JSONSerialization.data(withJSONObject: [purpose, encoded,
            agreementKeyThumbprint, serverKeyThumbprint], options: [.withoutEscapingSlashes]),
              message.count <= 8 * 1024 else {
            throw TeamAgreementPossessionError.invalidInput
        }
        var mutable = message
        defer { mutable.resetBytes(in: mutable.startIndex..<mutable.endIndex) }
        return Data(HMAC<SHA256>.authenticationCode(for: mutable, using: SymmetricKey(data: key)))
    }
}
