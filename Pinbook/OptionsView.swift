import SwiftData
import SwiftUI

struct OptionsView: View {
    @Environment(\.pinbookSkin) private var skin
    @Query private var appearances: [AppearanceSettingsItem]

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
            }

            Section("Data") {
                NavigationLink {
                    PlannedCapabilityView(
                        title: "Backup & sync",
                        symbol: "arrow.triangle.2.circlepath.icloud",
                        detail: "Per-user Google Drive app-data sync, restore preview, history, undo snapshots, and conflict recovery are planned but not connected."
                    )
                } label: {
                    OptionsRow(title: "Backup & sync", subtitle: "Not connected", symbol: "icloud.slash")
                }

                NavigationLink {
                    PlannedCapabilityView(
                        title: "Receipts & statements",
                        symbol: "doc.text.magnifyingglass",
                        detail: "Private receipt storage and per-person, per-currency PDF/CSV statements are planned. No files are imported or exported yet."
                    )
                } label: {
                    OptionsRow(title: "Receipts & statements", subtitle: "Planned", symbol: "doc.text")
                }
            }

            Section("Device") {
                NavigationLink {
                    PlannedCapabilityView(
                        title: "Reminders",
                        symbol: "bell.badge",
                        detail: "Reminder dates are stored locally. Notification authorization and delivery are not implemented yet."
                    )
                } label: {
                    OptionsRow(title: "Reminders", subtitle: "Dates stored; delivery planned", symbol: "bell")
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
    @Query private var appearances: [AppearanceSettingsItem]

    var body: some View {
        Form {
            Section("Interface skin") {
                ForEach(PinbookSkin.allCases) { skin in
                    Button {
                        updateSkin(skin)
                    } label: {
                        HStack {
                            Label(skin.title, systemImage: skin == .nightInk ? "moon.stars" : "paintpalette")
                            Spacer()
                            if appearances.first?.interfaceSkin == skin.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
                Text("Pinbook uses native Liquid Glass for tabs, toolbars, sheets, and important interactive controls. Expense cards retain a stable themed surface for readability.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Appearance")
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
        appearances.first?.interfaceSkin = skin.rawValue
        appearances.first?.colorTheme = "default"
        appearances.first?.updatedAt = .nowMilliseconds
        try? modelContext.save()
    }
}

private struct BooksAndCurrenciesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appearances: [AppearanceSettingsItem]
    @Query(sort: \BookItem.createdAt) private var books: [BookItem]
    @State private var showingNewBook = false
    @State private var editingBook: BookItem?
    @State private var operationError: String?
    private let availableCurrencies = ["AED", "CNY", "EUR", "GBP", "IQD", "JPY", "KWD", "SAR", "USD"]

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
                ForEach(availableCurrencies, id: \.self) { currency in
                    Toggle(currency, isOn: currencyBinding(currency))
                }
                Text("No favorites are selected by default. Expense entry only shows the currencies you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let settings, !settings.favoriteCurrencies.isEmpty {
                Section("Default for new expenses") {
                    Picker("Preferred currency", selection: preferredCurrencyBinding(settings)) {
                        ForEach(settings.favoriteCurrencies, id: \.self) { currency in
                            Text(currency).tag(Optional(currency))
                        }
                    }
                }
            }
        }
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

    private func currencyBinding(_ currency: String) -> Binding<Bool> {
        Binding(
            get: { appearances.first?.favoriteCurrencies.contains(currency) == true },
            set: { isSelected in
                guard let settings = appearances.first else { return }
                var values = settings.favoriteCurrencies
                if isSelected {
                    if !values.contains(currency) { values.append(currency); values.sort() }
                } else {
                    values.removeAll { $0 == currency }
                }
                settings.favoriteCurrencies = values
                if settings.preferredCurrency == nil { settings.preferredCurrency = values.first }
                try? modelContext.save()
            }
        )
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
