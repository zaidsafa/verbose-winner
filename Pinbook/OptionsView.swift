import SwiftData
import SwiftUI

struct PinbookCurrencyOption: Identifiable, Equatable {
    let code: String
    let symbol: String
    let localizedName: String

    var id: String { code }
}

enum PinbookCurrencyCatalog {
    static func options(locale: Locale = .current) -> [PinbookCurrencyOption] {
        Locale.commonISOCurrencyCodes
            .map { code in
                let formatter = NumberFormatter()
                formatter.locale = locale
                formatter.numberStyle = .currency
                formatter.currencyCode = code
                let symbol = formatter.currencySymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
                return PinbookCurrencyOption(
                    code: code,
                    symbol: symbol?.isEmpty == false ? symbol! : code,
                    localizedName: locale.localizedString(forCurrencyCode: code) ?? code
                )
            }
            .sorted { $0.code < $1.code }
    }
}

struct OptionsView: View {
    @Environment(\.pinbookSkin) private var skin
    @AppStorage(PinbookOnboardingState.completionKey) private var hasCompletedOnboarding = false
    @Query private var appearances: [AppearanceSettingsItem]
    @Query private var allTemplates: [ExpenseTemplateItem]

    private var activeTemplateCount: Int {
        PinbookQueries.templates(
            allTemplates,
            in: appearances.first?.activeBookID ?? "default"
        ).count
    }

    private var templateCountText: Text {
        activeTemplateCount == 1 ? Text("1 template") : Text("\(activeTemplateCount) templates")
    }

