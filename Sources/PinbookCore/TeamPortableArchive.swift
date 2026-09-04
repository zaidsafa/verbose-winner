import CryptoKit
import Foundation
import Darwin
import Security

public enum TeamRecoveryKeyError: Error, Equatable {
    case invalidKey, alreadyExists, invalidStoredItem, unavailable(OSStatus)
}

protocol TeamRecoveryKeychain: Sendable {
    func add(_ query: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
}

private struct SystemTeamRecoveryKeychain: TeamRecoveryKeychain {
    func add(_ query: [String: Any]) -> OSStatus { SecItemAdd(query as CFDictionary, nil) }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
}

/// Inactive archive-key custody only; not a login, group key, cloud backup or recovery guarantee.
/// No replacement/deletion API: replacing a key can make existing backups unrecoverable.
public struct TeamRecoveryKeyStore: Sendable {
    private let service: String
    private let keychain: any TeamRecoveryKeychain

    public init() {
        service = "com.zaidsafa.pinbook.ios.team-archive-recovery.v1"
        keychain = SystemTeamRecoveryKeychain()
    }

    // Isolated synthetic test namespace; no production caller can change the service.
    init(testService: String, keychain: (any TeamRecoveryKeychain)? = nil) {
        service = testService
        self.keychain = keychain ?? SystemTeamRecoveryKeychain()
    }

    private func query(accountId: String) throws -> [String: Any] {
        try TeamDeliveryRules.requireID(accountId)
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountId,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true]
    }

    /// Explicit first save only. SecItemAdd atomically refuses an existing account/purpose key.
    /// Caller must arrange user consent and an intentional off-device recovery-key copy.
    public func storeNew(_ recoveryKey: SymmetricKey, accountId: String) throws {
        guard recoveryKey.bitCount == 256 else { throw TeamRecoveryKeyError.invalidKey }
        var attributes = try query(accountId: accountId)
        var bytes = recoveryKey.withUnsafeBytes { Data($0) }
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        attributes[kSecValueData as String] = bytes
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = keychain.add(attributes)
        if status == errSecDuplicateItem { throw TeamRecoveryKeyError.alreadyExists }
        guard status == errSecSuccess else { throw TeamRecoveryKeyError.unavailable(status) }
    }

    /// Missing is distinct from inaccessible/corrupt. Never generates a replacement on failure.
    public func load(accountId: String) throws -> SymmetricKey? {
        var attributes = try query(accountId: accountId)
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        attributes[kSecReturnData as String] = true
        attributes[kSecReturnAttributes as String] = true
        let (status, result) = keychain.copy(attributes)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TeamRecoveryKeyError.unavailable(status) }
        guard let stored = result as? [String: Any],
              stored[kSecAttrService as String] as? String == service,
              stored[kSecAttrAccount as String] as? String == accountId,
              stored[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
              stored[kSecAttrSynchronizable as String] as? Bool == false,
              var bytes = stored[kSecValueData as String] as? Data,
              bytes.count == 32 else { throw TeamRecoveryKeyError.invalidStoredItem }
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        return SymmetricKey(data: bytes)
    }
}

public enum TeamArchiveError: Error, Equatable {
    case invalidFormat, invalidAccount, invalidTimestamp, duplicateDelivery, tooLarge
    case invalidKey, authenticationFailed
    case fileUnavailable
}

