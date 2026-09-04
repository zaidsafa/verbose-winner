import Foundation
import Observation

struct TeamInvitationWorkflowSource: Sendable {
    let account: any TeamInvitationAccountScreenService
    let device: @Sendable (TeamInvitationAccountReceipt) async throws -> any TeamDeviceRegistrationScreenService
    static func connected(accountScreen: TeamInvitationAccountScreenBridge, authorityEpoch: String,
                          sessions: TeamAccountSessionStore, custody: TeamDeviceCustody, joins: TeamJoinStore,
                          transport: any TeamDeviceRegistering & TeamMembershipTransport,
                          clock: @escaping @Sendable () -> TeamSignInMoment = { .current() }) -> Self {
        .init(account: accountScreen, device: { receipt in
            let flow = try await TeamInvitationDeviceFlow.begin(accountScreen: accountScreen, receipt: receipt,
                authorityEpoch: authorityEpoch, sessions: sessions, custody: custody, joins: joins,
                transport: transport, clock: clock)
            return TeamDeviceRegistrationScreenBridge(flow: flow)
        })
    }
}
enum TeamInvitationWorkflowStep: Equatable { case account, device, membership, failed, closed }

/// Retained parent owns all transition tasks. No automatic I/O on initialization,
/// appearance or step publication. Host must invalidate on external account changes.
@MainActor @Observable
final class TeamInvitationWorkflowModel {
    let account: TeamInvitationAccountScreenModel
    private(set) var device: TeamDeviceRegistrationScreenModel?
    private(set) var membership: TeamMembershipScreenModel?
    private(set) var step = TeamInvitationWorkflowStep.account
    private(set) var isTransitioning = false
    private(set) var cleanupFailed = false
    @ObservationIgnored private let source: TeamInvitationWorkflowSource
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: Task<Product, Error>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    private enum Product: Sendable {
        case device(any TeamDeviceRegistrationScreenService), membership(any TeamMembershipScreenService)
        func close() async {
            switch self { case .device(let value): await value.close(); case .membership(let value): await value.close() }
        }
    }
    init(source: TeamInvitationWorkflowSource) {
        self.source = source; account = .init(service: source.account)
    }
    func continueFromAccount() async {
        guard step == .account, account.stage == .complete, let receipt = account.receipt,
              !isTransitioning, !Task.isCancelled else { return }
        let factory = source.device
        await transition(expected: .init(accountID: receipt.accountID, teamID: receipt.teamID, role: receipt.role)) {
            .device(try await factory(receipt))
        }
    }
    func continueFromDevice() async {
        guard step == .device, let device, device.canContinue, !isTransitioning, !Task.isCancelled else { return }
        await transition(expected: device.context) { .membership(try await device.membership()) }
    }
    /// Use for external account/session replacement, code edits and backgrounding.
    /// A legitimate account commit owned by this sign-in flow is not an external replacement.
    func close() {
        guard step != .closed else { return }
        generation = UUID(); step = .closed; isTransitioning = false
        let pending = operation, account = account, device = device, membership = membership
        operation = nil; pending?.cancel()
        account.close(); device?.close(); membership?.close()
        self.device = nil; self.membership = nil
        cleanup = Task {
            if case .success(let late) = await pending?.result { await late.close() }
            await account.waitForCleanup(); await device?.waitForCleanup(); await membership?.waitForCleanup()
            cleanupFailed = account.cleanupFailed
        }
    }
    func waitForCleanup() async { await cleanup?.value }
    private func transition(expected: TeamInvitationDeviceContext,
                            action: @escaping @Sendable () async throws -> Product) async {
        guard operation == nil, step != .closed else { return }
        let id = UUID(); generation = id; isTransitioning = true
        let task = Task { try Task.checkCancellation(); return try await action() }
        operation = task
        defer { if generation == id { operation = nil; isTransitioning = false } }
        var produced: Product?
        do {
            let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            produced = value
            try Task.checkCancellation()
            guard generation == id, step != .closed else { await value.close(); return }
            switch value {
            case .device(let service):
                guard service.context.accountID == expected.accountID, service.context.teamID == expected.teamID,
                      service.context.role == expected.role else { throw TeamDeviceRegistrationError.invalidated }
                let next = try TeamDeviceRegistrationScreenModel(service: service)
                account.close(); await account.waitForCleanup()
                guard !account.cleanupFailed else { throw TeamInvitationAccountError.accountUnavailable }
                try Task.checkCancellation()
                guard generation == id, step != .closed else { await value.close(); return }
                device = next; step = .device
            case .membership(let service):
                guard service.context.accountID == expected.accountID, service.context.teamID == expected.teamID,
                      service.context.invitedRole == expected.role, !service.context.isRetry else {
                    throw TeamMembershipJoinError.invalidIntent
                }
                let next = try TeamMembershipScreenModel(service: service)
                device?.close(); await device?.waitForCleanup()
                try Task.checkCancellation()
                guard generation == id, step != .closed else { await value.close(); return }
                device = nil; membership = next; step = .membership
            }
        } catch {
            await produced?.close()
            guard generation == id, step != .closed else { return }
            account.close(); device?.close(); membership?.close()
            await account.waitForCleanup(); await device?.waitForCleanup(); await membership?.waitForCleanup()
            guard generation == id, step != .closed else { return }
            cleanupFailed = account.cleanupFailed; device = nil; membership = nil; step = .failed
        }
    }
}
