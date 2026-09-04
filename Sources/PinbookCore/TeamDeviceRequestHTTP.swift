import CryptoKit
import Foundation

protocol TeamDeviceRequestPayload: TeamOnboardingDiagnostic {
    var membershipRevision: Int64 { get }
    var body: Data { get }
}

struct TeamAudienceRevisionRequest: TeamDeviceRequestPayload {
    let membershipRevision: Int64
    let body: Data

    init(membershipRevision: Int64) throws {
        guard (0...TeamAuthWire.maximumSafeTime).contains(membershipRevision) else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.membershipRevision = membershipRevision
        body = Data("{\"membershipRevision\":\(membershipRevision)}".utf8)
        guard body.count <= 100 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamAgreementEnrollmentRequest: TeamDeviceRequestPayload {
    let membershipRevision: Int64
    let agreement: TeamAgreementPublic
    let body: Data

    init(membershipRevision: Int64, agreement: TeamAgreementPublic) throws {
        let jwk = agreement.publicKey.jwk
        guard (0...TeamAuthWire.maximumSafeTime).contains(membershipRevision),
              agreement.keyThumbprint == agreement.publicKey.thumbprint,
              Set(jwk.keys) == ["kty", "crv", "x", "y"],
              jwk["kty"] == "EC", jwk["crv"] == "P-256",
              let x = jwk["x"], let y = jwk["y"] else {
            throw TeamAuthHTTPError.invalidRequest
        }
        self.membershipRevision = membershipRevision; self.agreement = agreement
        body = Data("{\"agreementKey\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"\(x)\",\"y\":\"\(y)\"},\"membershipRevision\":\(membershipRevision)}".utf8)
        guard body.count <= 256 else { throw TeamAuthHTTPError.invalidRequest }
    }
}

struct TeamAudienceTarget: TeamOnboardingDiagnostic {
    let accountID: String
    let deviceID: String
    let enrollmentID: String
    let keyThumbprint: String
    let publicKey: TeamDeviceEnrollmentWire.PublicKey
    let agreementKeyThumbprint: String
    let agreementPublicKey: TeamDeviceEnrollmentWire.PublicKey
}

struct TeamAudience: TeamOnboardingDiagnostic {
    let teamID: String
    let membershipRevision: Int64
    let targets: [TeamAudienceTarget]
}

struct TeamAgreementRegistration: TeamOnboardingDiagnostic {
    let teamID: String
    let membershipRevision: Int64
    let enrollmentID: String
    let agreementKeyThumbprint: String
    let agreementPublicKey: TeamDeviceEnrollmentWire.PublicKey
}

struct TeamPreparedDeviceRequestChallenge: TeamOnboardingDiagnostic {
    let challengeID: String
    let expiresAt: Int64
    fileprivate let wire: Data

    init<Request: TeamDeviceRequestPayload>(validating wire: Data, expected: TeamDeviceRequestWire.Binding,
         publicKey: TeamDeviceEnrollmentWire.PublicKey,
         request: Request, now: Int64) throws {
        _ = try TeamDeviceRequestWire.message(challenge: wire, expected: expected,
            publicKey: publicKey, body: request.body, now: now)
        let object = try TeamStrictJSON.object(wire)
        challengeID = try TeamAuthWire.string(object, "challengeId", secret: true)
        expiresAt = try TeamAuthWire.time(object, "expiresAt")
        self.wire = wire
    }

    func message<Request: TeamDeviceRequestPayload>(expected: TeamDeviceRequestWire.Binding,
                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                 request: Request, now: Int64) throws -> Data {
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
            guard Set(row.keys) == ["accountId", "deviceId", "enrollmentId", "keyThumbprint", "publicKey",
                "agreementKeyThumbprint", "agreementPublicKey"],
                  let jwk = row["publicKey"] as? [String: String],
                  let agreementJWK = row["agreementPublicKey"] as? [String: String] else {
                throw TeamAuthHTTPError.invalidResponse
            }
            let accountID = try TeamAuthWire.string(row, "accountId")
            let deviceID = try TeamAuthWire.string(row, "deviceId")
            let enrollmentID = try TeamAuthWire.string(row, "enrollmentId")
            let thumbprint = try TeamAuthWire.string(row, "keyThumbprint", secret: true)
            let agreementThumbprint = try TeamAuthWire.string(row, "agreementKeyThumbprint", secret: true)
            let key: TeamDeviceEnrollmentWire.PublicKey, agreementKey: TeamDeviceEnrollmentWire.PublicKey
            do {
                key = try TeamDeviceEnrollmentWire.publicKey(jwk)
                agreementKey = try TeamDeviceEnrollmentWire.publicKey(agreementJWK)
            }
            catch { throw TeamAuthHTTPError.invalidResponse }
            guard accountID != expected.accountID, key.thumbprint == thumbprint,
                  agreementKey.thumbprint == agreementThumbprint,
                  agreementThumbprint != thumbprint,
                  accounts.insert(accountID).inserted, devices.insert(deviceID).inserted,
                  enrollments.insert(enrollmentID).inserted else { throw TeamAuthHTTPError.invalidResponse }
            return TeamAudienceTarget(accountID: accountID, deviceID: deviceID,
                enrollmentID: enrollmentID, keyThumbprint: thumbprint, publicKey: key,
                agreementKeyThumbprint: agreementThumbprint, agreementPublicKey: agreementKey)
        }
        return TeamAudience(teamID: teamID, membershipRevision: revision, targets: targets)
    }

    static func agreement(_ data: Data, expected: TeamDeviceRequestWire.Binding,
                          request: TeamAgreementEnrollmentRequest) throws -> TeamAgreementRegistration {
        let object = try TeamAuthWire.object(data, keys: ["teamId", "membershipRevision", "enrollmentId",
            "agreementKeyThumbprint", "agreementPublicKey"])
        guard let jwk = object["agreementPublicKey"] as? [String: String] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        let key: TeamDeviceEnrollmentWire.PublicKey
        do { key = try TeamDeviceEnrollmentWire.publicKey(jwk) }
        catch { throw TeamAuthHTTPError.invalidResponse }
        let result = try TeamAgreementRegistration(teamID: TeamAuthWire.string(object, "teamId"),
            membershipRevision: TeamAuthWire.time(object, "membershipRevision"),
            enrollmentID: TeamAuthWire.string(object, "enrollmentId"),
            agreementKeyThumbprint: TeamAuthWire.string(object, "agreementKeyThumbprint", secret: true),
            agreementPublicKey: key)
        guard result.teamID == expected.teamID,
              result.membershipRevision == request.membershipRevision,
              result.enrollmentID == expected.enrollmentID,
              result.agreementKeyThumbprint == request.agreement.keyThumbprint,
              result.agreementPublicKey.thumbprint == result.agreementKeyThumbprint,
              result.agreementPublicKey.jwk == request.agreement.publicKey.jwk else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return result
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

    func agreementRequestChallenge(expected: TeamDeviceRequestWire.Binding,
                                   publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                   request: TeamAgreementEnrollmentRequest,
                                   ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceRequestChallenge {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .agreementEnroll else { throw TeamAuthHTTPError.invalidRequest }
        let digest: String
        do { digest = try TeamDeviceRequestWire.bodySHA256(request.body) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.agreementChallenge, fields: [
            "enrollmentId": expected.enrollmentID,
            "binding": ["operation": expected.operation.rawValue, "teamId": expected.teamID,
                        "requestId": expected.requestID, "bodySha256": digest]
        ], ticket: ticket)
        do {
            return try .init(validating: reply.data, expected: expected,
                publicKey: publicKey, request: request, now: reply.receivedAt)
        } catch { throw TeamAuthHTTPError.invalidResponse }
    }

    func executeAgreementRequest(challenge: TeamPreparedDeviceRequestChallenge,
                                 signature: Data, expected: TeamDeviceRequestWire.Binding,
                                 publicKey: TeamDeviceEnrollmentWire.PublicKey,
                                 request: TeamAgreementEnrollmentRequest,
                                 ticket: TeamAccountAccessTicket) async throws -> TeamAgreementRegistration {
        guard acceptsDeviceRequestBinding(expected, key: publicKey, ticket: ticket),
              expected.operation == .agreementEnroll, signature.count == 64,
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
        let reply = try await onboarding(.agreementExecute, fields: [
            "challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature),
            "body": TeamDeviceEnrollmentWire.encode(request.body)
        ], ticket: ticket)
        return try TeamDeviceRequestHTTPWire.agreement(reply.data, expected: expected, request: request)
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
