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
    private let availableCurrencies = ["AED", "CNY", "EUR", "GBP", "IQD", "JPY", "KWD", "SAR", "USD"]

    var body: some View {
        List {
            Section("Books") {
                ForEach(books.filter { !$0.isArchived }) { book in
                    Label(book.name, systemImage: book.id == "default" ? "book.closed.fill" : "book.closed")
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
        }
        .navigationTitle("Books & currencies")
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
