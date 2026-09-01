import SwiftData
import SwiftUI

struct SummaryView: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        SummaryMetric(title: "Open", value: "\(openExpenses.count)", symbol: "tray.full")
                        SummaryMetric(title: "Noted", value: "\(expenses.count - openExpenses.count)", symbol: "checkmark.circle")
                    }
                } else {
                    HStack(spacing: 12) {
                        SummaryMetric(title: "Open", value: "\(openExpenses.count)", symbol: "tray.full")
                        SummaryMetric(title: "Noted", value: "\(expenses.count - openExpenses.count)", symbol: "checkmark.circle")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Remaining by currency", systemImage: "sum")
                        .font(.headline)
                    if totals.isEmpty {
                        Text("No open balances yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(totals, id: \.currency) { total in
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(total.currency).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(total.amount.formattedMoney(currency: total.currency))
                                        .monospacedDigit()
                                        .font(.headline)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(total.currency).font(.subheadline.weight(.semibold))
                                    Text(total.amount.formattedMoney(currency: total.currency))
                                        .monospacedDigit()
                                        .font(.headline)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 4) {
                                    notedPurpose(expense)
                                    notedAmount(expense)
                                }
                            } else {
                                HStack {
                                    notedPurpose(expense)
                                    Spacer()
                                    notedAmount(expense)
                                }
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

    private func notedPurpose(_ expense: ExpenseItem) -> some View {
        Text(expense.purpose)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func notedAmount(_ expense: ExpenseItem) -> some View {
        Text(expense.amountMinor.formattedMoney(currency: expense.currency))
            .monospacedDigit()
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }
}
