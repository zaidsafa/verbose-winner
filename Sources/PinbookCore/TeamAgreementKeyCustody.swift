import CryptoKit
import Foundation
import Security

enum TeamAgreementKeyError: Error, Equatable {
    case invalidScope, unavailable, invalidRecord, keyUnavailable, accessLost
}

struct TeamAgreementPublic: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
                            CustomReflectable {
    let keyThumbprint: String
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
    var description: String { "TeamAgreementPublic(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct TeamAgreementScope: Equatable, Sendable {
    static let purpose = "pinbook-device-agreement-v1"
    let identifier: String
    init(origin: String, accountID: String, authorityEpoch: String, enrollmentID: String) throws {
        guard TeamDeviceEnrollmentWire.canonicalAudience(origin),
              TeamAuthWire.identifier(accountID), TeamAuthWire.identifier(authorityEpoch),
              TeamAuthWire.identifier(enrollmentID) else { throw TeamAgreementKeyError.invalidScope }
        let binding = [Self.purpose, origin, accountID, authorityEpoch, enrollmentID].joined(separator: "\n")
        identifier = Data(SHA256.hash(data: Data(binding.utf8))).map { String(format: "%02x", $0) }.joined()
    }
}

struct TeamAgreementKeyMaterial: TeamOnboardingDiagnostic {
    let sealed: Data
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
}

protocol TeamAgreementKeyProviding: Sendable {
    func generate() throws -> TeamAgreementKeyMaterial
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey
    func agree(sealed: Data, peer: TeamDeviceEnrollmentWire.PublicKey) throws -> Data
}

struct SecureEnclaveTeamAgreementKeys: TeamAgreementKeyProviding {
    private func restored(_ data: Data) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        guard SecureEnclave.isAvailable, (1...4096).contains(data.count) else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        do { return try .init(dataRepresentation: data) }
        catch { throw TeamAgreementKeyError.keyUnavailable }
    }
    private func wire(_ key: P256.KeyAgreement.PublicKey) throws -> TeamDeviceEnrollmentWire.PublicKey {
        do { return try TeamDeviceEnrollmentWire.publicKey(P256.Signing.PublicKey(x963Representation: key.x963Representation)) }
        catch { throw TeamAgreementKeyError.keyUnavailable }
    }
    func generate() throws -> TeamAgreementKeyMaterial {
        guard SecureEnclave.isAvailable,
              let access = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .privateKeyUsage, nil) else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        do {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                compactRepresentable: false, accessControl: access)
            guard (1...4096).contains(key.dataRepresentation.count) else {
                throw TeamAgreementKeyError.keyUnavailable
            }
            return try .init(sealed: key.dataRepresentation, publicKey: wire(key.publicKey))
        } catch { throw TeamAgreementKeyError.keyUnavailable }
    }
    func publicKey(sealed: Data) throws -> TeamDeviceEnrollmentWire.PublicKey {
        try wire(restored(sealed).publicKey)
    }
    func agree(sealed: Data, peer: TeamDeviceEnrollmentWire.PublicKey) throws -> Data {
        do {
            let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: peer.key.x963Representation)
            return try restored(sealed).sharedSecretFromKeyAgreement(with: publicKey)
                .withUnsafeBytes { Data($0) }
        } catch { throw TeamAgreementKeyError.keyUnavailable }
    }
}

protocol TeamAgreementKeyStoring: Sendable {
    func load(scope: String) throws -> Data?
    /// Returns false only when another exact-scope value already exists.
    func insert(scope: String, sealed: Data) throws -> Bool
    func remove(scope: String) throws
}
extension TeamAgreementKeyStoring {
    func remove(scope: String) throws { throw TeamAgreementKeyError.unavailable }
}

struct KeychainTeamAgreementKeyStore: TeamAgreementKeyStoring {
    private let service = "com.zaidsafa.pinbook.ios.team-agreement-custody.v1"
    private func base(_ scope: String) throws -> [String: Any] {
        guard scope.utf8.count == 64,
              scope.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw TeamAgreementKeyError.invalidScope
        }
        return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: scope,
            kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    }
    func load(scope: String) throws -> Data? {
        var query = try base(scope)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true; query[kSecReturnAttributes as String] = true
        var raw: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &raw)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let fields = raw as? [String: Any],
              fields[kSecAttrService as String] as? String == service,
              fields[kSecAttrAccount as String] as? String == scope,
              fields[kSecAttrSynchronizable as String] as? Bool == false,
              fields[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String,
              let sealed = fields[kSecValueData as String] as? Data,
              (1...4096).contains(sealed.count),
              fields[kSecAttrGeneric as String] as? Data == Data(SHA256.hash(data: sealed)) else {
            throw TeamAgreementKeyError.invalidRecord
        }
        return sealed
    }
    func insert(scope: String, sealed: Data) throws -> Bool {
        guard (1...4096).contains(sealed.count) else { throw TeamAgreementKeyError.invalidRecord }
        var attributes = try base(scope)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        attributes[kSecValueData as String] = sealed
        attributes[kSecAttrGeneric as String] = Data(SHA256.hash(data: sealed))
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw TeamAgreementKeyError.unavailable }
        return true
    }
    func remove(scope: String) throws {
        let status = SecItemDelete(try base(scope) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TeamAgreementKeyError.unavailable
        }
    }
}

