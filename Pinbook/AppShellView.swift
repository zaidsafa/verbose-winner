import SwiftData
import SwiftUI

enum PinbookLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case arabic = "ar"
    case turkish = "tr"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case brazilianPortuguese = "pt-BR"
    case hindi = "hi"
    case indonesian = "id"
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"
    case italian = "it"
    case urdu = "ur"

    static let preferenceKey = "pinbook.language.preference"

    // Keep UI-test language changes out of the user's ordinary preferences.
    // UserDefaults is thread-safe; sharing one instance also keeps AppStorage's
    // observers in sync when a choice changes from a presented language picker.
    nonisolated(unsafe) static let preferenceStore: UserDefaults = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PinbookFixture") {
            return UserDefaults(suiteName: "pinbook.language.ui-tests")!
        }
#endif
        return .standard
    }()

    static var current: PinbookLanguage {
        let selected = PinbookLanguage(rawValue: preferenceStore.string(forKey: preferenceKey) ?? "system") ?? .system
        return availableCases.contains(selected) ? selected : .system
    }

    // Never offer a locale whose catalog has not been compiled into this build.
    // All parity catalogs are included; this also guards incomplete future builds.
    static var availableCases: [PinbookLanguage] {
        allCases.filter { $0 == .system || $0 == .english || Bundle.main.localizations.contains($0.rawValue) }
    }

    static var currentLocale: Locale { current.effectiveLocale() }

    static var localizedBundle: Bundle { current.bundle() }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> PinbookLanguage {
        guard self == .system else { return self }
        let supported = Self.allCases.filter { $0 != .system }.map(\.rawValue)
        let identifier = Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first ?? "en"
        return PinbookLanguage(rawValue: identifier) ?? .english
    }

    func bundle(in source: Bundle = .main, preferredLanguages: [String] = Locale.preferredLanguages) -> Bundle {
        let language = resolved(preferredLanguages: preferredLanguages)
        guard let path = source.path(forResource: language.rawValue, ofType: "lproj"),
              let localized = Bundle(path: path) else { return source }
        return localized
    }

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .arabic: "العربية"
        case .turkish: "Türkçe"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .brazilianPortuguese: "Português (Brasil)"
        case .hindi: "हिन्दी"
        case .indonesian: "Bahasa Indonesia"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .russian: "Русский"
        case .italian: "Italiano"
        case .urdu: "اردو"
        }
    }

    func effectiveLocale(systemLocale: Locale = .autoupdatingCurrent) -> Locale {
        self == .system ? systemLocale : Locale(identifier: rawValue)
    }

    func layoutDirection(preferredLanguages: [String] = Locale.preferredLanguages) -> LayoutDirection {
        // Match the same supported-language fallback used by localized service
        // strings, including a supported secondary phone language.
        let locale = resolved(preferredLanguages: preferredLanguages).effectiveLocale()
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        return ["ar", "ur"].contains(languageCode) ? .rightToLeft : .leftToRight
    }
}

enum PinbookTab: Hashable {
    case expenses
    case summary
    case noted
    case options
}

struct PinbookLanguageEnvironment: ViewModifier {
    @AppStorage(PinbookLanguage.preferenceKey, store: PinbookLanguage.preferenceStore) private var preference = "system"

    func body(content: Content) -> some View {
        let selected = PinbookLanguage(rawValue: preference) ?? .system
        let language = PinbookLanguage.availableCases.contains(selected) ? selected : .system
        content
            .environment(\.locale, language.effectiveLocale())
            .environment(\.layoutDirection, language.layoutDirection())
    }
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
    @AppStorage(PinbookLanguage.preferenceKey, store: PinbookLanguage.preferenceStore) private var languagePreference = PinbookLanguage.system.rawValue
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

    private var language: PinbookLanguage {
        let selected = PinbookLanguage(rawValue: languagePreference) ?? .system
        return PinbookLanguage.availableCases.contains(selected) ? selected : .system
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
        // Wrap presentations as well as the tab content in the chosen language.
        .environment(\.locale, language.effectiveLocale())
        .environment(\.layoutDirection, language.layoutDirection())
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
