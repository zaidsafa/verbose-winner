import CryptoKit
import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct TeamDeliveryCryptoPrimitivesTests {
    private func hex(_ value: String) throws -> Data {
        guard value.count.isMultiple(of: 2) else { throw TeamDeliveryCryptoError.invalidInput }
        var result = Data(); result.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else {
                throw TeamDeliveryCryptoError.invalidInput
            }
            result.append(byte); index = end
        }
        return result
    }

    @Test func rfc7518AppendixCConcatKDFVector() throws {
        let secret = Data([158, 86, 217, 29, 129, 113, 53, 211, 114, 131, 66, 131,
            191, 132, 38, 156, 251, 49, 110, 163, 218, 128, 106, 72, 246, 218, 167,
            121, 140, 254, 144, 196])
        let derived = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: secret,
            algorithm: "A128GCM", partyU: Data("Alice".utf8), partyV: Data("Bob".utf8), bits: 128)
        #expect(derived == (try hex("56aa8deaf8236d205c2228cd71a7101a")))
    }

    @Test func rfc3394Section46A256WrapVectorAndIntegrity() throws {
        var kek = try hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        var key = try hex("00112233445566778899aabbccddeeff000102030405060708090a0b0c0d0e0f")
        var expected = try hex("28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326cbc7f0e71a99f43bfb988b9b7a02dd21")
        defer {
            kek.resetBytes(in: kek.startIndex..<kek.endIndex)
            key.resetBytes(in: key.startIndex..<key.endIndex)
            expected.resetBytes(in: expected.startIndex..<expected.endIndex)
        }
        #expect(try TeamDeliveryCryptoPrimitives.wrapA256(kek: kek, key: key) == expected)
        #expect(try TeamDeliveryCryptoPrimitives.unwrapA256(kek: kek, wrapped: expected) == key)
        expected[20] ^= 1
        #expect(throws: TeamDeliveryCryptoError.integrityFailure) {
            try TeamDeliveryCryptoPrimitives.unwrapA256(kek: kek, wrapped: expected)
        }
    }

    @Test func independentP256AgreementsDeriveSameWrappingKey() throws {
        let sender = P256.KeyAgreement.PrivateKey(), recipient = P256.KeyAgreement.PrivateKey()
        var firstSecret = try sender.sharedSecretFromKeyAgreement(with: recipient.publicKey)
            .withUnsafeBytes { Data($0) }
        var secondSecret = try recipient.sharedSecretFromKeyAgreement(with: sender.publicKey)
            .withUnsafeBytes { Data($0) }
        var first = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: firstSecret,
            algorithm: "ECDH-ES+A256KW", partyU: Data("delivery".utf8),
            partyV: Data("recipient".utf8), bits: 256)
        var second = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: secondSecret,
            algorithm: "ECDH-ES+A256KW", partyU: Data("delivery".utf8),
            partyV: Data("recipient".utf8), bits: 256)
        var contentKey = Data((0..<32).map(UInt8.init))
        defer {
            firstSecret.resetBytes(in: firstSecret.startIndex..<firstSecret.endIndex)
            secondSecret.resetBytes(in: secondSecret.startIndex..<secondSecret.endIndex)
            first.resetBytes(in: first.startIndex..<first.endIndex)
            second.resetBytes(in: second.startIndex..<second.endIndex)
            contentKey.resetBytes(in: contentKey.startIndex..<contentKey.endIndex)
        }
        let wrapped = try TeamDeliveryCryptoPrimitives.wrapA256(kek: first, key: contentKey)
        #expect(first == second)
        #expect(Data(wrapped.dropFirst(8).prefix(32)) != contentKey)
        #expect(try TeamDeliveryCryptoPrimitives.unwrapA256(kek: second, wrapped: wrapped) == contentKey)
    }

    @Test func boundsRefuseUnsupportedInputs() {
        #expect(throws: TeamDeliveryCryptoError.invalidInput) {
            try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: Data(), algorithm: "A256KW",
                partyU: Data(), partyV: Data(), bits: 256)
        }
        #expect(throws: TeamDeliveryCryptoError.invalidInput) {
            try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: Data([1]), algorithm: "bad\n",
                partyU: Data(), partyV: Data(), bits: 256)
        }
        #expect(throws: TeamDeliveryCryptoError.invalidInput) {
            try TeamDeliveryCryptoPrimitives.wrapA256(kek: Data(repeating: 0, count: 16),
                key: Data(repeating: 0, count: 32))
        }
        #expect(throws: TeamDeliveryCryptoError.invalidInput) {
            try TeamDeliveryCryptoPrimitives.unwrapA256(kek: Data(repeating: 0, count: 32),
                wrapped: Data(repeating: 0, count: 16))
        }
    }
}
