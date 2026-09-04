import CryptoKit
import Foundation

enum TeamDeviceEnrollmentWireError: Error, Equatable { case invalidKey, invalidChallenge, bindingMismatch }

/// Internal wire prerequisite only. No key creation/custody, networking or authority.
/// The eventual owner must additionally bind the operation to its durable generation
/// and monotonic deadline, and recheck both immediately before signing/dispatch.
enum TeamDeviceEnrollmentWire {
    struct PublicKey: Sendable {
        let key: P256.Signing.PublicKey
        let jwk: [String: String]
        let thumbprint: String
    }
    struct Binding: Sendable {
        let audience: String
        let authorityEpoch: String
        let accountID: String
        let sessionID: String
        let deviceID: String
        let keyThumbprint: String
        let accessExpiresAt: Int64
    }

    static func publicKey(_ jwk: [String: String]) throws -> PublicKey {
        guard Set(jwk.keys) == ["kty", "crv", "x", "y"],
              jwk["kty"] == "EC", jwk["crv"] == "P-256",
              let x = jwk["x"], let y = jwk["y"],
              TeamAuthWire.credential(x), TeamAuthWire.credential(y),
              let xBytes = decode(x), let yBytes = decode(y),
              let key = try? P256.Signing.PublicKey(x963Representation: Data([4]) + xBytes + yBytes)
        else { throw TeamDeviceEnrollmentWireError.invalidKey }
        // RFC7638 member ordering and no whitespace. No private field is accepted.
        let canonical = try JSONSerialization.data(withJSONObject: jwk,
            options: [.sortedKeys, .withoutEscapingSlashes])
        return PublicKey(key: key, jwk: jwk, thumbprint: encode(Data(SHA256.hash(data: canonical))))
    }

    static func publicKey(_ key: P256.Signing.PublicKey) throws -> PublicKey {
        let bytes = key.x963Representation
        guard bytes.count == 65, bytes.first == 4 else { throw TeamDeviceEnrollmentWireError.invalidKey }
        return try publicKey(["kty": "EC", "crv": "P-256",
            "x": encode(bytes.subdata(in: 1..<33)), "y": encode(bytes.subdata(in: 33..<65))])
    }

    /// Only constructs a domain-separated message after comparing ALL known local
    /// bindings. Never accepts server-provided bytes to sign or follows its audience.
    static func message(challenge data: Data, expected: Binding, now: Int64) throws -> Data {
        let fields: [String: Any]
        do {
            fields = try TeamAuthWire.object(data, keys: ["audience", "authorityEpoch", "accountId",
                "sessionId", "deviceId", "challengeId", "nonce", "keyThumbprint", "expiresAt"])
        } catch { throw TeamDeviceEnrollmentWireError.invalidChallenge }
        guard canonicalAudience(expected.audience), let audience = fields["audience"] as? String,
              audience == expected.audience,
              [expected.authorityEpoch, expected.accountID, expected.sessionID, expected.deviceID]
                .allSatisfy(TeamAuthWire.identifier),
              fields["authorityEpoch"] as? String == expected.authorityEpoch,
              fields["accountId"] as? String == expected.accountID,
              fields["sessionId"] as? String == expected.sessionID,
              fields["deviceId"] as? String == expected.deviceID,
              TeamAuthWire.credential(expected.keyThumbprint),
              fields["keyThumbprint"] as? String == expected.keyThumbprint
        else { throw TeamDeviceEnrollmentWireError.bindingMismatch }
        guard let challengeID = fields["challengeId"] as? String, TeamAuthWire.credential(challengeID),
              let nonce = fields["nonce"] as? String, TeamAuthWire.credential(nonce),
              let expiry = try? TeamAuthWire.time(fields, "expiresAt"),
              now >= 0, now <= TeamAuthWire.maximumSafeTime,
              expected.accessExpiresAt <= TeamAuthWire.maximumSafeTime,
              expiry > now, expiry <= expected.accessExpiresAt, expiry - now <= 120_000
        else { throw TeamDeviceEnrollmentWireError.invalidChallenge }
        return try JSONSerialization.data(withJSONObject: ["pinbook-device-enrollment-v1", audience,
            expected.authorityEpoch, expected.accountID, expected.sessionID, expected.deviceID,
            challengeID, nonce, expected.keyThumbprint, expiry], options: [.withoutEscapingSlashes])
    }

    /// Backend requires the canonical origin WITHOUT a trailing slash. Do not use
    /// the session store's path-normalized scope URL directly as this audience.
    static func canonicalAudience(_ value: String) -> Bool {
        guard value.utf8.count <= 512, value.hasPrefix("https://"),
              let parts = URLComponents(string: value), parts.scheme == "https",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty, let host = parts.host, !host.isEmpty,
              !host.hasSuffix("."), host == host.lowercased(),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              host.utf8.contains(where: { (97...122).contains($0) }),
              parts.url != nil else { return false }
        // WHATWG URL (the backend) interprets a numeric/hex final host label as
        // IPv4 syntax. Foundation does not normalize every such spelling alike.
        // Reject these rather than signing a different origin across parsers.
        let finalLabel = host.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
        if finalLabel.utf8.allSatisfy({ (48...57).contains($0) }) { return false }
        if finalLabel.hasPrefix("0x"), finalLabel.dropFirst(2).utf8.allSatisfy({
            (48...57).contains($0) || (97...102).contains($0)
        }) { return false }
        if let port = parts.port, !(1...65_535).contains(port) || port == 443 { return false }
        let canonical = "https://" + host + (parts.port.map { ":\($0)" } ?? "")
        return value == canonical
    }

    static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ value: String) -> Data? {
        guard !value.isEmpty, value.utf8.count <= 86, value.utf8.allSatisfy(TeamAuthWire.urlByte) else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), encode(data) == value else { return nil }
        return data
    }
}
