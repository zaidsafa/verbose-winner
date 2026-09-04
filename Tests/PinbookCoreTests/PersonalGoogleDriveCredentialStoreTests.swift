import Foundation
import Security
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

final class PersonalDriveCredentialKeychainStub:
    PersonalGoogleDriveCredentialKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var item: [String: Any]?

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard item == nil else { return errSecDuplicateItem }
            item = attributes
            return errSecSuccess
        }
    }

    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.withLock {
            guard let item else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, item as CFDictionary)
        }
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard var item, matches(query, item) else { return errSecItemNotFound }
            for (key, value) in attributes { item[key] = value }
            self.item = item
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            guard let item, matches(query, item) else { return errSecItemNotFound }
            self.item = nil
            return errSecSuccess
        }
    }

    func mutate(_ transform: (inout [String: Any]) -> Void) {
        lock.withLock {
            guard var item else { return }
            transform(&item)
            self.item = item
        }
    }

    func attributes() -> [String: Any]? { lock.withLock { item } }

    private func matches(_ query: [String: Any], _ item: [String: Any]) -> Bool {
        for key in [kSecClass, kSecAttrService, kSecAttrAccount,
                    kSecAttrSynchronizable, kSecAttrAccessible, kSecAttrGeneric] {
            let name = key as String
            if let expected = query[name] as? NSObject,
               let actual = item[name] as? NSObject, expected != actual { return false }
            if query[name] != nil && item[name] == nil { return false }
        }
        return true
    }
}

func personalDriveCredentialConfiguration(_ prefix: String = "123-custody") throws
    -> PersonalGoogleDriveConfiguration {
    let client = prefix + ".apps.googleusercontent.com"
    return try PersonalGoogleDriveConfiguration(
        clientID: client,
        registeredURLSchemes: [client.split(separator: ".").reversed().joined(separator: ".")]
    )
}

func personalDriveCredentialGrant(refresh: Character = "r",
                                          refreshLifetime: Int64? = 7_200,
                                          now: Int64 = 1_000_000) throws
    -> PersonalGoogleDriveGrant {
    var object: [String: Any] = [
        "access_token": String(repeating: "a", count: 32),
        "expires_in": 3_600,
        "scope": GoogleDriveBackupTransport.scope,
        "token_type": "Bearer",
        "refresh_token": String(repeating: String(refresh), count: 32),
    ]
    if let refreshLifetime { object["refresh_token_expires_in"] = refreshLifetime }
    return try PersonalGoogleDriveTokenClient.grant(
        JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
        existingRefresh: nil, now: now
    )
}

@Suite(.serialized)
struct PersonalGoogleDriveCredentialStoreTests {
    @Test func saveLoadUsesDeviceOnlyKeychainAndRedactsSecrets() throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.secure", keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        let grant = try personalDriveCredentialGrant()
        let saved = try store.saveInitial(grant, configuration: configuration,
                                          now: 1_000_000, consent: true)
        let persisted = try store.load(configuration: configuration)
        let loaded = try #require(persisted)
        #expect(saved.generation == loaded.generation)
        #expect(loaded.phase == .active)
        #expect(loaded.refreshExpiresAt == 8_200_000)
        #expect(String(reflecting: loaded) ==
                "PersonalGoogleDriveCredentialSnapshot(<redacted>)")
        #expect(Mirror(reflecting: loaded).children.isEmpty)
        #expect(String(reflecting: try loaded.usableRefreshToken(now: 1_000_001)) ==
                "PersonalGoogleDriveRefreshToken(<redacted>)")

        let fields = try #require(keychain.attributes())
        #expect(fields[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(fields[kSecAttrAccessible as String] as? String ==
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(fields[kSecUseDataProtectionKeychain as String] as? Bool == true)
        let data = try #require(fields[kSecValueData as String] as? Data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(String(repeating: "r", count: 32)))
        #expect(!text.contains(String(repeating: "a", count: 32)))
        #expect(!text.contains(configuration.clientID))
    }

    @Test func consentDuplicateScopeAndCorruptionFailClosed() throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.closed", keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        let grant = try personalDriveCredentialGrant()
        #expect(throws: PersonalGoogleDriveCredentialError.consentRequired) {
            try store.saveInitial(grant, configuration: configuration,
                                  now: 1_000_000, consent: false)
        }
        _ = try store.saveInitial(grant, configuration: configuration,
                                  now: 1_000_000, consent: true)
        #expect(throws: PersonalGoogleDriveCredentialError.alreadyConnected) {
            try store.saveInitial(grant, configuration: configuration,
                                  now: 1_000_000, consent: true)
        }
        let foreign = try personalDriveCredentialConfiguration("456-custody")
        #expect(throws: PersonalGoogleDriveCredentialError.scopeMismatch) {
            try store.load(configuration: foreign)
        }
        keychain.mutate { $0[kSecAttrGeneric as String] = Data("wrong".utf8) }
        #expect(throws: PersonalGoogleDriveCredentialError.invalidRecord) {
            try store.load(configuration: configuration)
        }
    }

    @Test func refreshRotationAndRemovalAreGenerationBound() throws {
        let keychain = PersonalDriveCredentialKeychainStub()
        let store = try PersonalGoogleDriveCredentialStore(
            testService: "pinbook.personal-drive-credential-test.rotation", keychain: keychain
        )
        let configuration = try personalDriveCredentialConfiguration()
        let initial = try store.saveInitial(
            personalDriveCredentialGrant(), configuration: configuration,
            now: 1_000_000, consent: true
        )
        let rotated = try store.replace(
            initial, with: personalDriveCredentialGrant(refresh: "n", refreshLifetime: nil,
                                                        now: 2_000_000),
            now: 2_000_000
        )
        #expect(rotated.generation != initial.generation)
        #expect(rotated.phase == .active)
        #expect(rotated.refreshExpiresAt == nil)
        #expect(throws: PersonalGoogleDriveCredentialError.staleOperation) {
            try store.remove(initial, consent: true)
        }
        #expect(throws: PersonalGoogleDriveCredentialError.consentRequired) {
            try store.remove(rotated, consent: false)
        }
        try store.remove(rotated, consent: true)
        #expect(try store.load(configuration: configuration) == nil)

        let expiring = try store.saveInitial(
            personalDriveCredentialGrant(refreshLifetime: 60, now: 3_000_000),
            configuration: configuration, now: 3_000_000, consent: true
        )
        #expect(throws: PersonalGoogleDriveCredentialError.expired) {
            try expiring.usableRefreshToken(now: 3_060_000)
        }
    }

    #if !SWIFT_PACKAGE
    @Test func realKeychainReopensAndExactGenerationClears() throws {
        let suffix = UUID().uuidString.lowercased()
        let service = "pinbook.personal-drive-credential-device-test." + suffix
        let first = try PersonalGoogleDriveCredentialStore(deviceTestService: service)
        let configuration = try personalDriveCredentialConfiguration()
        let saved = try first.saveInitial(
            personalDriveCredentialGrant(), configuration: configuration,
            now: 1_000_000, consent: true
        )
        let reopened = try PersonalGoogleDriveCredentialStore(deviceTestService: service)
        let persisted = try reopened.load(configuration: configuration)
        let loaded = try #require(persisted)
        #expect(loaded.generation == saved.generation)
        try reopened.remove(loaded, consent: true)
        #expect(try first.load(configuration: configuration) == nil)
    }
    #endif
}
