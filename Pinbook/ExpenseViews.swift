import SwiftData
import SwiftUI

struct ExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query(sort: \ExpenseItem.occurredAt, order: .reverse) private var allExpenses: [ExpenseItem]
    @Query(sort: \SettlementItem.occurredAt, order: .reverse) private var settlements: [SettlementItem]
    @Query private var appearances: [AppearanceSettingsItem]
    @Binding var showingAddExpense: Bool
    let openOptions: () -> Void

    private var expenses: [ExpenseItem] { allExpenses.filter { !$0.isNoted } }

    var body: some View {
        ZStack {
            skin.backdrop.ignoresSafeArea()
            Group {
                if expenses.isEmpty {
                    EmptyExpensesView(
                        hasCurrencies: appearances.first?.favoriteCurrencies.isEmpty == false,
                        addExpense: { showingAddExpense = true },
                        openOptions: openOptions
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(expenses) { expense in
                                ExpenseCard(
                                    expense: expense,
                                    remainingMinor: ExpenseCalculations.remainingMinor(
                                        for: expense,
                                        settlements: settlements
                                    ),
                                    markNoted: { markNoted(expense) }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 90)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .top)
                }
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !expenses.isEmpty {
                    Button("Add", systemImage: "plus") { showingAddExpense = true }
                        .buttonStyle(.glassProminent)
                        .accessibilityHint("Opens the new expense form")
                }
            }
        }
    }

    private func markNoted(_ expense: ExpenseItem) {
        withAnimation {
            expense.isNoted = true
            expense.notedAt = .nowMilliseconds
            expense.updatedAt = .nowMilliseconds
            try? modelContext.save()
        }
    }
}

private struct EmptyExpensesView: View {
    @Environment(\.pinbookSkin) private var skin
    @Namespace private var glassNamespace
    let hasCurrencies: Bool
    let addExpense: () -> Void
    let openOptions: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your open expenses", systemImage: "book.closed")
        } description: {
            Text("Add a periodic expense, then track what remains until it is noted.")
        } actions: {
            GlassEffectContainer(spacing: 18) {
                if hasCurrencies {
                    Button("Add expense", systemImage: "plus", action: addExpense)
                        .buttonStyle(.glassProminent)
                        .glassEffectID("add-expense", in: glassNamespace)
                } else {
                    Button("Choose currencies", systemImage: "coloncurrencysign.circle", action: openOptions)
                        .buttonStyle(.glassProminent)
                        .glassEffectID("currencies", in: glassNamespace)
                }
            }
            .tint(skin.accent)
        }
    }
}

private struct ExpenseCard: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.colorSchemeContrast) private var contrast
    let expense: ExpenseItem
    let remainingMinor: Int64
    let markNoted: () -> Void
    @State private var showingPayment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.purpose)
                        .font(.headline)
                    Text(expense.counterparty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(remainingMinor.formattedMoney(currency: expense.currency))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if remainingMinor != expense.amountMinor {
                        Text("of \(expense.amountMinor.formattedMoney(currency: expense.currency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Label(expense.occurredAt.pinbookDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                if !expense.category.isEmpty {
                    Label(expense.category, systemImage: "tag")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Payment", systemImage: "banknote") { showingPayment = true }
                    .buttonStyle(.glass)
                Spacer()
                Button("Mark noted", systemImage: "checkmark", action: markNoted)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(18)
        .background(skin.contentSurface, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(skin.accent.opacity(contrast == .increased ? 0.65 : 0.20), lineWidth: contrast == .increased ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showingPayment) {
            SettlementEditorView(expense: expense, remainingMinor: remainingMinor)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct SettlementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let expense: ExpenseItem
    let remainingMinor: Int64
    @State private var amount = ""
    @State private var note = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Remaining") {
                    Text(remainingMinor.formattedMoney(currency: expense.currency))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                Section("Payment") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Note (optional)", text: $note)
                    if let validationMessage {
                        Text(validationMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func save() {
        do {
            let money = try MoneyAmount.parse(amount, currencyCode: expense.currency)
            guard money.minorUnits > 0, money.minorUnits <= remainingMinor else {
                validationMessage = String(localized: "Enter an amount up to the remaining balance.")
                return
            }
            modelContext.insert(SettlementItem(
                expenseID: expense.id,
                amountMinor: money.minorUnits,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            expense.updatedAt = .nowMilliseconds
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = String(localized: "Enter a valid amount for this currency.")
        }
    }
}