    var body: some View {
        List {
            Section("Personalize") {
                NavigationLink {
                    AppearanceOptionsView()
                } label: {
                    OptionsRow(title: "Appearance", subtitle: skin.title, symbol: "circle.lefthalf.filled")
                }

                NavigationLink {
                    BooksAndCurrenciesView()
                } label: {
                    OptionsRow(
                        title: "Books & currencies",
                        subtitle: Text("\(appearances.first?.favoriteCurrencies.count ?? 0) favorite currencies"),
                        symbol: "books.vertical"
                    )
                }

                NavigationLink {
                    TemplatesView()
                } label: {
                    OptionsRow(
                        title: "Templates",
                        subtitle: templateCountText,
                        symbol: "doc.on.doc"
                    )
                }
            }

            Section("Data") {
                NavigationLink {
                    BackupRecoveryView()
                } label: {
                    OptionsRow(title: "Backup & Recovery", subtitle: "Local Files and restore history", symbol: "externaldrive.badge.timemachine")
                }

                NavigationLink {
                    StatementsView()
                } label: {
                    OptionsRow(title: "Statements", subtitle: "PDF and CSV", symbol: "doc.text")
                }
            }

            Section("Device") {
                NavigationLink {
                    ReminderOverviewView()
                } label: {
                    OptionsRow(title: "Reminders", subtitle: "Local delivery", symbol: "bell")
                }

                NavigationLink {
                    PlannedCapabilityView(
                        title: "Receipt OCR",
                        symbol: "viewfinder",
                        detail: "On-device receipt text recognition is a later enhancement and is not available in this build."
                    )
                } label: {
                    OptionsRow(title: "Receipt OCR", subtitle: "Later enhancement", symbol: "text.viewfinder")
                }
            }

            Section("Help") {
                Button {
                    hasCompletedOnboarding = false
                } label: {
                    OptionsRow(
                        title: "View introduction",
                        subtitle: "Replay the quick Pinbook tour",
                        symbol: "rectangle.stack.badge.play"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(skin.backdrop.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Options")
    }
}

private struct OptionsRow: View {
    let title: LocalizedStringKey
    let subtitle: Text
    let symbol: String

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, symbol: String) {
        self.title = title
        self.subtitle = Text(subtitle)
        self.symbol = symbol
    }

    init(title: LocalizedStringKey, subtitle: Text, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                subtitle.font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppearanceOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var activeSkin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var appearances: [AppearanceSettingsItem]

    var body: some View {
        Form {
            Section("Interface skin") {
                ForEach(PinbookSkin.allCases) { skin in
                    Button {
                        updateSkin(skin)
                    } label: {
                        SkinPreviewRow(
                            skin: skin,
                            isSelected: appearances.first?.interfaceSkin == skin.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(activeSkin.contentSurface)
                }
            }

            Section("Theme mode") {
                Picker("Theme mode", selection: themeModeBinding) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Text(themeModeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Pinbook uses native Liquid Glass for tabs, toolbars, sheets, and important interactive controls. Expense cards retain a stable themed surface for readability.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(activeSkin.backdrop.ignoresSafeArea())
        .navigationTitle("Appearance")
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: activeSkin)
    }

    private var themeModeDescription: LocalizedStringKey {
        switch appearances.first?.themeMode {
        case "light": "Light keeps every skin bright with dark, high-contrast text."
        case "dark": "Dark adapts every surface and accent for comfortable low-light reading."
        default: "System follows the appearance selected in iPhone Settings."
        }
    }

    private var themeModeBinding: Binding<String> {
        Binding(
            get: { appearances.first?.themeMode ?? "system" },
            set: { value in
                appearances.first?.themeMode = value
                appearances.first?.updatedAt = .nowMilliseconds
                try? modelContext.save()
            }
        )
    }

    private func updateSkin(_ skin: PinbookSkin) {
        let changes = {
            appearances.first?.interfaceSkin = skin.rawValue
            appearances.first?.colorTheme = "default"
            appearances.first?.updatedAt = .nowMilliseconds
            try? modelContext.save()
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.4)) { changes() }
        }
    }
}

private struct SkinPreviewRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skin: PinbookSkin
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(skin.backdrop)
                    .frame(width: 58, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(skin.accent.opacity(0.34), lineWidth: 1)
                    }
                Image(systemName: skin.symbol)
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(skin.accent)
                    .symbolEffect(.bounce, value: isSelected && !reduceMotion)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(skin.title)
                    .font(.headline)
                Text(skin.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? skin.accent : Color.secondary.opacity(0.4))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(isSelected ? "Selected" : "Not selected")
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct BooksAndCurrenciesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appearances: [AppearanceSettingsItem]
    @Query(sort: \BookItem.createdAt) private var books: [BookItem]
    @State private var showingNewBook = false
    @State private var editingBook: BookItem?
    @State private var operationError: String?

    private var settings: AppearanceSettingsItem? { appearances.first }
    private var activeBooks: [BookItem] { books.filter { !$0.isArchived } }
    private var archivedBooks: [BookItem] { books.filter(\.isArchived) }

    var body: some View {
        List {
            Section {
                ForEach(activeBooks) { book in
                    Button {
                        select(book)
                    } label: {
                        HStack {
                            Label(book.name, systemImage: book.id == "default" ? "book.closed.fill" : "book.closed")
                            Spacer()
                            if settings?.activeBookID == book.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Active book")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button("Rename", systemImage: "pencil") { editingBook = book }
                            .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        if settings?.activeBookID != book.id {
                            Button("Archive", systemImage: "archivebox", role: .destructive) {
                                setArchived(true, for: book)
                            }
                        }
                    }
                }
            } header: {
                Text("Active book")
            } footer: {
                Text("Only the selected book appears in Expenses, Summary, Noted, templates, and exports.")
            }

            if !archivedBooks.isEmpty {
                Section("Archived books") {
                    ForEach(archivedBooks) { book in
                        Label(book.name, systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                            .swipeActions(edge: .leading) {
                                Button("Rename", systemImage: "pencil") { editingBook = book }
                                    .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    setArchived(false, for: book)
                                }
                                .tint(.green)
                            }
                    }
                }
            }

            Section("Favorite currencies") {
                if let settings {
                    NavigationLink {
                        CurrencySelectionView(settings: settings)
                    } label: {
                        OptionsRow(
                            title: "Choose currencies",
                            subtitle: Text("\(settings.favoriteCurrencies.count) favorite currencies"),
                            symbol: "coloncurrencysign.circle"
                        )
                    }
                }
                Text("No favorites are selected by default. Expense entry only shows the currencies you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("books-currencies-final-help")
            }

            if let settings, !settings.favoriteCurrencies.isEmpty {
                Section("Default for new expenses") {
                    Picker("Preferred currency", selection: preferredCurrencyBinding(settings)) {
                        ForEach(settings.favoriteCurrencies, id: \.self) { currency in
                            Text(currency).tag(Optional(currency))
                        }
                    }
                    .accessibilityIdentifier("books-currencies-final-row")
                }
            }
        }
        .contentMargins(.bottom, PinbookLayout.tabBarScrollClearance, for: .scrollContent)
        .navigationTitle("Books & currencies")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New book", systemImage: "plus") { showingNewBook = true }
            }
        }
        .sheet(isPresented: $showingNewBook) {
            BookNameEditorView(title: "New book", initialName: "") { name in
                do {
                    guard let book = try BookOperations.create(named: name, in: modelContext) else {
                        return false
                    }
                    if let settings { try BookOperations.select(book, settings: settings, in: modelContext) }
                    return true
                } catch {
                    operationError = error.localizedDescription
                    return false
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingBook) { book in
            BookNameEditorView(title: "Rename book", initialName: book.name) { name in
                do {
                    try BookOperations.rename(book, to: name, in: modelContext)
                    return true
                } catch {
                    operationError = error.localizedDescription
                    return false
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Unable to update books", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func preferredCurrencyBinding(_ settings: AppearanceSettingsItem) -> Binding<String?> {
        Binding(
            get: { settings.preferredCurrency ?? settings.favoriteCurrencies.first },
            set: { value in
                settings.preferredCurrency = value
                settings.updatedAt = .nowMilliseconds
                try? modelContext.save()
            }
        )
    }

    private func select(_ book: BookItem) {
        guard let settings else { return }
        do {
            try BookOperations.select(book, settings: settings, in: modelContext)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func setArchived(_ archived: Bool, for book: BookItem) {
        guard let settings else { return }
        do {
            try BookOperations.setArchived(archived, for: book, settings: settings, in: modelContext)
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct CurrencySelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: AppearanceSettingsItem
    @State private var searchText = ""
    @State private var allCurrencies = PinbookCurrencyCatalog.options()

    private var currencies: [PinbookCurrencyOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allCurrencies }
        return allCurrencies.filter {
            $0.code.localizedCaseInsensitiveContains(query)
                || $0.symbol.localizedCaseInsensitiveContains(query)
                || $0.localizedName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(currencies) { currency in
            Toggle(isOn: currencyBinding(currency.code)) {
                HStack(spacing: 14) {
                    Group {
                        if currency.symbol == currency.code {
                            Image(systemName: "coloncurrencysign")
                                .font(.headline)
                        } else {
                            Text(currency.symbol)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: 46, height: 38)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currency.code)
                            .font(.headline.monospaced())
                        Text(currency.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .tint(.accentColor)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("currency-\(currency.code)")
        }
        .contentMargins(.bottom, PinbookLayout.tabBarScrollClearance, for: .scrollContent)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Choose currencies")
        )
        .navigationTitle("Favorite currencies")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func currencyBinding(_ currency: String) -> Binding<Bool> {
        Binding(
            get: { settings.favoriteCurrencies.contains(currency) },
            set: { isSelected in
                var values = settings.favoriteCurrencies
                if isSelected {
                    if !values.contains(currency) { values.append(currency); values.sort() }
                } else {
                    values.removeAll { $0 == currency }
                }
                settings.favoriteCurrencies = values
                if settings.preferredCurrency == nil { settings.preferredCurrency = values.first }
                settings.updatedAt = .nowMilliseconds
                try? modelContext.save()
            }
        )
    }
}

private struct BookNameEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let save: (String) -> Bool
    @State private var name: String
    @State private var showsValidation = false

    init(title: LocalizedStringKey, initialName: String, save: @escaping (String) -> Bool) {
        self.title = title
        self.save = save
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    if showsValidation {
                        Text("Enter a book name.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !BookOperations.cleanedName(name).isEmpty else {
                            showsValidation = true
                            return
                        }
                        if save(name) { dismiss() }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

private struct PlannedCapabilityView: View {
    let title: LocalizedStringKey
    let symbol: String
    let detail: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