/// An authenticated, immutable import candidate. It grants no remote account authority.
/// Keep only while the restore confirmation is open; do not log or persist this value.
public struct TeamArchiveImport: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let archive: TeamPortableArchive
    public var accountId: String { archive.accountId }
    public var exportedAt: Int64 { archive.exportedAt }
    public var recordCount: Int { archive.notes.count }
    public var teamCount: Int { Set(archive.notes.map { $0.envelope.teamId }).count }
    public var description: String { "TeamArchiveImport(<redacted>)" }
    public var debugDescription: String { description }

    private init(archive: TeamPortableArchive) { self.archive = archive }

    public static func prepare(_ compact: String, recoveryKey: SymmetricKey,
                               expectedAccountId: String) throws -> Self {
        Self(archive: try TeamArchiveJWE.decrypt(compact, recoveryKey: recoveryKey,
                                               expectedAccountId: expectedAccountId))
    }

    /// Caller owns security-scoped access and file-provider coordination. Reads one opened
    /// regular file, with a byte cap independent of advertised size. Never writes plaintext.
    /// Confirmation uses this candidate, not a second read of a possibly replaced file.
    public static func prepare(fileURL: URL, recoveryKey: SymmetricKey,
                               expectedAccountId: String) throws -> Self {
        guard recoveryKey.bitCount == 256 else { throw TeamArchiveError.invalidKey }
        try TeamDeliveryRules.requireID(expectedAccountId)
        let compact = try readCompactFile(fileURL)
        return try prepare(compact, recoveryKey: recoveryKey, expectedAccountId: expectedAccountId)
    }

    static func readCompactFile(_ url: URL) throws -> String {
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw TeamArchiveError.fileUnavailable }
        // NONBLOCK avoids hanging on a FIFO before fstat can reject non-regular inputs.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw TeamArchiveError.fileUnavailable }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0 else { throw TeamArchiveError.fileUnavailable }
        guard info.st_size <= TeamArchiveJWE.maximumCompactBytes else { throw TeamArchiveError.tooLarge }
        return try readBoundedCompact { count in
            var data = Data(count: count)
            let actual = data.withUnsafeMutableBytes { buffer in
                var result: Int
                repeat { result = Darwin.read(descriptor, buffer.baseAddress, count) }
                while result < 0 && errno == EINTR
                return result
            }
            guard actual >= 0 else { throw TeamArchiveError.fileUnavailable }
            data.count = actual
            return data
        }
    }

    /// Internal stream seam exercises short reads, growth and failures without provider access.
    static func readBoundedCompact(maximumBytes: Int = TeamArchiveJWE.maximumCompactBytes,
                                   read: (Int) throws -> Data) throws -> String {
        guard (0...TeamArchiveJWE.maximumCompactBytes).contains(maximumBytes) else {
            throw TeamArchiveError.tooLarge
        }
        var data = Data()
        while true {
            let requested = min(64 * 1024, maximumBytes - data.count + 1)
            let chunk = try read(requested)
            guard chunk.count <= requested, chunk.count <= maximumBytes - data.count else {
                throw TeamArchiveError.tooLarge
            }
            if chunk.isEmpty { break }
            // Compact JWE is ASCII. Reject invalid bytes rather than lossy replacement.
            guard chunk.allSatisfy({ $0 < 128 }) else { throw TeamArchiveError.invalidFormat }
            data.append(chunk)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Portable archive only. No ACKs, enrollment credentials, group keys or remote authority.
public struct TeamPortableArchive: Equatable, Sendable {
    public static let marker = "pinbook-team-archive-v1"
    public static let maximumRecords = 10_000
    public static let maximumPlaintextBytes = 16 * 1024 * 1024
    public let accountId: String
    public let exportedAt: Int64
    public let notes: [ArchivedTeamNote]

    public init(accountId: String, exportedAt: Int64, notes: [ArchivedTeamNote]) throws {
        self.accountId = accountId
        self.exportedAt = exportedAt
        self.notes = notes
        _ = try encodePlaintext()
    }

    public func encodePlaintext() throws -> Data {
        var writer = try BoundedTeamArchiveWriter(accountId: accountId, exportedAt: exportedAt)
        for note in notes { try writer.append(note) }
        return writer.finish()
    }

    public static func decodePlaintext(_ data: Data, expectedAccountId: String) throws -> Self {
        guard data.count <= maximumPlaintextBytes else { throw TeamArchiveError.tooLarge }
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]), String(data: data, encoding: .utf8) != nil else {
            throw TeamArchiveError.invalidFormat
        }
        // Foundation accepts some nonstandard syntax. Enforce this fixed array/string grammar
        // before its decoder allocates a JSON map; Unicode escape semantics remain Foundation's job.
        try data.withUnsafeBytes { bytes in
            var syntax = ArchiveTupleSyntax(bytes: bytes)
            try syntax.validate()
        }
        try TeamDeliveryRules.requireID(expectedAccountId)
        let decoder = JSONDecoder()
        decoder.userInfo[ArchiveRoot.expectedAccountKey] = expectedAccountId
        do { return try decoder.decode(ArchiveRoot.self, from: data).archive }
        catch let error as TeamArchiveError { throw error }
        catch { throw TeamArchiveError.invalidFormat }
    }

    static func timestamp(_ text: String) throws -> Int64 {
        guard !text.isEmpty, text.utf8.count <= 19,
              text.utf8.allSatisfy({ (48...57).contains($0) }),
              text == "0" || text.utf8.first != 48,
              let value = Int64(text) else { throw TeamArchiveError.invalidTimestamp }
        return value
    }
}

private struct ArchiveTupleSyntax {
    let bytes: UnsafeRawBufferPointer
    var offset = 0

    mutating func validate() throws {
        try require(91) // [marker, account, timestamp, [records]]
        for index in 0..<3 {
            if index > 0 { try require(44) }
            try string()
        }
        try require(44)
        try require(91)
        if !consume(93) {
            var count = 0
            repeat {
                count += 1
                guard count <= TeamPortableArchive.maximumRecords else { throw TeamArchiveError.tooLarge }
                try require(91)
                for index in 0..<11 {
                    if index > 0 { try require(44) }
                    try string()
                }
                try require(93)
            } while consume(44)
            try require(93)
        }
        try require(93)
        whitespace()
        guard offset == bytes.count else { throw TeamArchiveError.invalidFormat }
    }

