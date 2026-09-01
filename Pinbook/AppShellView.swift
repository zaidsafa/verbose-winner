import SwiftData
import SwiftUI

enum PinbookTab: Hashable {
    case expenses
    case summary
    case noted
    case options
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var appearances: [AppearanceSettingsItem]
    @State private var selection: PinbookTab
    @State private var showingAddExpense = false
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
                QuickAddAccessory { showingAddExpense = true }
            }
        }
        .environment(\.pinbookSkin, skin)
        .tint(skin.accent)
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEditorView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Local store unavailable", isPresented: .constant(bootstrapError != nil)) {
            Button("OK") { bootstrapError = nil }
        } message: {
            Text(bootstrapError ?? "")
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
