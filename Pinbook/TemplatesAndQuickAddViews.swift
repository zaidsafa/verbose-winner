import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query private var appearances: [AppearanceSettingsItem]
    @Query(sort: \ExpenseTemplateItem.name) private var allTemplates: [ExpenseTemplateItem]
    @State private var showingNewTemplate = false
    @State private var editingTemplate: ExpenseTemplateItem?
    @State private var operationError: String?

    private var activeBookID: String { appearances.first?.activeBookID ?? "default" }
    private var templates: [ExpenseTemplateItem] {
        PinbookQueries.templates(allTemplates, in: activeBookID)
    }

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No templates", systemImage: "doc.on.doc")
                } description: {
                    Text("Save repeated expense details once, then use them from Quick Add.")
                } actions: {
                    Button("New template", systemImage: "plus") { showingNewTemplate = true }
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(templates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            TemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                setDeleted(template)
                            }
                        }
                    }
                } footer: {
                    Text("Templates belong only to the active book and are available from Quick Add.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New template", systemImage: "plus") { showingNewTemplate = true }
            }
        }
        .sheet(isPresented: $showingNewTemplate) {
            TemplateEditorView(template: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(template: template)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Unable to update templates", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func setDeleted(_ template: ExpenseTemplateItem) {
        do {
            try TemplateOperations.setDeleted(true, for: template, in: modelContext)
        } catch {
            operationError = error.localizedDescription
        }
    }
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query private var appearances: [AppearanceSettingsItem]
    @Query private var allExpenses: [ExpenseItem]
    @Query(sort: \ExpenseTemplateItem.name) private var allTemplates: [ExpenseTemplateItem]
    @State private var operationError: String?
    @State private var showingExpenseEditor = false

    private var activeBookID: String { appearances.first?.activeBookID ?? "default" }
    private var favorites: [ExpenseItem] {
        PinbookQueries.favoriteExpenses(allExpenses, in: activeBookID)
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var templates: [ExpenseTemplateItem] {
        PinbookQueries.templates(allTemplates, in: activeBookID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add different expense", systemImage: "square.and.pencil") {
                        showingExpenseEditor = true
                    }
                }

                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { expense in
                            Button {
                                add(ExpenseDraft(favorite: expense))
                            } label: {
                                QuickAddRow(
                                    title: expense.purpose,
                                    subtitle: expense.counterparty,
                                    amountMinor: expense.amountMinor,
                                    currency: expense.currency,
                                    symbol: "star.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !templates.isEmpty {
                    Section("Templates") {
                        ForEach(templates) { template in
                            Button {
                                add(ExpenseDraft(template: template))
                            } label: {
                                QuickAddRow(
                                    title: template.name,
                                    subtitle: template.purpose,
                                    amountMinor: template.amountMinor,
                                    currency: template.currency,
                                    symbol: "doc.on.doc"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if favorites.isEmpty && templates.isEmpty {
                    Section {
                        Text("Star an expense or create a template to make it appear here.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(skin.backdrop.ignoresSafeArea())
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .alert("Unable to add expense", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK") { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
            .sheet(isPresented: $showingExpenseEditor) {
                ExpenseEditorView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func add(_ draft: ExpenseDraft) {
        do {
            try QuickAddOperations.createExpense(from: draft, in: activeBookID, context: modelContext)
            dismiss()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct TemplateRow: View {
    let template: ExpenseTemplateItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.headline)
                Text(template.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(template.amountMinor.formattedMoney(currency: template.currency))
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct QuickAddRow: View {
    let title: String
    let subtitle: String
    let amountMinor: Int64
    let currency: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountMinor.formattedMoney(currency: currency))
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var appearances: [AppearanceSettingsItem]
    let template: ExpenseTemplateItem?

    @State private var name: String
    @State private var amount: String
    @State private var currency: String
    @State private var purpose: String
    @State private var counterparty: String
    @State private var category: String
    @State private var tags: String
    @State private var privateNote: String
    @State private var validationMessage: String?

    init(template: ExpenseTemplateItem?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _amount = State(initialValue: template.map(Self.amountInput) ?? "")
        _currency = State(initialValue: template?.currency ?? "")
        _purpose = State(initialValue: template?.purpose ?? "")
        _counterparty = State(initialValue: template?.counterparty ?? "")
        _category = State(initialValue: template?.category ?? "")
        _tags = State(initialValue: template?.tags.joined(separator: ", ") ?? "")
        _privateNote = State(initialValue: template?.privateNote ?? "")
    }

    private var settings: AppearanceSettingsItem? { appearances.first }
    private var currencies: [String] {
        var values = settings?.favoriteCurrencies ?? []
        if let template, !values.contains(template.currency) { values.append(template.currency) }
        return values.sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if currencies.isEmpty {
                    ContentUnavailableView(
                        "Choose currencies first",
                        systemImage: "coloncurrencysign.circle",
                        description: Text("Templates use the favorite currencies you explicitly choose in Options.")
                    )
                } else {
                    Form {
                        Section("Template") {
                            TextField("Template name", text: $name)
                            TextField("Amount", text: $amount).keyboardType(.decimalPad)
                            Picker("Currency", selection: $currency) {
                                ForEach(currencies, id: \.self) { Text($0).tag($0) }
                            }
                            TextField("Purpose", text: $purpose)
                            TextField("Person or customer", text: $counterparty)
                        }

                        Section("Details") {
                            TextField("Category (optional)", text: $category)
                            TextField("Tags (comma separated)", text: $tags)
                            TextField("Private note (optional)", text: $privateNote, axis: .vertical)
                                .lineLimit(2...5)
                        }

                        if let validationMessage {
                            Section { Text(validationMessage).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if !currencies.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .onAppear {
                if currency.isEmpty { currency = settings?.preferredCurrency ?? currencies.first ?? "" }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPurpose.isEmpty, !cleanCounterparty.isEmpty else {
            validationMessage = String(localized: "Name, purpose, and person are required.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
            return
        }

        do {
            let money = try MoneyAmount.parse(amount, currencyCode: currency, locale: PinbookLanguage.currentLocale)
            guard money.minorUnits > 0 else {
                validationMessage = String(localized: "Amount must be greater than zero.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
                return
            }
            let cleanTags = tags.split(separator: ",").map(String.init)
            if let template {
                template.name = cleanName
                template.amountMinor = money.minorUnits
                template.currency = money.currencyCode
                template.purpose = cleanPurpose
                template.counterparty = cleanCounterparty
                template.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
                template.tags = cleanTags
                template.privateNote = privateNote.trimmingCharacters(in: .whitespacesAndNewlines)
                template.updatedAt = .nowMilliseconds
            } else {
                modelContext.insert(ExpenseTemplateItem(
                    bookID: settings?.activeBookID ?? "default",
                    name: cleanName,
                    amountMinor: money.minorUnits,
                    currency: money.currencyCode,
                    purpose: cleanPurpose,
                    counterparty: cleanCounterparty,
                    category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                    tags: cleanTags,
                    privateNote: privateNote.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = String(localized: "Enter a valid amount for this currency.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        }
    }

    private static func amountInput(_ template: ExpenseTemplateItem) -> String {
        let digits = MoneyAmount.fractionDigits(for: template.currency)
        let scale: Decimal = switch digits {
        case 0: 1
        case 3: 1_000
        default: 100
        }
        let formatter = NumberFormatter()
        formatter.locale = PinbookLanguage.currentLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(template.amountMinor) / scale)) ?? ""
    }
}
