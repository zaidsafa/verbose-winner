import SwiftUI

struct TeamInvitationWorkflowView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinbookSkin) private var skin
    @State private var model: TeamInvitationWorkflowModel
    init(model: TeamInvitationWorkflowModel) { _model = State(initialValue: model) }
    var body: some View {
        Group {
            switch model.step {
            case .account:
                TeamInvitationAccountView(model: model.account, isTransitioning: model.isTransitioning,
                    onContinue: { Task { await model.continueFromAccount() } }, onClose: close)
            case .device:
                if let device = model.device {
                    TeamDeviceRegistrationView(model: device, isTransitioning: model.isTransitioning,
                        onContinue: { Task { await model.continueFromDevice() } }, onClose: close)
                }
            case .membership:
                if let membership = model.membership { TeamMembershipView(model: membership, onClose: close) }
            case .failed, .closed:
                NavigationStack {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Team membership").font(.largeTitle.bold())
                        Text(model.step == .closed ? "Team setup closed. Open the invitation again to continue." :
                            "Setup could not continue. Close this screen and reopen the invitation.")
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("invitation-workflow-status")
                        if model.cleanupFailed { Text("Account cleanup could not be confirmed. Do not retry this invitation yet.") }
                        Spacer()
                    }
                    .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                    .background(skin.backdrop.ignoresSafeArea()).foregroundStyle(.primary)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", role: .cancel, action: close) } }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.close() } }
        .onDisappear { model.close() }
    }
    private func close() { model.close(); dismiss() }
}

#if DEBUG
private actor TeamWorkflowDebugMembership: TeamMembershipScreenService {
    nonisolated let context = TeamMembershipScreenContext(accountID: "public-test-account", teamID: "public-test-team", invitedRole: .reviewer)
    func review() async throws -> TeamMembershipRetryPreparation {
        .ready(.init(accountID: context.accountID, teamID: context.teamID, role: .reviewer))
    }
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot {
        guard consent else { throw TeamMembershipJoinError.consentRequired }; return try result()
    }
    func recover() async throws -> TeamJoinSnapshot { try result() }
    func close() async {}
    private func result() throws -> TeamJoinSnapshot {
        try .init(scope: .init(audience: "https://pinbook.example", accountID: context.accountID, authorityEpoch: "public-epoch"),
            teamID: context.teamID, enrollmentID: "public-enrollment", role: .reviewer,
            invitationHash: String(repeating: "a", count: 64), generation: UUID(), phase: .confirmed, checkedAt: 1_000, membershipRevision: 1)
    }
}
private actor TeamWorkflowDebugDevice: TeamDeviceRegistrationScreenService {
    nonisolated let context = TeamInvitationDeviceContext(accountID: "public-test-account", teamID: "public-test-team", role: .reviewer)
    private let scenario: String
    private var attempts = 0
    init(scenario: String) { self.scenario = scenario }
    func register(consent: Bool) async throws -> TeamDeviceRegistrationScreenResult {
        guard consent else { throw TeamDeviceCustodyError.consentRequired }; attempts += 1
        if scenario == "retry", attempts == 1 { return .waiting(until: Int64(Date.now.timeIntervalSince1970 * 1_000)) }
        if scenario == "retry", attempts == 2 { return .retryReady }
        if scenario == "uncertain", attempts == 1 { throw TeamDeviceRegistrationError.transportFailure }
        return .registered
    }
    func membership() async throws -> any TeamMembershipScreenService { TeamWorkflowDebugMembership() }
    func close() async {}
}
/// Public synthetic UI only: never accesses Keychain, providers, network or stored records.
struct TeamInvitationWorkflowDebugHost: View {
    @State private var model: TeamInvitationWorkflowModel
    private let configuration: PinbookLaunchConfiguration
    init(configuration: PinbookLaunchConfiguration) {
        self.configuration = configuration
        let scenario = configuration.invitationWorkflowFixtureScenario
        _model = State(initialValue: .init(source: .init(account:
            TeamInvitationAccountDebugService(scenario: scenario == "existing" ? "existing" : "new"),
            device: { _ in TeamWorkflowDebugDevice(scenario: scenario) })))
    }
    var body: some View {
        TeamInvitationWorkflowView(model: model)
            .environment(\.pinbookSkin, configuration.skin ?? .paperGlass)
            .preferredColorScheme(configuration.themeMode == "dark" ? .dark : configuration.themeMode == "light" ? .light : nil)
    }
}
#endif
