import SwiftData
import SwiftUI

struct StatementsView: View {
    @Environment(\.pinbookSkin) private var skin
    @Query private var appearances: [AppearanceSettingsItem]
    @Query private var allExpenses: [ExpenseItem]
    @Query private var settlements: [SettlementItem]
    @State private var selectedPerson = ""
    @State private var selectedCurrency = ""
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var operationError: String?

    private var activeBookID: String { appearances.first?.activeBookID ?? "default" }
    private var activeExpenses: [ExpenseItem] {
        PinbookQueries.expenses(allExpenses, in: activeBookID)
    }
    private var people: [String] {
        Array(Set(activeExpenses.map(\.counterparty))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private var currencies: [String] {
        Array(Set(activeExpenses.filter { $0.counterparty == selectedPerson }.map(\.currency))).sorted()
    }
    private var selectedExpenses: [ExpenseItem] {
        PinbookQueries.statementExpenses(
            allExpenses,
            in: activeBookID,
            person: selectedPerson,
            currency: selectedCurrency
        )
    }

    var body: some View {
        Group {
            if people.isEmpty {
                ContentUnavailableView(
                    "No statement data",
                    systemImage: "doc.text",
                    description: Text("Add an expense before creating a statement.")
                )
            } else {
                Form {
                    Section("Statement scope") {
                        Picker("Person or customer", selection: $selectedPerson) {
                            ForEach(people, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Currency", selection: $selectedCurrency) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        LabeledContent("Expenses", value: "\(selectedExpenses.count)")
                    }

                    Section("Create files") {
                        Button("Prepare PDF", systemImage: "doc.richtext") { preparePDF() }
                        Button("Prepare CSV", systemImage: "tablecells") { prepareCSV() }
                    }

                    if pdfURL != nil || csvURL != nil {
                        Section("Ready to share") {
                            if let pdfURL {
                                ShareLink(item: pdfURL) {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                            }
                            if let csvURL {
                                ShareLink(item: csvURL) {
                                    Label("Share CSV", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }

                    Section {
                        Text("Every statement contains exactly one person and one currency. CSV stores exact minor-unit integers; PDF formats values for reading. Files are generated locally in temporary storage.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("statements-final-help")
                    }
                }
                .contentMargins(.bottom, PinbookLayout.tabBarScrollClearance, for: .scrollContent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Statements")
        .onAppear { normalizeSelection() }
        .onChange(of: people) { _, _ in normalizeSelection() }
        .onChange(of: selectedPerson) { _, _ in
            if !currencies.contains(selectedCurrency) { selectedCurrency = currencies.first ?? "" }
            clearFiles()
        }
        .onChange(of: selectedCurrency) { _, _ in clearFiles() }
        .alert("Unable to create statement", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func normalizeSelection() {
        if !people.contains(selectedPerson) { selectedPerson = people.first ?? "" }
        if !currencies.contains(selectedCurrency) { selectedCurrency = currencies.first ?? "" }
    }

    private func preparePDF() {
        do {
            let data = try LocalStatementGenerator().pdf(
                for: selectedExpenses.map(\.statementRecord),
                settlements: settlements.map(\.statementRecord)
            )
            pdfURL = try StatementFileWriter.write(data, person: selectedPerson, currency: selectedCurrency, extension: "pdf")
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func prepareCSV() {
        do {
            let data = try LocalStatementGenerator().csv(
                for: selectedExpenses.map(\.statementRecord),
                settlements: settlements.map(\.statementRecord)
            )
            csvURL = try StatementFileWriter.write(data, person: selectedPerson, currency: selectedCurrency, extension: "csv")
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func clearFiles() {
        pdfURL = nil
        csvURL = nil
    }
}

struct ReminderOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query private var appearances: [AppearanceSettingsItem]
    @Query(sort: \ExpenseItem.reminderAt) private var allExpenses: [ExpenseItem]
    @State private var pendingCancellation: ExpenseItem?
    @State private var operationError: String?

    private var reminders: [ExpenseItem] {
        PinbookQueries.expenses(allExpenses, in: appearances.first?.activeBookID ?? "default")
            .filter { expense in
                guard let reminderAt = expense.reminderAt else { return false }
                return !expense.isNoted && reminderAt.pinbookDate > Date()
            }
    }

    var body: some View {
        Group {
            if reminders.isEmpty {
                ContentUnavailableView(
                    "No scheduled reminders",
                    systemImage: "bell.slash",
                    description: Text("Enable a reminder when adding an expense. Permission is requested only when you save it.")
                )
            } else {
                List {
                    Section {
                        ForEach(reminders) { expense in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(expense.purpose).font(.headline)
                                if let reminderAt = expense.reminderAt {
                                    Text(reminderAt.pinbookDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Cancel reminder", systemImage: "bell.slash", role: .destructive) {
                                    pendingCancellation = expense
                                }
                            }
                        }
                    } header: {
                        Text("Scheduled reminders")
                    } footer: {
                        Text("Notification text is intentionally generic so financial details do not appear on the Lock Screen.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Reminders")
        .confirmationDialog(
            "Cancel this reminder?",
            isPresented: Binding(
                get: { pendingCancellation != nil },
                set: { if !$0 { pendingCancellation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel reminder", role: .destructive) {
                guard let expense = pendingCancellation else { return }
                pendingCancellation = nil
                Task { await cancel(expense) }
            }
            Button("Keep reminder", role: .cancel) { pendingCancellation = nil }
        }
        .alert("Unable to cancel reminder", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    @MainActor
    private func cancel(_ expense: ExpenseItem) async {
        expense.reminderAt = nil
        expense.reminderSentAt = nil
        expense.updatedAt = .nowMilliseconds
        do {
            try modelContext.save()
            await LocalReminderScheduler.shared.cancel(expenseID: expense.id)
        } catch {
            modelContext.rollback()
            operationError = error.localizedDescription
        }
    }
}
