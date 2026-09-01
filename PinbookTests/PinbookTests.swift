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
    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    #expect(settings.favoriteCurrencies.isEmpty)
    #expect(settings.preferredCurrency == nil)
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
@Test func bookManagementPreservesAnActiveUnarchivedBook() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    try PinbookBootstrap.prepare(context)
    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    let defaultBook = try #require(context.fetch(FetchDescriptor<BookItem>()).first)

    let createdTravel = try BookOperations.create(named: "  Travel  ", in: context)
    let travel = try #require(createdTravel)
    #expect(travel.name == "Travel")
    try BookOperations.select(travel, settings: settings, in: context)
    #expect(settings.activeBookID == travel.id)

    try BookOperations.setArchived(true, for: travel, settings: settings, in: context)
    #expect(!travel.isArchived)

    try BookOperations.setArchived(true, for: defaultBook, settings: settings, in: context)
    #expect(defaultBook.isArchived)
    try BookOperations.setArchived(false, for: defaultBook, settings: settings, in: context)
    try BookOperations.rename(defaultBook, to: "  Household  ", in: context)
    #expect(defaultBook.name == "Household")
    #expect(!defaultBook.isArchived)
}

@MainActor
@Test func activeBookQueriesIsolateOpenNotedAndCurrencyTotals() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let first = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "First",
        counterparty: "A",
        bookID: "first"
    )
    let firstNoted = ExpenseItem(
        amountMinor: 2_000,
        currency: "USD",
        purpose: "First noted",
        counterparty: "A",
        bookID: "first",
        isNoted: true
    )
    let second = ExpenseItem(
        amountMinor: 9_000,
        currency: "EUR",
        purpose: "Second",
        counterparty: "B",
        bookID: "second"
    )
    [first, firstNoted, second].forEach(context.insert)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<ExpenseItem>())
    let firstOpen = PinbookQueries.expenses(stored, in: "first", noted: false)
    let firstArchived = PinbookQueries.expenses(stored, in: "first", noted: true)
    #expect(firstOpen.map(\.id) == [first.id])
    #expect(firstArchived.map(\.id) == [firstNoted.id])
    #expect(ExpenseCalculations.totalsByCurrency(expenses: firstOpen, settlements: []) == ["USD": 1_000])
}

#if DEBUG
@Test func launchArgumentsSelectDeterministicFixturePresentation() {
    let configuration = PinbookLaunchConfiguration(arguments: [
        "Pinbook",
        "-PinbookFixture", "populated",
        "-PinbookTab", "summary",
        "-PinbookSkin", "nightInk",
        "-PinbookTheme", "dark",
    ])

    #expect(configuration.usesFixtures)
    #expect(configuration.initialTab == .summary)
    #expect(configuration.skin == .nightInk)
    #expect(configuration.themeMode == "dark")
}

@MainActor
@Test func debugFixtureUsesInfrastructureAndDeterministicSampleRecords() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let configuration = PinbookLaunchConfiguration(arguments: [
        "Pinbook", "-PinbookFixture", "populated", "-PinbookSkin", "softPastel",
    ])

    try PinbookBootstrap.prepare(context)
    try PinbookDebugFixtures.prepare(context, configuration: configuration)

    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let settlements = try context.fetch(FetchDescriptor<SettlementItem>())
    #expect(settings.interfaceSkin == PinbookSkin.softPastel.rawValue)
    #expect(settings.favoriteCurrencies == ["CNY", "KWD", "USD"])
    #expect(expenses.count == 4)
    #expect(expenses.filter(\.isNoted).count == 1)
    #expect(settlements.count == 1)
    #expect(
        ExpenseCalculations.totalsByCurrency(
            expenses: expenses.filter { !$0.isNoted },
            settlements: settlements
        ) == ["CNY": 800_000, "USD": 285_075, "KWD": 123_456]
    )
}
#endif

@MainActor
private func inMemoryContainer() throws -> ModelContainer {
    let schema = Schema(PinbookSchema.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
