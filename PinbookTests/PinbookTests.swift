import SwiftData
import Testing
@testable import Pinbook

@MainActor
@Test func productionBootstrapCreatesOnlyInfrastructureRecords() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext

    try PinbookBootstrap.prepare(context)

    #expect(try context.fetch(FetchDescriptor<BookItem>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<AppearanceSettingsItem>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SettlementItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ExpenseTemplateItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ReceiptMetadataItem>()).isEmpty)
}

@MainActor
@Test func swiftDataPersistsExpenseAndPartialPayment() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let expense = ExpenseItem(
        amountMinor: 12_345,
        currency: "CNY",
        purpose: "Courier",
        counterparty: "Customer"
    )
    let payment = SettlementItem(expenseID: expense.id, amountMinor: 2_345)
    context.insert(expense)
    context.insert(payment)
    try context.save()

    let storedExpenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let storedPayments = try context.fetch(FetchDescriptor<SettlementItem>())
    #expect(storedExpenses.count == 1)
    #expect(ExpenseCalculations.remainingMinor(for: expense, settlements: storedPayments) == 10_000)
}

@MainActor
@Test func summaryNeverCombinesCurrencies() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    context.insert(ExpenseItem(amountMinor: 100, currency: "USD", purpose: "A", counterparty: "P"))
    context.insert(ExpenseItem(amountMinor: 200, currency: "EUR", purpose: "B", counterparty: "P"))
    try context.save()

    let totals = ExpenseCalculations.totalsByCurrency(
        expenses: try context.fetch(FetchDescriptor<ExpenseItem>()),
        settlements: []
    )
    #expect(totals == ["USD": 100, "EUR": 200])
}

@MainActor
private func inMemoryContainer() throws -> ModelContainer {
    let schema = Schema(PinbookSchema.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