    private mutating func whitespace() {
        while offset < bytes.count, [UInt8(32), 9, 10, 13].contains(bytes[offset]) { offset += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard offset < bytes.count, bytes[offset] == byte else { return false }
        offset += 1
        return true
    }

    private mutating func require(_ byte: UInt8) throws {
        guard consume(byte) else { throw TeamArchiveError.invalidFormat }
    }

    private mutating func string() throws {
        try require(34)
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte == 34 { return }
            guard byte >= 32 else { throw TeamArchiveError.invalidFormat }
            if byte == 92 {
                guard offset < bytes.count else { throw TeamArchiveError.invalidFormat }
                let escape = bytes[offset]
                offset += 1
                if escape == 117 {
                    guard offset + 4 <= bytes.count else { throw TeamArchiveError.invalidFormat }
                    for value in bytes[offset..<(offset + 4)] {
                        guard (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value) else {
                            throw TeamArchiveError.invalidFormat
                        }
                    }
                    offset += 4
                } else if ![UInt8(34), 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                    throw TeamArchiveError.invalidFormat
                }
            }
        }
        throw TeamArchiveError.invalidFormat
    }
}

private struct ArchiveRoot: Decodable {
    static let expectedAccountKey = CodingUserInfoKey(rawValue: "expectedTeamArchiveAccount")!
    let archive: TeamPortableArchive

    init(from decoder: Decoder) throws {
        var root = try decoder.unkeyedContainer()
        guard root.count == 4, try root.decode(String.self) == TeamPortableArchive.marker else {
            throw TeamArchiveError.invalidFormat
        }
        let account = try root.decode(String.self)
        guard account == decoder.userInfo[Self.expectedAccountKey] as? String else {
            throw TeamArchiveError.invalidAccount
        }
        let exportedAt = try TeamPortableArchive.timestamp(root.decode(String.self))
        var records = try root.nestedUnkeyedContainer()
        guard let count = records.count, count <= TeamPortableArchive.maximumRecords else {
            throw TeamArchiveError.tooLarge
        }
        var notes: [ArchivedTeamNote] = []
        notes.reserveCapacity(count)
        while !records.isAtEnd {
            var tuple = try records.nestedUnkeyedContainer()
            guard tuple.count == 11 else { throw TeamArchiveError.invalidFormat }
            var fields: [String] = []
            for _ in 0..<11 { fields.append(try tuple.decode(String.self)) }
            let target = try DeliveryTarget(userId: account, deviceId: fields[4], enrollmentId: fields[5])
            let envelope = TeamNoteEnvelope(protocolVersion: 1, teamId: fields[0], deliveryId: fields[1],
                noteId: fields[2], authorUserId: fields[3], recipient: target, body: fields[6], bodySha256: fields[7],
                acceptedAt: try TeamPortableArchive.timestamp(fields[8]),
                expiresAt: try TeamPortableArchive.timestamp(fields[9]), attachmentCount: 0)
            notes.append(ArchivedTeamNote(envelope: envelope, savedAt: try TeamPortableArchive.timestamp(fields[10])))
        }
        guard root.isAtEnd else { throw TeamArchiveError.invalidFormat }
        archive = try TeamPortableArchive(accountId: account, exportedAt: exportedAt, notes: notes)
    }
}

private struct ArchiveIdentity: Hashable {
    let teamId: String
    let deliveryId: String
}

/// Incremental serialization enforces the exact encoded-byte bound before appending each row.
/// Also used by SQLite export so an oversized database is never collected into a giant array.
struct BoundedTeamArchiveWriter {
    private let accountId: String
    private let encoder: JSONEncoder
    private var data: Data
    private var identities: Set<ArchiveIdentity> = []

    init(accountId: String, exportedAt: Int64) throws {
        try TeamDeliveryRules.requireID(accountId)
        guard exportedAt >= 0 else { throw TeamArchiveError.invalidTimestamp }
        self.accountId = accountId
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        data = try encoder.encode([TeamPortableArchive.marker, accountId, String(exportedAt)])
        data.removeLast() // Replace the encoded array's final ] with its fourth, nested element.
        data.append(contentsOf: ",[".utf8)
    }

