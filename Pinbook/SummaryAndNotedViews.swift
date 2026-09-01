import SwiftData
import SwiftUI

struct SummaryView: View {
    @Environment(\.pinbookSkin) private var skin
    @Query private var expenses: [ExpenseItem]
    @Query private var settlements: [SettlementItem]

    private var openExpenses: [ExpenseItem] { expenses.filter { !$0.isNoted } }
    private var totals: [(currency: String, amount: Int64)] {
        ExpenseCalculations.totalsByCurrency(expenses: openExpenses, settlements: settlements)
            .map { ($0.key, $0.value) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SummaryMetric(title: "Open", value: "\(openExpenses.count)", symbol: "tray.full")
                    SummaryMetric(title: "Noted", value: "\(expenses.count - openExpenses.count)", symbol: "checkmark.circle")
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Remaining by currency", systemImage: "sum")
                        .font(.headline)
                    if totals.isEmpty {
                        Text("No open balances yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(totals, id: \.currency) { total in
                            HStack {
                                Text(total.currency).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(total.amount.formattedMoney(currency: total.currency))
                                    .monospacedDigit()
                                    .font(.headline)
                            }
                            if total.currency != totals.last?.currency { Divider() }
                        }
                    }
                }
                .padding(18)
                .background(skin.contentSurface, in: .rect(cornerRadius: 24))

                Text("Totals stay separated by currency. Pinbook never applies an implicit exchange rate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .padding(.bottom, 50)
        }
        .background(skin.backdrop.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Summary")
    }
}

private struct SummaryMetric: View {
    @Environment(\.pinbookSkin) private var skin
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value).font(.largeTitle.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(skin.contentSurface, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

struct NotedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query(sort: \ExpenseItem.notedAt, order: .reverse) private var allExpenses: [ExpenseItem]
    private var expenses: [ExpenseItem] { allExpenses.filter(\.isNoted) }

    var body: some View {
        Group {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "Nothing noted",
                    systemImage: "checkmark.circle",
                    description: Text("Expenses you mark as noted stay recoverable here.")
                )
            } else {
                List {
                    ForEach(expenses) { expense in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(expense.purpose).font(.headline)
                                Spacer()
                                Text(expense.amountMinor.formattedMoney(currency: expense.currency))
                                    .monospacedDigit()
                            }
                            Text(expense.counterparty).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(skin.contentSurface)
                        .swipeActions(edge: .trailing) {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                expense.isNoted = false
                                expense.notedAt = nil
                                expense.updatedAt = .nowMilliseconds
                                try? modelContext.save()
                            }
                            .tint(skin.accent)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Noted")
    }
}
