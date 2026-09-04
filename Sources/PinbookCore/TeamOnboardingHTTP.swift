import Foundation

enum TeamOnboardingRoute: String {
    case preview = "invitations/preview", invitedChallenge = "auth/invited-challenge", invitedExchange = "auth/invited-exchange"
    case deviceChallenge = "devices/challenge", deviceComplete = "devices/complete", deviceLookup = "devices/lookup", deviceRevoke = "devices/revoke"
    case createTeam = "teams/create", currentTeam = "teams/current", acceptInvitation = "teams/accept"
    case issueInvitation = "teams/invites", listInvitations = "teams/invites/list", revokeInvitation = "teams/invites/revoke"
    var requiresSession: Bool { ![.preview, .invitedChallenge, .invitedExchange].contains(self) }
}
enum TeamInvitationRole: String, Sendable { case member = "MEMBER", reviewer = "REVIEWER" }
enum TeamMembershipRole: String, Sendable { case owner = "OWNER", member = "MEMBER", reviewer = "REVIEWER" }
enum TeamInvitationState: String, Sendable { case pending = "PENDING", claimed = "CLAIMED", expired = "EXPIRED", accepted = "ACCEPTED", revoked = "REVOKED" }
protocol TeamOnboardingDiagnostic: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}
extension TeamOnboardingDiagnostic {
    var description: String { "\(Self.self)(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
struct TeamInvitationPreview: TeamOnboardingDiagnostic {
    let inviteID: String
    let teamID: String
    let role: TeamInvitationRole
    let expiresAt: Int64
}
struct TeamIssuedInvitation: TeamOnboardingDiagnostic {
    let preview: TeamInvitationPreview
    let token: String
}
struct TeamInvitationListEntry: TeamOnboardingDiagnostic {
    let inviteID: String
    let role: TeamInvitationRole
    let state: TeamInvitationState
    let expiresAt: Int64
}
struct TeamRegisteredDevice: TeamOnboardingDiagnostic {
    let enrollmentID: String
    let accountID: String
    let deviceID: String
    let keyThumbprint: String
    let authorityEpoch: String
}
struct TeamMembership: TeamOnboardingDiagnostic {
    let teamID: String
    let accountID: String
    let enrollmentID: String
    let role: TeamMembershipRole
    let revision: Int64
}
struct TeamPreparedDeviceChallenge: TeamOnboardingDiagnostic {
    let challengeID: String
    let expiresAt: Int64
    fileprivate let wire: Data
    init(validating wire: Data, expected: TeamDeviceEnrollmentWire.Binding, now: Int64) throws {
        _ = try TeamDeviceEnrollmentWire.message(challenge: wire, expected: expected, now: now)
        let object = try TeamStrictJSON.object(wire)
        challengeID = try TeamAuthWire.string(object, "challengeId", secret: true)
        expiresAt = try TeamAuthWire.time(object, "expiresAt")
        self.wire = wire
    }
    // Caller must still recheck durable generation/monotonic lifetime and current
    // session immediately before using these bytes with its dedicated device key.
    func message(expected: TeamDeviceEnrollmentWire.Binding, now: Int64) throws -> Data {
        try TeamDeviceEnrollmentWire.message(challenge: wire, expected: expected, now: now)
    }
}

private enum TeamOnboardingWire {
    static func exact(_ object: [String: Any], _ keys: Set<String>) throws {
        guard Set(object.keys) == keys else { throw TeamAuthHTTPError.invalidResponse }
    }
    static func preview(_ object: [String: Any], now: Int64) throws -> TeamInvitationPreview {
        let expiry = try TeamAuthWire.time(object, "expiresAt")
        guard let role = (object["role"] as? String).flatMap(TeamInvitationRole.init(rawValue:)),
              expiry > now, expiry - now <= 604_805_000 else { throw TeamAuthHTTPError.invalidResponse }
        return try .init(inviteID: TeamAuthWire.string(object, "inviteId"), teamID: TeamAuthWire.string(object, "teamId"), role: role, expiresAt: expiry)
    }
    static func registration(_ object: [String: Any], expected: TeamDeviceEnrollmentWire.Binding) throws -> TeamRegisteredDevice {
        try exact(object, ["enrollmentId", "accountId", "deviceId", "keyThumbprint", "authorityEpoch"])
        let result = try TeamRegisteredDevice(enrollmentID: TeamAuthWire.string(object, "enrollmentId"),
            accountID: TeamAuthWire.string(object, "accountId"), deviceID: TeamAuthWire.string(object, "deviceId"),
            keyThumbprint: TeamAuthWire.string(object, "keyThumbprint", secret: true), authorityEpoch: TeamAuthWire.string(object, "authorityEpoch"))
        guard result.accountID == expected.accountID, result.deviceID == expected.deviceID,
              result.keyThumbprint == expected.keyThumbprint, result.authorityEpoch == expected.authorityEpoch else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return result
    }
    static func membership(_ data: Data, teamID: String, enrollmentID: String, accountID: String, role: TeamMembershipRole? = nil) throws -> TeamMembership {
        let object = try TeamAuthWire.object(data, keys: ["teamId", "accountId", "enrollmentId", "role", "membershipRevision"])
        guard let actualRole = (object["role"] as? String).flatMap(TeamMembershipRole.init(rawValue:)) else { throw TeamAuthHTTPError.invalidResponse }
        let result = try TeamMembership(teamID: TeamAuthWire.string(object, "teamId"), accountID: TeamAuthWire.string(object, "accountId"),
            enrollmentID: TeamAuthWire.string(object, "enrollmentId"), role: actualRole, revision: TeamAuthWire.time(object, "membershipRevision"))
        guard result.teamID == teamID, result.enrollmentID == enrollmentID, result.accountID == accountID,
              role == nil || role == actualRole else { throw TeamAuthHTTPError.invalidResponse }
        return result
    }
    static func ids(_ values: String...) throws {
        guard values.allSatisfy(TeamAuthWire.identifier) else { throw TeamAuthHTTPError.invalidRequest }
    }
    static func token(_ value: String) throws {
        guard TeamAuthWire.credential(value) else { throw TeamAuthHTTPError.invalidRequest }
    }
}

/// All methods share this exact client's native unresolved slot with ordinary
/// login/refresh/logout. No routes are constructed from IDs; no automatic retry,
/// sign-out or durable authority mutation. Higher-level consent/ownership required.
extension TeamAuthHTTPClient {
    func previewInvitation(token: String) async throws -> TeamInvitationPreview {
        try TeamOnboardingWire.token(token)
        let reply = try await onboarding(.preview, fields: ["token": token])
        return try TeamOnboardingWire.preview(TeamAuthWire.object(reply.data, keys: ["inviteId", "teamId", "role", "expiresAt"]), now: reply.receivedAt)
    }
    func invitedChallenge(providerID: String, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthChallenge {
        try TeamOnboardingWire.ids(providerID, teamID); try TeamOnboardingWire.token(token)
        let reply = try await onboarding(.invitedChallenge, fields: ["providerId": providerID, "token": token, "teamId": teamID, "role": role.rawValue])
        let result = try TeamAuthWire.challenge(reply.data)
        guard result.expiresAt > reply.receivedAt, result.expiresAt - reply.receivedAt <= 120_000 else { throw TeamAuthHTTPError.invalidResponse }
        return result
    }
    func invitedExchange(_ submission: TeamNativeLoginSubmission, token: String, teamID: String, role: TeamInvitationRole) async throws -> TeamAuthSessionPair {
        try TeamOnboardingWire.ids(submission.providerID, teamID); try TeamOnboardingWire.token(token)
        guard TeamAuthWire.credential(submission.challengeID), (1...16_384).contains(submission.idToken.utf8.count),
              submission.idToken.utf8.allSatisfy({ TeamAuthWire.urlByte($0) || $0 == 46 }),
              submission.idToken.split(separator: ".", omittingEmptySubsequences: false).count == 3,
              !submission.idToken.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty) else { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.invitedExchange, fields: ["providerId": submission.providerID, "token": token,
            "teamId": teamID, "role": role.rawValue, "challengeId": submission.challengeID, "idToken": submission.idToken])
        let pair = try TeamAuthWire.pair(reply.data)
        guard pair.accessExpiresAt > reply.receivedAt, pair.accessExpiresAt - reply.receivedAt <= 905_000,
              pair.sessionExpiresAt - reply.receivedAt <= 2_592_005_000 else { throw TeamAuthHTTPError.invalidResponse }
        return pair
    }
    func deviceChallenge(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                         session: TeamAccountSessionSnapshot) async throws -> TeamPreparedDeviceChallenge {
        try await deviceChallenge(key: key, expected: expected, ticket: .init(snapshot: session))
    }
    func deviceChallenge(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                         ticket: TeamAccountAccessTicket) async throws -> TeamPreparedDeviceChallenge {
        guard acceptsDeviceBinding(expected, ticket: ticket), key.thumbprint == expected.keyThumbprint else { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deviceChallenge, fields: ["deviceId": expected.deviceID, "publicKey": key.jwk], ticket: ticket)
        do { return try .init(validating: reply.data, expected: expected, now: reply.receivedAt) }
        catch { throw TeamAuthHTTPError.invalidResponse }
    }
    func completeDevice(challenge: TeamPreparedDeviceChallenge, signature: Data, expected: TeamDeviceEnrollmentWire.Binding,
                        session: TeamAccountSessionSnapshot) async throws -> TeamRegisteredDevice {
        try await completeDevice(challenge: challenge, signature: signature, expected: expected, ticket: .init(snapshot: session))
    }
    func completeDevice(challenge: TeamPreparedDeviceChallenge, signature: Data, expected: TeamDeviceEnrollmentWire.Binding,
                        ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice {
        guard acceptsDeviceBinding(expected, ticket: ticket), signature.count == 64 else { throw TeamAuthHTTPError.invalidRequest }
        do { _ = try challenge.message(expected: expected, now: onboardingTime()) }
        catch { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deviceComplete, fields: ["challengeId": challenge.challengeID,
            "signature": TeamDeviceEnrollmentWire.encode(signature)], ticket: ticket)
        return try TeamOnboardingWire.registration(TeamStrictJSON.object(reply.data), expected: expected)
    }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                      session: TeamAccountSessionSnapshot) async throws -> TeamRegisteredDevice? {
        try await lookupDevice(key: key, expected: expected, ticket: .init(snapshot: session))
    }
    func lookupDevice(key: TeamDeviceEnrollmentWire.PublicKey, expected: TeamDeviceEnrollmentWire.Binding,
                      ticket: TeamAccountAccessTicket) async throws -> TeamRegisteredDevice? {
        guard acceptsDeviceBinding(expected, ticket: ticket), key.thumbprint == expected.keyThumbprint else { throw TeamAuthHTTPError.invalidRequest }
        let reply = try await onboarding(.deviceLookup, fields: ["deviceId": expected.deviceID, "publicKey": key.jwk], ticket: ticket)
        let object = try TeamAuthWire.object(reply.data, keys: ["registration"])
        if object["registration"] is NSNull { return nil }
        guard let registration = object["registration"] as? [String: Any] else { throw TeamAuthHTTPError.invalidResponse }
        return try TeamOnboardingWire.registration(registration, expected: expected)
    }
    func revokeDevice(enrollmentID: String, session: TeamAccountSessionSnapshot) async throws {
        try TeamOnboardingWire.ids(enrollmentID)
        let reply = try await onboarding(.deviceRevoke, fields: ["enrollmentId": enrollmentID], session: session)
        let object = try TeamAuthWire.object(reply.data, keys: ["enrollmentId", "active"])
        guard try TeamAuthWire.string(object, "enrollmentId") == enrollmentID,
              try TeamAuthWire.boolean(object, "active") == false else { throw TeamAuthHTTPError.invalidResponse }
    }
    func createTeam(teamID: String, enrollmentID: String, session: TeamAccountSessionSnapshot) async throws -> TeamMembership {
        try TeamOnboardingWire.ids(teamID, enrollmentID)
        let reply = try await onboarding(.createTeam, fields: ["teamId": teamID, "enrollmentId": enrollmentID], session: session)
        return try TeamOnboardingWire.membership(reply.data, teamID: teamID, enrollmentID: enrollmentID, accountID: session.accountID, role: .owner)
    }
    func currentTeam(teamID: String, enrollmentID: String, session: TeamAccountSessionSnapshot) async throws -> TeamMembership {
        try TeamOnboardingWire.ids(teamID, enrollmentID)
        let reply = try await onboarding(.currentTeam, fields: ["teamId": teamID, "enrollmentId": enrollmentID], session: session)
        return try TeamOnboardingWire.membership(reply.data, teamID: teamID, enrollmentID: enrollmentID, accountID: session.accountID)
    }
    func acceptInvitation(token: String, teamID: String, enrollmentID: String, role: TeamInvitationRole,
                          session: TeamAccountSessionSnapshot) async throws -> TeamMembership {
        try TeamOnboardingWire.ids(teamID, enrollmentID); try TeamOnboardingWire.token(token)
        let reply = try await onboarding(.acceptInvitation, fields: ["token": token, "teamId": teamID, "enrollmentId": enrollmentID, "role": role.rawValue], session: session)
        return try TeamOnboardingWire.membership(reply.data, teamID: teamID, enrollmentID: enrollmentID, accountID: session.accountID,
            role: role == .member ? .member : .reviewer)
    }
    func issueInvitation(teamID: String, enrollmentID: String, role: TeamInvitationRole, session: TeamAccountSessionSnapshot) async throws -> TeamIssuedInvitation {
        try TeamOnboardingWire.ids(teamID, enrollmentID)
        let reply = try await onboarding(.issueInvitation, fields: ["teamId": teamID, "enrollmentId": enrollmentID, "role": role.rawValue], session: session)
        let object = try TeamAuthWire.object(reply.data, keys: ["inviteId", "teamId", "role", "expiresAt", "token"])
        let preview = try TeamOnboardingWire.preview(object, now: reply.receivedAt), token = try TeamAuthWire.string(object, "token", secret: true)
        guard preview.teamID == teamID, preview.role == role, token != session.pair?.accessToken, token != session.pair?.refreshToken else { throw TeamAuthHTTPError.invalidResponse }
        return .init(preview: preview, token: token)
    }
    func listInvitations(teamID: String, enrollmentID: String, session: TeamAccountSessionSnapshot) async throws -> [TeamInvitationListEntry] {
        try TeamOnboardingWire.ids(teamID, enrollmentID)
        let reply = try await onboarding(.listInvitations, fields: ["teamId": teamID, "enrollmentId": enrollmentID], session: session)
        let object = try TeamAuthWire.object(reply.data, keys: ["invitations"])
        guard let rows = object["invitations"] as? [[String: Any]], rows.count <= 100 else { throw TeamAuthHTTPError.invalidResponse }
        var ids = Set<String>()
        return try rows.map { row in
            try TeamOnboardingWire.exact(row, ["inviteId", "role", "state", "expiresAt"])
            let id = try TeamAuthWire.string(row, "inviteId")
            guard ids.insert(id).inserted, let role = (row["role"] as? String).flatMap(TeamInvitationRole.init(rawValue:)),
                  let state = (row["state"] as? String).flatMap(TeamInvitationState.init(rawValue:)) else { throw TeamAuthHTTPError.invalidResponse }
            return try .init(inviteID: id, role: role, state: state, expiresAt: TeamAuthWire.time(row, "expiresAt"))
        }
    }
    func revokeInvitation(teamID: String, enrollmentID: String, inviteID: String, session: TeamAccountSessionSnapshot) async throws {
        try TeamOnboardingWire.ids(teamID, enrollmentID, inviteID)
        let reply = try await onboarding(.revokeInvitation, fields: ["teamId": teamID, "enrollmentId": enrollmentID, "inviteId": inviteID], session: session)
        let object = try TeamAuthWire.object(reply.data, keys: ["inviteId", "state"])
        guard try TeamAuthWire.string(object, "inviteId") == inviteID, object["state"] as? String == "REVOKED" else { throw TeamAuthHTTPError.invalidResponse }
    }
}
