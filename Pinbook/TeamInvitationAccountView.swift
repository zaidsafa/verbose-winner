import SwiftUI

/// Invitation preflight, not a provider-branded sign-in button or membership UI.
/// Kept outside normal navigation until the parent account/device workflow is ready.
struct TeamInvitationAccountView: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var model: TeamInvitationAccountScreenModel
    init(model: TeamInvitationAccountScreenModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: model.stage == .complete ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 42, weight: .semibold)).foregroundStyle(skin.accent)
                        .accessibilityHidden(true)
                    Text("Account access").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(statusMessage).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("invitation-account-status")
                    if let details = model.reviewDetails {
                        VStack(alignment: .leading, spacing: 18) {
                            identity("Team", value: details.teamID, identifier: "invitation-account-team")
                            if let account = model.receipt?.accountID ?? details.accountID {
                                identity("Account", value: account, identifier: "invitation-account-identity")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Role").font(.subheadline).foregroundStyle(.secondary)
                                Text(details.role == .member ? "Member" : "Reviewer").font(.headline)
                                    .accessibilityIdentifier("invitation-account-role")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                        .background(skin.contentSurface, in: RoundedRectangle(cornerRadius: 26))
                        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.primary.opacity(0.08), lineWidth: 1) }
                        .transition(.opacity)
                    }
                    if model.stage != .closed {
                        Label("Signing in does not register this device or join the team.", systemImage: "lock.shield")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("invitation-account-privacy")
                    }
                    if model.stage == .reviewed && model.reviewDetails?.accountID == nil {
                        Toggle(isOn: Binding(get: { model.agreed }, set: { model.setAgreement($0) })) {
                            Text("I agree to sign in for this invitation.").fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: 48).accessibilityIdentifier("invitation-account-consent")
                    }
                    if model.isWorking {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                            .accessibilityLabel(Text("Account access"))
                    }
                    if model.canReview {
                        Button { Task { await model.review() } } label: {
                            Text("Review invitation").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.pinbookProminent).accessibilityIdentifier("invitation-account-review")
                    }
                    if model.stage == .reviewed {
                        Button { Task { await model.access() } } label: {
                            Text(model.reviewDetails?.accountID == nil ? "Continue to sign in" : "Continue with this account")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.pinbookProminent).disabled(!model.canAccess)
                        .accessibilityIdentifier("invitation-account-access")
                    }
                    if model.stage == .complete {
                        Button("Done") { close() }.buttonStyle(.pinbookProminent)
                            .frame(minHeight: 44).accessibilityIdentifier("invitation-account-done")
                    }
                }
                .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.stage)
            }
            .background(skin.backdrop.ignoresSafeArea()).foregroundStyle(.primary).tint(skin.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) { close() }.accessibilityIdentifier("invitation-account-close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(skin.preferredScheme)
        // Provider modal inactivity is not backgrounding.
        .onChange(of: scenePhase) { _, value in if value == .background { model.close() } }
        .onDisappear { model.close() }
    }
    private func identity(_ title: LocalizedStringKey, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value).font(.body.monospaced()).environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true).privacySensitive().accessibilityIdentifier(identifier)
        }
    }
    private var statusMessage: LocalizedStringKey {
        if model.cleanupFailed { return "Account cleanup could not be confirmed. Do not retry this invitation yet." }
        switch model.stage {
        case .accessing: return "Checking account access…"
        case .reviewFailed: return "The invitation could not be reviewed. You can review it again or close this screen."
        case .uncertain: return "Account access could not be confirmed. Close this screen before signing in again."
        case .complete: return "Account access is ready. Registering this device and joining need separate confirmation."
        case .closed: return "Account screen closed. Open the invitation again to continue."
        default: return "Review the team and role before signing in."
        }
    }
    private func close() { model.close(); dismiss() }
}

#if DEBUG
/// Synthetic presentation only: no Keychain, real account, provider or transport.
private actor TeamInvitationAccountDebugService: TeamInvitationAccountScreenService {
    private let scenario: String
    init(scenario: String) { self.scenario = scenario }
    func review() async throws -> TeamInvitationAccountReview {
        .init(teamID: "public-test-team", role: .reviewer, expiresAt: 2_000_000_000_000,
            accountID: scenario == "existing" ? "public-test-account" : nil)
    }
    func access(_ review: TeamInvitationAccountReview, consent: Bool) async throws -> TeamInvitationAccountReceipt {
        guard review.accountID != nil || consent else { throw TeamInvitationAccountError.consentRequired }
        if scenario == "uncertain" { throw TeamInvitationAccountError.accountUnavailable }
        return .init(teamID: review.teamID, role: review.role, accountID: "public-test-account")
    }
    func close() async throws {}
}
struct TeamInvitationAccountDebugHost: View {
    @State private var model: TeamInvitationAccountScreenModel
    private let configuration: PinbookLaunchConfiguration
    init(configuration: PinbookLaunchConfiguration) {
        self.configuration = configuration
        _model = State(initialValue: TeamInvitationAccountScreenModel(service:
            TeamInvitationAccountDebugService(scenario: configuration.invitationAccountFixtureScenario)))
    }
    var body: some View {
        TeamInvitationAccountView(model: model)
            .environment(\.pinbookSkin, configuration.skin ?? .paperGlass)
            .preferredColorScheme(configuration.themeMode == "dark" ? .dark : configuration.themeMode == "light" ? .light : nil)
    }
}
#endif
