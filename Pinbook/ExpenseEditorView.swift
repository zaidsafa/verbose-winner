import SwiftData
import SwiftUI

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var appearances: [AppearanceSettingsItem]
    @Query(sort: \BookItem.createdAt) private var books: [BookItem]

    @State private var amount = ""
    @State private var currency = ""
    @State private var purpose = ""
    @State private var counterparty = ""
    @State private var category = ""
    @State private var privateNote = ""
    @State private var occurredAt = Date()
    @State private var reminderEnabled = false
    @State private var reminderAt = Date().addingTimeInterval(86_400)
    @State private var validationMessage: String?

    private var settings: AppearanceSettingsItem? { appearances.first }
    private var currencies: [String] { settings?.favoriteCurrencies ?? [] }
    private var activeBooks: [BookItem] { books.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            Group {
                if currencies.isEmpty {
                    ContentUnavailableView(
                        "Choose currencies first",
                        systemImage: "coloncurrencysign.circle",
                        description: Text("Pinbook never assumes a default favorite currency. Choose one in Options, then add the expense.")
                    )
                } else {
                    Form {
                        Section("Expense") {
                            TextField("Amount", text: $amount)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currency) {
                                ForEach(currencies, id: \.self) { Text($0).tag($0) }
                            }
                            TextField("Purpose", text: $purpose)
                            TextField("Person or customer", text: $counterparty)
                            DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                        }

                        Section("Details") {
                            TextField("Category (optional)", text: $category)
                            TextField("Private note (optional)", text: $privateNote, axis: .vertical)
                                .lineLimit(2...5)
                        }

                        Section("Reminder") {
                            Toggle("Set a reminder date", isOn: $reminderEnabled)
                            if reminderEnabled {
                                DatePicker("Reminder", selection: $reminderAt)
                            }
                            Text("Notification permission will be requested only when reminder delivery is implemented.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let validationMessage {
                            Section { Text(validationMessage).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if !currencies.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .onAppear {
                if currency.isEmpty {
                    currency = settings?.preferredCurrency ?? currencies.first ?? ""
                }
            }
        }
    }

    private func save() {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty, !cleanCounterparty.isEmpty else {
            validationMessage = String(localized: "Purpose and person are required.")
            return
        }

        do {
            let money = try MoneyAmount.parse(amount, currencyCode: currency)
            guard money.minorUnits > 0 else {
                validationMessage = String(localized: "Amount must be greater than zero.")
                return
            }
            modelContext.insert(ExpenseItem(
                amountMinor: money.minorUnits,
                currency: money.currencyCode,
                purpose: cleanPurpose,
                counterparty: cleanCounterparty,
                bookID: settings?.activeBookID ?? activeBooks.first?.id ?? "default",
                category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                privateNote: privateNote.trimmingCharacters(in: .whitespacesAndNewlines),
                reminderAt: reminderEnabled ? Int64((reminderAt.timeIntervalSince1970 * 1_000).rounded()) : nil,
                occurredAt: Int64((occurredAt.timeIntervalSince1970 * 1_000).rounded())
            ))
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = String(localized: "Enter a valid amount for this currency.")
        }
    }
}
