import SwiftUI

/// Modal only; not linked from normal navigation until team activation gates pass.
/// Parent must dismiss/recreate when account/session generation changes.
struct TeamMembershipView: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var model: TeamMembershipScreenModel
    private let onClose: (() -> Void)?

    init(model: TeamMembershipScreenModel, onClose: (() -> Void)? = nil) {
        _model = State(initialValue: model); self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: model.stage == .confirmed ? "checkmark.shield.fill" : "person.2.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(skin.accent)
                        .accessibilityHidden(true)
                    Text("Team membership")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(statusMessage)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("membership-status")

                    if let details = model.details {
                        VStack(alignment: .leading, spacing: 18) {
                            identity("Team", value: details.teamID, identifier: "membership-team")
                            identity("Account", value: details.accountID, identifier: "membership-account")
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Role").font(.subheadline).foregroundStyle(.secondary)
                                Text(details.role == .member ? "Member" : "Reviewer").font(.headline)
                                    .accessibilityIdentifier("membership-role")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .background(skin.contentSurface, in: RoundedRectangle(cornerRadius: 26))
                        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.primary.opacity(0.08), lineWidth: 1) }
                        .transition(.opacity)
                    }

                    if model.stage != .closed {
                        Label("Joining does not share your existing private notes.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("membership-privacy")
                    }

                    if model.stage == .consent {
                        Toggle(isOn: Binding(get: { model.agreed }, set: { model.setAgreement($0) })) {
                            Text(model.context.isRetry ? "I agree to retry joining this team with the role shown." : "I agree to join this team with the role shown.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("membership-consent")
                    }
                    if model.isWorking {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                            .accessibilityLabel(Text("Team membership"))
                            .accessibilityIdentifier("membership-progress")
                    }
                    actions
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.stage)
            }
            .background(skin.backdrop.ignoresSafeArea())
            .foregroundStyle(.primary)
            .tint(skin.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) { close() }
                        .accessibilityIdentifier("membership-close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(skin.preferredScheme)
        .onChange(of: scenePhase) { _, value in if value == .background { model.close() } }
        .onDisappear { model.close() }
    }

    @ViewBuilder private var actions: some View {
        if model.canReview {
            Button { Task { await model.review() } } label: {
                Text(model.context.isRetry ? "Check previous join" : "Review invitation").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.pinbookProminent)
            .accessibilityIdentifier("membership-review")
        }
        if model.stage == .consent {
            Button { Task { await model.join() } } label: {
                Text(model.context.isRetry ? "Retry join" : "Join team").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.pinbookProminent)
            .disabled(!model.canJoin)
            .accessibilityIdentifier("membership-join")
        }
        if model.canCheck {
            Text("Checking membership uses your saved team details. It does not resend a join request.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.checkMembership() } } label: {
                Text("Check membership").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.pinbookProminent)
            .accessibilityIdentifier("membership-check")
        }
        if model.stage == .confirmed {
            Button("Done") { close() }.buttonStyle(.pinbookProminent)
                .frame(minHeight: 44).accessibilityIdentifier("membership-done")
        }
    }
    private func identity(_ title: LocalizedStringKey, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value).font(.body.monospaced())
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitive()
                .accessibilityIdentifier(identifier)
        }
    }
    private var statusMessage: LocalizedStringKey {
        switch model.stage {
        case .ready where model.context.isRetry, .reviewing where model.context.isRetry:
            "Check the previous attempt before sending another join request."
        case .consent where model.context.isRetry:
            "The previous join is still pending. Confirm again to retry the same invitation."
        case .reviewFailed where model.context.isRetry:
            "The previous attempt could not be checked. You can check it again or close this screen."
        case .ready where model.context.invitedRole == nil: "Check whether this account still belongs to the team."
        case .joining: "Joining team…"
        case .checking: "Check membership"
        case .uncertain: "We couldn't confirm the result. Check membership before trying anything else."
        case .reviewFailed: "The invitation could not be reviewed. You can review it again or close this screen."
        case .confirmed: "Your membership is confirmed. Shared-note delivery is not enabled yet."
        case .closed: "Membership screen closed. Open it again to continue."
        default: "Review the team and role before joining."
        }
    }
    private func close() { model.close(); if let onClose { onClose() } else { dismiss() } }
}

#if DEBUG
/// Public in-memory presentation only. Never reads accounts/Keychain or sends HTTP.
private actor TeamMembershipDebugService: TeamMembershipScreenService {
    nonisolated let context: TeamMembershipScreenContext
    private let uncertain: Bool
    private let retryJoined: Bool
    init(scenario: String) {
        context = .init(accountID: "public-test-account", teamID: "public-test-team", invitedRole: scenario == "recovery" ? nil : .member,
            isRetry: scenario == "retry-pending" || scenario == "retry-joined")
        uncertain = scenario == "uncertain"
        retryJoined = scenario == "retry-joined"
    }
    func review() async throws -> TeamMembershipRetryPreparation {
        if retryJoined { return .joined(try result()) }
        return .ready(.init(accountID: context.accountID, teamID: context.teamID, role: .member))
    }
    func join(_ preview: TeamMembershipJoinPreview, consent: Bool) async throws -> TeamJoinSnapshot {
        guard consent else { throw TeamMembershipJoinError.consentRequired }
        if uncertain { throw TeamMembershipJoinError.transportFailure }
        return try result()
    }
    func recover() async throws -> TeamJoinSnapshot { try result() }
    func close() async {}
    private func result() throws -> TeamJoinSnapshot {
        try .init(scope: .init(audience: "https://pinbook.example", accountID: context.accountID, authorityEpoch: "public-epoch"),
            teamID: context.teamID, enrollmentID: "public-enrollment", role: .member,
            invitationHash: String(repeating: "a", count: 64), generation: UUID(), phase: .confirmed, checkedAt: 1_000, membershipRevision: 1)
    }
}
struct TeamMembershipDebugHost: View {
    @State private var model: TeamMembershipScreenModel?
    private let configuration: PinbookLaunchConfiguration
    init(configuration: PinbookLaunchConfiguration) {
        self.configuration = configuration
        _model = State(initialValue: try? TeamMembershipScreenModel(service: TeamMembershipDebugService(scenario: configuration.membershipFixtureScenario)))
    }
    var body: some View {
        Group {
            if let model { TeamMembershipView(model: model) }
            else { ContentUnavailableView("Team membership", systemImage: "person.2.fill") }
        }
        .environment(\.pinbookSkin, configuration.skin ?? .paperGlass)
        .preferredColorScheme(configuration.themeMode == "dark" ? .dark : configuration.themeMode == "light" ? .light : nil)
    }
}
#endif