/// Separate inactive agreement identity. It never accepts or reuses a signing key,
/// exports private material, replaces/deletes an identity, or performs network I/O.
final class TeamAgreementKeyCustody: @unchecked Sendable {
    let scope: TeamAgreementScope
    private let storage: any TeamAgreementKeyStoring
    private let keys: any TeamAgreementKeyProviding
    private let requireAccess: @Sendable () throws -> Void
    init(origin: String, accountID: String, authorityEpoch: String, enrollmentID: String,
         storage: any TeamAgreementKeyStoring = KeychainTeamAgreementKeyStore(),
         keys: any TeamAgreementKeyProviding = SecureEnclaveTeamAgreementKeys(),
         requireAccess: @escaping @Sendable () throws -> Void) throws {
        scope = try .init(origin: origin, accountID: accountID,
            authorityEpoch: authorityEpoch, enrollmentID: enrollmentID)
        self.storage = storage; self.keys = keys; self.requireAccess = requireAccess
    }

    func prepare() throws -> TeamAgreementPublic {
        try requireAccess()
        if let sealed = try storage.load(scope: scope.identifier) {
            let result = try checked(sealed); try requireAccess(); return result
        }
        let candidate = try keys.generate()
        guard (1...4096).contains(candidate.sealed.count),
              try keys.publicKey(sealed: candidate.sealed).thumbprint == candidate.publicKey.thumbprint else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        try requireAccess()
        do {
            if try storage.insert(scope: scope.identifier, sealed: candidate.sealed) {
                let result = try checked(candidate.sealed); try requireAccess(); return result
            }
        } catch {
            // An insert error can be ambiguous; only an exact readable winner is accepted.
            if let winner = try? storage.load(scope: scope.identifier),
               let result = try? checked(winner) { try requireAccess(); return result }
            throw error
        }
        guard let winner = try storage.load(scope: scope.identifier) else {
            throw TeamAgreementKeyError.invalidRecord
        }
        let result = try checked(winner); try requireAccess(); return result
    }

    func current() throws -> TeamAgreementPublic {
        try requireAccess()
        guard let sealed = try storage.load(scope: scope.identifier) else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        let result = try checked(sealed); try requireAccess(); return result
    }
    func deleteIdentity() throws { try storage.remove(scope: scope.identifier) }

    /// Returns a fresh derived key owned by the caller, who must clear it after use.
    func derive(peer: TeamAgreementPublic, algorithm: String, partyU: Data,
                partyV: Data, bits: Int = 256) throws -> Data {
        try requireAccess()
        guard peer.publicKey.thumbprint == peer.keyThumbprint,
              let sealed = try storage.load(scope: scope.identifier) else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        _ = try checked(sealed)
        var secret = try keys.agree(sealed: sealed, peer: peer.publicKey)
        var result: Data?
        var released = false
        defer {
            secret.resetBytes(in: secret.startIndex..<secret.endIndex)
            if !released, result != nil {
                result!.resetBytes(in: result!.startIndex..<result!.endIndex)
            }
        }
        guard secret.count == 32 else { throw TeamAgreementKeyError.keyUnavailable }
        result = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: secret,
            algorithm: algorithm, partyU: partyU, partyV: partyV, bits: bits)
        try requireAccess()
        guard let current = try storage.load(scope: scope.identifier), current == sealed else {
            throw TeamAgreementKeyError.keyUnavailable
        }
        _ = try checked(current)
        released = true
        return result!
    }

    private func checked(_ sealed: Data) throws -> TeamAgreementPublic {
        guard (1...4096).contains(sealed.count) else { throw TeamAgreementKeyError.invalidRecord }
        let key = try keys.publicKey(sealed: sealed)
        guard TeamAuthWire.credential(key.thumbprint) else { throw TeamAgreementKeyError.keyUnavailable }
        return .init(keyThumbprint: key.thumbprint, publicKey: key)
    }
}
