import CryptoKit
import Foundation

enum TeamDeliveryCryptoError: Error, Equatable {
    case invalidInput
    case integrityFailure
}

/// RFC 7518 Concat KDF and RFC 3394 AES Key Wrap primitives only.
/// No key generation, custody, envelope, transport or runtime activation.
enum TeamDeliveryCryptoPrimitives {
    static func concatKDF(sharedSecret: Data, algorithm: String, partyU: Data,
                          partyV: Data, bits: Int) throws -> Data {
        var algorithmBytes = Data(algorithm.utf8)
        defer { algorithmBytes.resetBytes(in: algorithmBytes.startIndex..<algorithmBytes.endIndex) }
        guard (1...132).contains(sharedSecret.count),
              (1...64).contains(algorithmBytes.count),
              algorithmBytes.allSatisfy({ (0x21...0x7e).contains($0) }),
              partyU.count <= 512, partyV.count <= 512,
              [128, 192, 256].contains(bits) else {
            throw TeamDeliveryCryptoError.invalidInput
        }
        var input = Data()
        input.reserveCapacity(4 + sharedSecret.count + 4 + algorithmBytes.count
            + 4 + partyU.count + 4 + partyV.count + 4)
        append(1, to: &input)
        input.append(sharedSecret)
        append(UInt32(algorithmBytes.count), to: &input)
        input.append(algorithmBytes)
        append(UInt32(partyU.count), to: &input)
        input.append(partyU)
        append(UInt32(partyV.count), to: &input)
        input.append(partyV)
        append(UInt32(bits), to: &input)
        defer { input.resetBytes(in: input.startIndex..<input.endIndex) }
        return Data(SHA256.hash(data: input).prefix(bits / 8))
    }

    static func wrapA256(kek: Data, key: Data) throws -> Data {
        guard kek.count == 32, key.count >= 16, key.count.isMultiple(of: 8) else {
            throw TeamDeliveryCryptoError.invalidInput
        }
        do {
            return try AES.KeyWrap.wrap(SymmetricKey(data: key), using: SymmetricKey(data: kek))
        } catch {
            throw TeamDeliveryCryptoError.invalidInput
        }
    }

    static func unwrapA256(kek: Data, wrapped: Data) throws -> Data {
        guard kek.count == 32, wrapped.count >= 24, wrapped.count.isMultiple(of: 8) else {
            throw TeamDeliveryCryptoError.invalidInput
        }
        do {
            let key = try AES.KeyWrap.unwrap(wrapped, using: SymmetricKey(data: kek))
            let result = key.withUnsafeBytes { Data($0) }
            guard result.count == wrapped.count - 8 else {
                throw TeamDeliveryCryptoError.integrityFailure
            }
            return result
        } catch let error as TeamDeliveryCryptoError {
            throw error
        } catch {
            throw TeamDeliveryCryptoError.integrityFailure
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
