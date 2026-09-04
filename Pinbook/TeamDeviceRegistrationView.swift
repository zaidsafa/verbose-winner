import SwiftUI

struct TeamDeviceRegistrationView: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: TeamDeviceRegistrationScreenModel
    let isTransitioning: Bool
    let onContinue: () -> Void
    let onClose: () -> Void
    init(model: TeamDeviceRegistrationScreenModel, isTransitioning: Bool,
         onContinue: @escaping () -> Void, onClose: @escaping () -> Void) {
        _model = State(initialValue: model); self.isTransitioning = isTransitioning
        self.onContinue = onContinue; self.onClose = onClose
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: model.canContinue ? "checkmark.shield.fill" : "iphone.gen3")
                        .font(.system(size: 42, weight: .semibold)).foregroundStyle(skin.accent).accessibilityHidden(true)
                    Text("Register this device").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(statusMessage).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("device-registration-status")
                    if model.stage != .closed {
                        VStack(alignment: .leading, spacing: 18) {
                            identity("Account", value: model.context.accountID, identifier: "device-registration-account")
                            identity("Team", value: model.context.teamID, identifier: "device-registration-team")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                        .background(skin.contentSurface, in: RoundedRectangle(cornerRadius: 26))
                        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.primary.opacity(0.08), lineWidth: 1) }
                        Text("Registration does not join the team or share your private notes.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("device-registration-privacy")
                    }
                    if let until = model.waitUntil {
                        Text(Date(timeIntervalSince1970: Double(until) / 1_000), format: .dateTime.month().day().hour().minute())
                            .font(.headline).accessibilityIdentifier("device-registration-wait-until")
                    }
                    if model.offersConsent {
                        Toggle(isOn: Binding(get: { model.agreed }, set: { model.setAgreement($0) })) {
                            Text("I agree to register this device for the account shown.").fixedSize(horizontal: false, vertical: true)
                        }.frame(minHeight: 48).accessibilityIdentifier("device-registration-consent")
                        Button { Task { await model.register() } } label: {
                            Text(model.stage == .ready ? "Register this device" : "Continue registration")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.pinbookProminent).disabled(!model.canRegister)
                            .accessibilityIdentifier("device-registration-register")
                    }
                    if model.stage == .registering || isTransitioning {
                        ProgressView().frame(maxWidth: .infinity).accessibilityLabel(Text("Register this device"))
                    }
                    if model.canContinue {
                        Button("Continue", action: onContinue).buttonStyle(.pinbookProminent)
                            .disabled(isTransitioning).frame(minHeight: 44).accessibilityIdentifier("device-registration-continue")
                    }
                }
                .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.stage)
            }
            .background(skin.backdrop.ignoresSafeArea()).foregroundStyle(.primary).tint(skin.accent)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close", role: .cancel, action: onClose).accessibilityIdentifier("device-registration-close")
            } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(skin.preferredScheme)
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
        switch model.stage {
        case .ready: "This device needs its own registration before you can join the team."
        case .registering: "Registering device…"
        case .waiting: "An earlier registration is still pending. Wait until the time shown, then continue."
        case .retryReady: "The previous attempt was not found. Confirm again to retry with the same device."
        case .uncertain: "Registration could not be confirmed. Continue to check the previous attempt before trying again."
        case .registered: "This device is registered. Continue to review your team membership."
        case .closed: "Device screen closed. Open the invitation again to continue."
        }
    }
}
