import Foundation
import Observation

enum TeamDeviceRegistrationScreenResult: Sendable {
    case registered, waiting(until: Int64), retryReady
}
protocol TeamDeviceRegistrationScreenService: Sendable {
    var context: TeamInvitationDeviceContext { get }
    func register(consent: Bool) async throws -> TeamDeviceRegistrationScreenResult
    func membership() async throws -> any TeamMembershipScreenService
    func close() async
}
actor TeamDeviceRegistrationScreenBridge: TeamDeviceRegistrationScreenService {
    nonisolated let context: TeamInvitationDeviceContext
    private let flow: TeamInvitationDeviceFlow
    init(flow: TeamInvitationDeviceFlow) { self.flow = flow; context = flow.context }
    func register(consent: Bool) async throws -> TeamDeviceRegistrationScreenResult {
        switch try await flow.register(consent: consent) {
        case .registered: return .registered
        case .recoveryWait(let until): return .waiting(until: until)
        case .retryReady: return .retryReady
        }
    }
    func membership() async throws -> any TeamMembershipScreenService { try await flow.takeMembershipScreen() }
    func close() async { await flow.close() }
}
enum TeamDeviceRegistrationScreenStage: Equatable, Sendable {
    case ready, registering, waiting, retryReady, uncertain, registered, closed
}
@MainActor @Observable
final class TeamDeviceRegistrationScreenModel {
    let context: TeamInvitationDeviceContext
    private(set) var stage = TeamDeviceRegistrationScreenStage.ready
    private(set) var agreed = false
    private(set) var waitUntil: Int64?
    @ObservationIgnored private let service: any TeamDeviceRegistrationScreenService
    @ObservationIgnored private var operation: Task<TeamDeviceRegistrationScreenResult, Error>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    init(service: any TeamDeviceRegistrationScreenService) throws {
        context = service.context
        guard TeamAuthWire.identifier(context.accountID), TeamAuthWire.identifier(context.teamID) else {
            throw TeamDeviceRegistrationError.invalidated
        }
        self.service = service
    }
    var offersConsent: Bool { [.ready, .waiting, .retryReady, .uncertain].contains(stage) }
    var canRegister: Bool { offersConsent && agreed }
    var canContinue: Bool { stage == .registered }
    func setAgreement(_ value: Bool) { if offersConsent { agreed = value } }
    func register() async {
        guard canRegister, operation == nil, !Task.isCancelled else { return }
        let id = UUID(); generation = id; stage = .registering; agreed = false; waitUntil = nil
        let service = service
        let task = Task { try Task.checkCancellation(); return try await service.register(consent: true) }
        operation = task
        defer { if generation == id { operation = nil } }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == id, stage != .closed else { return }
            switch result {
            case .registered: stage = .registered
            case .retryReady: stage = .retryReady
            case .waiting(let until):
                guard until > 0, until <= TeamAuthWire.maximumSafeTime else { throw TeamDeviceRegistrationError.expired }
                waitUntil = until; stage = .waiting
            }
        } catch {
            guard generation == id, stage != .closed else { return }
            stage = .uncertain; waitUntil = nil
        }
    }
    /// Parent owns/cancels this transfer task and closes any late returned child.
    func membership() async throws -> any TeamMembershipScreenService {
        guard canContinue else { throw TeamDeviceRegistrationError.registrationUnavailable }
        try Task.checkCancellation()
        return try await service.membership()
    }
    func close() {
        guard stage != .closed else { return }
        stage = .closed; generation = UUID(); agreed = false; waitUntil = nil
        let pending = operation, service = service
        pending?.cancel(); operation = nil
        cleanup = Task { await service.close(); _ = await pending?.result }
    }
    func waitForCleanup() async { await cleanup?.value }
}
