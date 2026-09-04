import CryptoKit
import Foundation

struct TeamAudienceRevisionRequest: TeamOnboardingDiagnostic {
    let membershipRevision: Int64
    fileprivate let body: Data

    init(membershipRevision: Int64) throws {
        guard (0...TeamAuthWire.maximumSafeTime).contains(membershipRevision) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.membershipRevision = membershipRevision
        body = Data("{\"membershipRevision\":\(membershipRevision)}".utf8)
        guard body.count <= 100 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamAudienceTarget: TeamOnboardingDiagnostic {
    let accountID: String
    let deviceID: String
    let enrollmentID: String
    let keyThumbprint: String
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
}

struct TeamAudience: TeamOnboardingDiagnostic {
    let teamID: String
    let membershipRevision: Int64
    let targets: [TeamAudienceTarget]
}

struct TeamPreparedDeviceRequestChallenge: TeamOnboardingDiagnostic {
    let challengeID: String
    let expiresAt: Int64
    fileprivate let wire: Data

    init(validating wire: Data, expected: TeamDeviceRequestWire.Binding,
         publicKey: TeamDeviceEnrollmentWire.PublicKey,
         request: TeamAudienceRevisionRequest, now: Int64) throws {
        _ = try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now)
        let object = try TeamStrictJSON.object(wire)
        challengeID = try TeamAuthWire.string(object, "challengeId", secret: true)
        expiresAt = try TeamAuthWire.time(object, "expiresAt")
        self.wire = wire
    }

    func message(expected: TeamDeviceRequestWire.Binding,
                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                 request: TeamAudienceRevisionRequest, now: Int64) throws -> Data {
        try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now)
    }
}

private enum TeamDeviceRequestHTTPWire {
    static func audience(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                         request: TeamAudienceRevisionRequest) throws -> TeamAudience {
        let object = try TeamAuthWire.object(data, keys: ["teamId", "membershipRevision", "targets"])
        let teamID = try TeamAuthWire.string(object, "teamId")
        let revision = try TeamAuthWire.time(object, "membershipRevision")
        guard teamID == expected.teamID, revision == request.membershipRevision,
              let rows = object["targets"] as? [[String: Any]], rows.count <= 9 else {
            throw TeamAuthHTTPError.invalidResponse
        }
        var accounts = Set<String>(), devices = Set<String>(), enrollments = Set<String>()
        let targets = try rows.map { row in
            guard Set(row.keys) == ["accountId", "deviceId", "enrollmentId", "keyThumbprint", "publicKey"],
                  let jwk = row["publicKey"] as? [String: String] else { throw TeamAuthHTTPError.invalidResponse }
            let accountID = try TeamAuthWire.string(row, "accountId")
            let deviceID = try TeamAuthWire.string(row, "deviceId")
            let enrollmentID = try TeamAuthWire.string(row, "enrollmentId")
            let thumbprint = try TeamAuthWire.string(row, "keyThumbprint", secret: true)
            let key: TeamDeviceEnrollmentWire.PublicKey
            do { key = try TeamDeviceEnrollmentWire.publicKey(jwk) }
            catch { throw TeamAuthHTTPError.invalidResponse }
            guard accountID != expected.accountID, key.thumbprint == thumbprint,
                  accounts.insert(accountID).inserted, devices.insert(deviceID).inserted,
                  enrollments.insert(enrollmentID).inserted else { throw TeamAuthHTTPError.invalidResponse }
            return TeamAudienceTarget(accountID: accountID, deviceID: deviceID,
                enrollmentID: enrollmentID, keyThumbprint: thumbprint, publicKey: key)
        }
        return TeamAudience(teamID: teamID, membershipRevision: revision, targets: targets)
    }
}

extension TeamAuthHTTPClient {
    func deviceRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                request: TeamAudienceRevisionRequest,
                                ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .teamAudience else { throw TeamAuthHTTPError.invalidRequest }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deviceRequestChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func executeDeviceRequest(challenge: TeamPreparedDeviceRequestChallenge,
                              signature: Data, expected: TeamDeviceRequestWire.Binding,
                              publicKey: TeamDeviceEnrollmentWire.PublicKey,
                              request: TeamAudienceRevisionRequest,
                              ticket: TeamAccountAccessTicket) async throws -> TeamAudience {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .teamAudience, signature.count == 64,
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let message: Data
        do { message = try challenge.message(expected: expected, publicKey: publicKey,
            request: request, now: onboardingTime()) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        guard publicKey.key.isValidSignature(parsed, for: message) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        let reply = try await onboarding(.deviceRequestExecute, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body)
        ], ticket: ticket)
        return try TeamDeviceRequestHTTPWire.audience(reply.data, expected: expected, request: request)
    }

    private func acceptsDeviceRequestBinding(_ binding: TeamDeviceRequestWire.Binding,
                                             key: TeamDeviceEnrollmentWire.PublicKey,
                                             ticket: TeamAccountAccessTicket) -> Bool {
        let device = TeamDeviceEnrollmentWire.Binding(audience: binding.audience,
            authorityEpoch: binding.authorityEpoch, accountID: binding.accountID,
            sessionID: binding.sessionID, deviceID: binding.deviceID,
            keyThumbprint: binding.keyThumbprint, accessExpiresAt: binding.accessExpiresAt)
        return acceptsDeviceBinding(device, ticket: ticket) &&
            TeamAuthWire.identifier(binding.enrollmentID) && TeamAuthWire.identifier(binding.teamID) &&
            TeamAuthWire.identifier(binding.requestID) && key.thumbprint == binding.keyThumbprint
    }
}
