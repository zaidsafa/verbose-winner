import SwiftData
import SwiftUI

enum PinbookTab: Hashable {
    case expenses
    case summary
    case noted
    case options
}

enum PinbookDeepLink: Equatable {
    case newExpense
    case summary

    init?(url: URL) {
        guard url.scheme?.lowercased() == "pinbook" else { return nil }
        switch (url.host?.lowercased(), url.path.lowercased()) {
        case ("expense", "/new"): self = .newExpense
        case ("summary", ""): self = .summary
        default: return nil
        }
    }

    var destinationTab: PinbookTab {
        switch self {
        case .newExpense: .expenses
        case .summary: .summary
        }
    }

    var opensExpenseEditor: Bool { self == .newExpense }
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var appearances: [AppearanceSettingsItem]
    @AppStorage(PinbookOnboardingState.completionKey) private var hasCompletedOnboarding = false
    @State private var selection: PinbookTab
    @State private var showingAddExpense = false
    @State private var showingQuickAdd = false
    @State private var onboardingOverrideDismissed = false
    @State private var bootstrapError: String?
    private let launchConfiguration: PinbookLaunchConfiguration

    init(launchConfiguration: PinbookLaunchConfiguration = .production) {
        self.launchConfiguration = launchConfiguration
        _selection = State(initialValue: launchConfiguration.initialTab)
    }

    private var skin: PinbookSkin {
        PinbookSkin(rawValue: appearances.first?.interfaceSkin ?? "") ?? .paperGlass
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearances.first?.themeMode {
        case "light": .light
        case "dark": .dark
        default: skin.preferredScheme
        }
    }

    private var hasFavoriteCurrencies: Bool {
        appearances.first?.favoriteCurrencies.isEmpty == false
    }

    private var shouldShowOnboarding: Bool {
        PinbookOnboardingPolicy.shouldPresent(
            mode: launchConfiguration.onboardingMode,
            hasCompleted: hasCompletedOnboarding,
            overrideDismissed: onboardingOverrideDismissed
        )
    }

    var body: some View {
        ZStack {
            skin.backdrop.ignoresSafeArea()

            TabView(selection: $selection) {
                Tab("Expenses", systemImage: "wallet.bifold", value: .expenses) {
                    NavigationStack {
                        ExpensesView(
                            showingAddExpense: $showingAddExpense,
                            openOptions: { selection = .options }
                        )
                    }
                }

                Tab("Summary", systemImage: "chart.bar.xaxis", value: .summary) {
                    NavigationStack { SummaryView() }
                }

                Tab("Noted", systemImage: "checkmark.circle", value: .noted) {
                    NavigationStack { NotedView() }
                }

                Tab("Options", systemImage: "slider.horizontal.3", value: .options) {
                    NavigationStack { OptionsView() }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(
                isEnabled: selection == .expenses && hasFavoriteCurrencies && !dynamicTypeSize.isAccessibilitySize
            ) {
                QuickAddAccessory { showingQuickAdd = true }
            }
        }
        .environment(\.pinbookSkin, skin)
        .tint(skin.accent)
        .preferredColorScheme(preferredColorScheme)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: skin)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: appearances.first?.themeMode)
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEditorView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddView()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Local store unavailable", isPresented: .constant(bootstrapError != nil)) {
            Button("OK") { bootstrapError = nil }
        } message: {
            Text(bootstrapError ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { shouldShowOnboarding },
            set: { if !$0 { onboardingOverrideDismissed = true } }
        )) {
            PinbookOnboardingView {
                hasCompletedOnboarding = true
                onboardingOverrideDismissed = true
            }
        }
        .onOpenURL { url in
            guard let deepLink = PinbookDeepLink(url: url) else { return }
            selection = deepLink.destinationTab
            if deepLink.opensExpenseEditor {
                showingAddExpense = true
            }
        }
        .task {
            do {
                try PinbookBootstrap.prepare(modelContext)
#if DEBUG
                try PinbookDebugFixtures.prepare(modelContext, configuration: launchConfiguration)
#endif
            } catch {
                bootstrapError = error.localizedDescription
            }
        }
    }
}

private struct QuickAddAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let addExpense: () -> Void

    var body: some View {
        Button(action: addExpense) {
            if placement == .inline {
                Image(systemName: "plus")
                    .accessibilityLabel("Add expense")
            } else {
                Label("Quick Add", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .accessibilityHint("Opens the new expense form")
        .padding(.horizontal, placement == .inline ? 0 : 12)
    }
}