    mutating func append(_ note: ArchivedTeamNote) throws {
        guard identities.count < TeamPortableArchive.maximumRecords else { throw TeamArchiveError.tooLarge }
        let envelope = note.envelope
        guard envelope.recipient.userId == accountId else { throw TeamArchiveError.invalidAccount }
        try envelope.validate(for: envelope.recipient, expectedTeamId: envelope.teamId)
        guard note.savedAt >= 0 else { throw TeamArchiveError.invalidTimestamp }
        let identity = ArchiveIdentity(teamId: envelope.teamId, deliveryId: envelope.deliveryId)
        guard !identities.contains(identity) else { throw TeamArchiveError.duplicateDelivery }
        let row = try encoder.encode([
            envelope.teamId, envelope.deliveryId, envelope.noteId, envelope.authorUserId,
            envelope.recipient.deviceId, envelope.recipient.enrollmentId, envelope.body, envelope.bodySha256,
            String(envelope.acceptedAt), String(envelope.expiresAt), String(note.savedAt)
        ])
        let commaBytes = identities.isEmpty ? 0 : 1
        guard data.count + commaBytes + row.count + 2 <= TeamPortableArchive.maximumPlaintextBytes else {
            throw TeamArchiveError.tooLarge
        }
        if commaBytes == 1 { data.append(44) }
        data.append(row)
        identities.insert(identity)
    }

    func finish() -> Data {
        var result = data
        result.append(contentsOf: "]]".utf8)
        return result
    }
}

/// A deliberately narrow RFC 7516/7518 archive profile, not a general JOSE or group-crypto engine.
public enum TeamArchiveJWE {
    public static let maximumCompactBytes = 22_370_000
    public static let protectedHeader = #"{"alg":"dir","enc":"A256GCM","typ":"pinbook-team-archive-v1"}"#
    static let encodedHeader = base64URL(Data(protectedHeader.utf8))

    /// No password derivation or key persistence. Future recovery UI must arrange safe custody.
    public static func generateRecoveryKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func encrypt(_ archive: TeamPortableArchive, recoveryKey: SymmetricKey) throws -> String {
        var plaintext = try archive.encodePlaintext()
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        return try encryptValidatedPlaintext(plaintext, recoveryKey: recoveryKey)
    }

    static func encryptValidatedPlaintext(_ plaintext: Data, recoveryKey: SymmetricKey) throws -> String {
        guard recoveryKey.bitCount == 256 else { throw TeamArchiveError.invalidKey }
        guard plaintext.count <= TeamPortableArchive.maximumPlaintextBytes else { throw TeamArchiveError.tooLarge }
        // CryptoKit generates a fresh 96-bit nonce. There is no caller-supplied nonce API.
        let box = try AES.GCM.seal(plaintext, using: recoveryKey, authenticating: Data(encodedHeader.utf8))
        let compact = [encodedHeader, "", base64URL(box.nonce.withUnsafeBytes { Data($0) }),
                       base64URL(box.ciphertext), base64URL(box.tag)].joined(separator: ".")
        guard compact.utf8.count <= maximumCompactBytes else { throw TeamArchiveError.tooLarge }
        return compact
    }

    public static func decrypt(_ compact: String, recoveryKey: SymmetricKey,
                               expectedAccountId: String) throws -> TeamPortableArchive {
        guard recoveryKey.bitCount == 256 else { throw TeamArchiveError.invalidKey }
        guard compact.utf8.count <= maximumCompactBytes else { throw TeamArchiveError.tooLarge }
        // At most six pieces even for malicious input containing millions of separators.
        let parts = compact.split(separator: ".", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == encodedHeader, parts[1].isEmpty else {
            throw TeamArchiveError.invalidFormat
        }
        let nonce = try decodeBase64URL(parts[2], maximumBytes: 12)
        let ciphertext = try decodeBase64URL(parts[3], maximumBytes: TeamPortableArchive.maximumPlaintextBytes)
        let tag = try decodeBase64URL(parts[4], maximumBytes: 16)
        guard nonce.count == 12, tag.count == 16 else { throw TeamArchiveError.invalidFormat }
        var plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            plaintext = try AES.GCM.open(box, using: recoveryKey, authenticating: Data(encodedHeader.utf8))
        } catch { throw TeamArchiveError.authenticationFailed }
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        // No caller sees plaintext before authentication, and no database is changed here.
        return try TeamPortableArchive.decodePlaintext(plaintext, expectedAccountId: expectedAccountId)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ text: Substring, maximumBytes: Int) throws -> Data {
        guard text.utf8.count <= ((maximumBytes + 2) / 3) * 4 else { throw TeamArchiveError.tooLarge }
        guard text.utf8.count % 4 != 1, text.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { throw TeamArchiveError.invalidFormat }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base64), bytes.count <= maximumBytes,
              base64URL(bytes) == text else { throw TeamArchiveError.invalidFormat }
        return bytes
    }
}
