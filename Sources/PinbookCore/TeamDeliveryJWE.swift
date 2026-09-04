import CryptoKit
import Foundation
import Security

enum TeamDeliveryJWEError: Error, Equatable {
    case invalidInput
    case invalidEnvelope
    case integrityFailure
}

/// Strict RFC 7516 General JSON profile for one ciphertext and 1...9 agreement keys.
/// Inactive foundation only: no payload codec, transport, persistence, ACK or runtime route.
struct TeamDeliveryJWE {
    static let algorithm = "ECDH-ES+A256KW"
    static let encryption = "A256GCM"
    static let type = "pinbook-team-delivery+jwe"
    static let version = 1
    static let maximumPlaintextBytes = 64 * 1024
    static let maximumSerializedBytes = 100_000
    private static let partyU = Data("pinbook-team-delivery-v1".utf8)

    private let entropy: (Int) throws -> Data
    private let ephemeral: () throws -> P256.KeyAgreement.PrivateKey

    init(entropy: @escaping (Int) throws -> Data = Self.secureEntropy,
         ephemeral: @escaping () throws -> P256.KeyAgreement.PrivateKey = {
             P256.KeyAgreement.PrivateKey()
         }) {
        self.entropy = entropy
        self.ephemeral = ephemeral
    }

    func encrypt(_ plaintext: Data, recipients input: [TeamAgreementPublic]) throws -> String {
        guard (1...Self.maximumPlaintextBytes).contains(plaintext.count) else {
            throw TeamDeliveryJWEError.invalidInput
        }
        let ordered = try recipients(input)
        var plaintextSnapshot = Data()
        plaintext.withUnsafeBytes { plaintextSnapshot.append(contentsOf: $0) }
        defer {
            plaintextSnapshot.resetBytes(
                in: plaintextSnapshot.startIndex..<plaintextSnapshot.endIndex)
        }
        let kids = ordered.map(\.keyThumbprint)
        let audience = try audience(kids)
        let protectedText = Self.protectedHeader(audience)
        let protectedValue = Self.encode(Data(protectedText.utf8))
        var cek = Data()
        var iv = Data()
        defer {
            cek.resetBytes(in: cek.startIndex..<cek.endIndex)
            iv.resetBytes(in: iv.startIndex..<iv.endIndex)
        }
        cek = try entropy(32)
        guard cek.count == 32 else { throw TeamDeliveryJWEError.invalidInput }
        iv = try entropy(12)
        guard cek.count == 32, iv.count == 12 else { throw TeamDeliveryJWEError.invalidInput }

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(plaintextSnapshot, using: SymmetricKey(data: cek),
                nonce: AES.GCM.Nonce(data: iv), authenticating: Data(protectedValue.utf8))
        } catch {
            throw TeamDeliveryJWEError.invalidInput
        }
        var wrapped = [Recipient]()
        wrapped.reserveCapacity(ordered.count)
        for recipient in ordered { wrapped.append(try wrap(cek: cek, recipient: recipient)) }
        let ephemeralKids = wrapped.map(\.ephemeralThumbprint)
        guard Set(ephemeralKids).count == wrapped.count,
              Set(ephemeralKids).isDisjoint(with: Set(kids)) else {
            throw TeamDeliveryJWEError.invalidInput
        }
        let serialized = Self.serialize(protectedValue: protectedValue, iv: iv,
            ciphertext: sealed.ciphertext, tag: sealed.tag, recipients: wrapped)
        guard serialized.utf8.count <= Self.maximumSerializedBytes else {
            throw TeamDeliveryJWEError.invalidInput
        }
        return serialized
    }

    /// Returned plaintext is caller-owned and must be validated and cleared after durable import.
    func decrypt(_ serialized: String, custody: TeamAgreementKeyCustody,
                 expectedRecipients input: [TeamAgreementPublic]) throws -> Data {
        guard (1...Self.maximumSerializedBytes).contains(serialized.utf8.count) else {
            throw TeamDeliveryJWEError.invalidEnvelope
        }
        let expected = try recipients(input)
        let root: [String: Any]
        do {
            root = try TeamStrictJSON.object(Data(serialized.utf8),
                maximumBytes: Self.maximumSerializedBytes, maximumDepth: 5)
        } catch {
            throw TeamDeliveryJWEError.invalidEnvelope
        }
        guard Set(root.keys) == ["ciphertext", "iv", "protected", "recipients", "tag"],
              let protectedValue = root["protected"] as? String,
              let protectedBytes = Self.decode(protectedValue, maximumBytes: 512),
              let protectedText = String(data: protectedBytes, encoding: .ascii),
              let protectedObject = try? TeamStrictJSON.object(protectedBytes, maximumBytes: 512),
              Set(protectedObject.keys) == ["alg", "crit", "enc", "pba", "pbv", "typ"],
              let audience = protectedObject["pba"] as? String,
              TeamAuthWire.credential(audience),
              protectedText == Self.protectedHeader(audience),
              let rows = root["recipients"] as? [Any],
              (1...TeamDeliveryRules.maximumRecipients).contains(rows.count)
        else { throw TeamDeliveryJWEError.invalidEnvelope }

        var parsed = [Recipient]()
        parsed.reserveCapacity(rows.count)
        do {
            for row in rows {
                guard let object = row as? [String: Any] else {
                    throw TeamDeliveryJWEError.invalidEnvelope
                }
                parsed.append(try parseRecipient(object))
            }
        } catch let error as TeamDeliveryJWEError {
            throw error
        } catch {
            throw TeamDeliveryJWEError.invalidEnvelope
        }
        let kids = parsed.map(\.kid)
        let ephemeralKids = parsed.map(\.ephemeralThumbprint)
        guard kids == kids.sorted(), Set(kids).count == kids.count,
              Set(ephemeralKids).count == ephemeralKids.count,
              Set(ephemeralKids).isDisjoint(with: Set(kids)),
              kids == expected.map(\.keyThumbprint),
              audience == (try? self.audience(kids)),
              let ivText = root["iv"] as? String,
              let ciphertextText = root["ciphertext"] as? String,
              let tagText = root["tag"] as? String,
              let iv = Self.decode(ivText, maximumBytes: 12), iv.count == 12,
              let ciphertext = Self.decode(ciphertextText,
                  maximumBytes: Self.maximumPlaintextBytes), !ciphertext.isEmpty,
              let tag = Self.decode(tagText, maximumBytes: 16), tag.count == 16,
              serialized == Self.serialize(protectedValue: protectedValue, iv: iv,
                  ciphertext: ciphertext, tag: tag, recipients: parsed)
        else { throw TeamDeliveryJWEError.invalidEnvelope }

        // Do not consult retained key custody until the untrusted envelope and the
        // independently authenticated complete audience are both structurally valid.
        let own = try custody.current()
        guard let selected = parsed.first(where: { $0.kid == own.keyThumbprint }) else {
            throw TeamDeliveryJWEError.invalidEnvelope
        }

        var kek = try custody.derive(peer: TeamAgreementPublic(
            keyThumbprint: selected.ephemeralThumbprint, publicKey: selected.ephemeralPublic),
            algorithm: Self.algorithm, partyU: Self.partyU, partyV: Data(selected.kid.utf8))
        var cek: Data?
        defer {
            kek.resetBytes(in: kek.startIndex..<kek.endIndex)
            if cek != nil { cek!.resetBytes(in: cek!.startIndex..<cek!.endIndex) }
        }
        do {
            cek = try TeamDeliveryCryptoPrimitives.unwrapA256(kek: kek, wrapped: selected.encryptedKey)
            guard cek?.count == 32 else { throw TeamDeliveryJWEError.integrityFailure }
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: cek!),
                authenticating: Data(protectedValue.utf8))
            guard (1...Self.maximumPlaintextBytes).contains(plaintext.count) else {
                throw TeamDeliveryJWEError.integrityFailure
            }
            return plaintext
        } catch let error as TeamDeliveryJWEError {
            throw error
        } catch {
            throw TeamDeliveryJWEError.integrityFailure
        }
    }

    private struct Recipient {
        let kid: String
        let apu: String
        let apv: String
        let ephemeralPublic: TeamDeviceEnrollmentWire.PublicKey
        let ephemeralThumbprint: String
        let encryptedKey: Data
    }

    private func wrap(cek: Data, recipient: TeamAgreementPublic) throws -> Recipient {
        let key = try ephemeral()
        let ephemeralPublic = try Self.publicKey(key.publicKey)
        guard ephemeralPublic.thumbprint != recipient.keyThumbprint else {
            throw TeamDeliveryJWEError.invalidInput
        }
        let recipientPublic: P256.KeyAgreement.PublicKey
        do {
            recipientPublic = try P256.KeyAgreement.PublicKey(
                x963Representation: recipient.publicKey.key.x963Representation)
        } catch {
            throw TeamDeliveryJWEError.invalidInput
        }
        var secret = try key.sharedSecretFromKeyAgreement(with: recipientPublic)
            .withUnsafeBytes { Data($0) }
        var kek: Data?
        defer {
            secret.resetBytes(in: secret.startIndex..<secret.endIndex)
            if kek != nil { kek!.resetBytes(in: kek!.startIndex..<kek!.endIndex) }
        }
        guard secret.count == 32 else { throw TeamDeliveryJWEError.invalidInput }
        kek = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: secret,
            algorithm: Self.algorithm, partyU: Self.partyU,
            partyV: Data(recipient.keyThumbprint.utf8), bits: 256)
        let wrapped = try TeamDeliveryCryptoPrimitives.wrapA256(kek: kek!, key: cek)
        guard wrapped.count == 40 else { throw TeamDeliveryJWEError.invalidInput }
        return Recipient(kid: recipient.keyThumbprint, apu: Self.encode(Self.partyU),
            apv: Self.encode(Data(recipient.keyThumbprint.utf8)),
            ephemeralPublic: ephemeralPublic,
            ephemeralThumbprint: ephemeralPublic.thumbprint, encryptedKey: wrapped)
    }

    private func parseRecipient(_ object: [String: Any]) throws -> Recipient {
        guard Set(object.keys) == ["encrypted_key", "header"],
              let encryptedText = object["encrypted_key"] as? String,
              let encrypted = Self.decode(encryptedText, maximumBytes: 40), encrypted.count == 40,
              let header = object["header"] as? [String: Any],
              Set(header.keys) == ["apu", "apv", "epk", "kid"],
              let kid = header["kid"] as? String, TeamAuthWire.credential(kid),
              let apu = header["apu"] as? String,
              let apv = header["apv"] as? String,
              Self.decode(apu, maximumBytes: Self.partyU.count) == Self.partyU,
              Self.decode(apv, maximumBytes: 43) == Data(kid.utf8),
              let epk = header["epk"] as? [String: Any],
              Set(epk.keys) == ["crv", "kty", "x", "y"],
              let crv = epk["crv"] as? String, let kty = epk["kty"] as? String,
              let x = epk["x"] as? String, let y = epk["y"] as? String,
              let publicKey = try? TeamDeviceEnrollmentWire.publicKey([
                  "crv": crv, "kty": kty, "x": x, "y": y
              ])
        else { throw TeamDeliveryJWEError.invalidEnvelope }
        return Recipient(kid: kid, apu: apu, apv: apv, ephemeralPublic: publicKey,
            ephemeralThumbprint: publicKey.thumbprint, encryptedKey: encrypted)
    }

    private func recipients(_ input: [TeamAgreementPublic]) throws -> [TeamAgreementPublic] {
        guard (1...TeamDeliveryRules.maximumRecipients).contains(input.count) else {
            throw TeamDeliveryJWEError.invalidInput
        }
        var snapshot = [TeamAgreementPublic]()
        snapshot.reserveCapacity(input.count)
        for recipient in input {
            let publicKey: TeamDeviceEnrollmentWire.PublicKey
            do { publicKey = try TeamDeviceEnrollmentWire.publicKey(recipient.publicKey.jwk) }
            catch { throw TeamDeliveryJWEError.invalidInput }
            guard TeamAuthWire.credential(recipient.keyThumbprint),
                  publicKey.thumbprint == recipient.keyThumbprint else {
                throw TeamDeliveryJWEError.invalidInput
            }
            snapshot.append(TeamAgreementPublic(keyThumbprint: recipient.keyThumbprint,
                                                publicKey: publicKey))
        }
        let ordered = snapshot.sorted { $0.keyThumbprint < $1.keyThumbprint }
        guard Set(ordered.map(\.keyThumbprint)).count == ordered.count else {
            throw TeamDeliveryJWEError.invalidInput
        }
        return ordered
    }

    private func audience(_ kids: [String]) throws -> String {
        guard kids == kids.sorted(), Set(kids).count == kids.count,
              kids.allSatisfy(TeamAuthWire.credential) else {
            throw TeamDeliveryJWEError.invalidInput
        }
        let exact = "[" + kids.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return Self.encode(Data(SHA256.hash(data: Data(exact.utf8))))
    }

    private static func protectedHeader(_ audience: String) -> String {
        "{\"alg\":\"\(algorithm)\",\"crit\":[\"pba\",\"pbv\"],\"enc\":\"\(encryption)\"," +
        "\"pba\":\"\(audience)\",\"pbv\":\(version),\"typ\":\"\(type)\"}"
    }

    private static func serialize(protectedValue: String, iv: Data, ciphertext: Data,
                                  tag: Data, recipients: [Recipient]) -> String {
        var result = "{\"ciphertext\":\"\(encode(ciphertext))\",\"iv\":\"\(encode(iv))\"," +
            "\"protected\":\"\(protectedValue)\",\"recipients\":["
        for (index, recipient) in recipients.enumerated() {
            if index > 0 { result.append(",") }
            let jwk = recipient.ephemeralPublic.jwk
            result += "{\"encrypted_key\":\"\(encode(recipient.encryptedKey))\",\"header\":{" +
                "\"apu\":\"\(recipient.apu)\",\"apv\":\"\(recipient.apv)\"," +
                "\"epk\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"\(jwk["x"]!)\"," +
                "\"y\":\"\(jwk["y"]!)\"},\"kid\":\"\(recipient.kid)\"}}"
        }
        return result + "],\"tag\":\"\(encode(tag))\"}"
    }

    private static func publicKey(_ key: P256.KeyAgreement.PublicKey) throws
        -> TeamDeviceEnrollmentWire.PublicKey {
        do {
            return try TeamDeviceEnrollmentWire.publicKey(
                P256.Signing.PublicKey(x963Representation: key.x963Representation))
        } catch {
            throw TeamDeliveryJWEError.invalidInput
        }
    }

    private static func secureEntropy(_ count: Int) throws -> Data {
        guard count > 0 else { throw TeamDeliveryJWEError.invalidInput }
        var result = Data(count: count)
        let status = result.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            result.resetBytes(in: result.startIndex..<result.endIndex)
            throw TeamDeliveryJWEError.invalidInput
        }
        return result
    }

    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String, maximumBytes: Int) -> Data? {
        guard maximumBytes >= 0,
              value.utf8.count <= (maximumBytes * 4 + 2) / 3,
              value.utf8.allSatisfy(TeamAuthWire.urlByte) else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), data.count <= maximumBytes,
              encode(data) == value else { return nil }
        return data
    }
}
