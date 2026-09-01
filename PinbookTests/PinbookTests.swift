import Foundation
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

@MainActor
@Test func templatesAndFavoritesStayInsideTheirBook() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let firstFavorite = ExpenseItem(
        amountMinor: 1_500,
        currency: "USD",
        purpose: "Favorite",
        counterparty: "A",
        bookID: "first",
        isFavorite: true
    )
    let secondFavorite = ExpenseItem(
        amountMinor: 2_500,
        currency: "EUR",
        purpose: "Other favorite",
        counterparty: "B",
        bookID: "second",
        isFavorite: true
    )
    let firstTemplate = ExpenseTemplateItem(
        bookID: "first",
        name: "First template",
        amountMinor: 900,
        currency: "USD",
        purpose: "Template",
        counterparty: "A"
    )
    let deletedTemplate = ExpenseTemplateItem(
        bookID: "first",
        name: "Deleted",
        amountMinor: 100,
        currency: "USD",
        purpose: "Deleted",
        counterparty: "A"
    )
    [firstFavorite, secondFavorite].forEach(context.insert)
    [firstTemplate, deletedTemplate].forEach(context.insert)
    try context.save()
    try TemplateOperations.setDeleted(true, for: deletedTemplate, in: context)
    #expect(deletedTemplate.isTombstoned)

    let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let templates = try context.fetch(FetchDescriptor<ExpenseTemplateItem>())
    #expect(PinbookQueries.favoriteExpenses(expenses, in: "first").map(\.id) == [firstFavorite.id])
    #expect(PinbookQueries.templates(templates, in: "first").map(\.id) == [firstTemplate.id])
}

@MainActor
@Test func quickAddCopiesDraftIntoAFreshUnstarredExpense() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let source = ExpenseItem(
        amountMinor: 12_345,
        currency: "KWD",
        purpose: "Recurring",
        counterparty: "Supplier",
        bookID: "source",
        category: "Samples",
        tags: ["repeat"],
        privateNote: "Private",
        isFavorite: true
    )
    context.insert(source)
    try context.save()

    let copy = try QuickAddOperations.createExpense(
        from: ExpenseDraft(favorite: source),
        in: "active",
        context: context,
        now: 123_456
    )
    #expect(copy.id != source.id)
    #expect(copy.bookID == "active")
    #expect(copy.amountMinor == source.amountMinor)
    #expect(copy.currency == source.currency)
    #expect(copy.tags == ["repeat"])
    #expect(!copy.isFavorite)
    #expect(!copy.isNoted)
    #expect(copy.reminderAt == nil)
    #expect(copy.occurredAt == 123_456)
}

@Test func receiptFileStoreSavesLoadsRemovesAndRejectsTraversal() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptStore-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let source = Data([0x89, 0x50, 0x4E, 0x47])

    let fileName = try await store.save(data: source, preferredFileName: "customer receipt.PNG")
    #expect(fileName.hasSuffix(".png"))
    #expect(!fileName.contains("customer"))
    #expect(try await store.load(fileName: fileName) == source)

    var rejectedTraversal = false
    do {
        _ = try await store.load(fileName: "../outside.png")
    } catch ReceiptFileStoreError.invalidFileName {
        rejectedTraversal = true
    }
    #expect(rejectedTraversal)

    try await store.remove(fileName: fileName)
    var removedFileIsUnavailable = false
    do {
        _ = try await store.load(fileName: fileName)
    } catch {
        removedFileIsUnavailable = true
    }
    #expect(removedFileIsUnavailable)
}

@MainActor
@Test func statementScopeStaysInsideBookPersonAndCurrency() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let selected = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "Selected",
        counterparty: "A",
        bookID: "first"
    )
    let otherCurrency = ExpenseItem(
        amountMinor: 2_000,
        currency: "EUR",
        purpose: "Other currency",
        counterparty: "A",
        bookID: "first"
    )
    let otherPerson = ExpenseItem(
        amountMinor: 3_000,
        currency: "USD",
        purpose: "Other person",
        counterparty: "B",
        bookID: "first"
    )
    let otherBook = ExpenseItem(
        amountMinor: 4_000,
        currency: "USD",
        purpose: "Other book",
        counterparty: "A",
        bookID: "second"
    )
    [selected, otherCurrency, otherPerson, otherBook].forEach(context.insert)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<ExpenseItem>())
    let scoped = PinbookQueries.statementExpenses(stored, in: "first", person: "A", currency: "USD")
    #expect(scoped.map(\.id) == [selected.id])
}

@Test func localStatementsPreserveExactMinorUnitsAndCreateReadableFiles() throws {
    let expense = ExpenseRecord(
        id: "expense",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Freight, \"priority\"",
        counterparty: "North Star",
        occurredAt: 1_788_192_000_000,
        createdAt: 1_788_192_000_000,
        updatedAt: 1_788_192_000_000,
        isNoted: false
    )
    let activePayment = SettlementRecord(
        id: "active",
        expenseId: expense.id,
        amountMinor: 2_345,
        note: nil,
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isDeleted: false
    )
    let deletedPayment = SettlementRecord(
        id: "deleted",
        expenseId: expense.id,
        amountMinor: 9_999,
        note: nil,
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isDeleted: true
    )
    let generator = LocalStatementGenerator()

    let csv = try generator.csv(for: [expense], settlements: [activePayment, deletedPayment])
    let csvText = try #require(String(data: csv, encoding: .utf8))
    #expect(Array(csv.prefix(3)) == [0xEF, 0xBB, 0xBF])
    #expect(csvText.hasPrefix("occurred_at"))
    #expect(csvText.contains("\"Freight, \"\"priority\"\"\""))
    #expect(csvText.contains(",12345,2345,10000,USD,open"))

    let pdf = try generator.pdf(for: [expense], settlements: [activePayment, deletedPayment])
    #expect(pdf.count > 1_000)
    #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
}

@Test func reminderRequestIsDeterministicAndLockScreenPrivate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let spec = ReminderRequestFactory.make(
        expenseID: "expense-1",
        at: date,
        title: "Expense reminder",
        calendar: calendar
    )

    #expect(spec.identifier == "pinbook-expense-expense-1")
    #expect(calendar.date(from: spec.dateComponents) == date)
    #expect(spec.body == "Open Pinbook to review a scheduled expense.")
    #expect(!spec.body.contains("Rent"))
    #expect(!spec.body.contains("USD"))
    #expect(!spec.body.contains("100"))
}

@MainActor
@Test func receiptLifecycleKeepsMetadataAndPrivateFileInStep() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptLifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let container = try inMemoryContainer()
    let context = container.mainContext
    let expense = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "Receipt test",
        counterparty: "Supplier"
    )
    context.insert(expense)
    try context.save()
    let source = Data("private receipt".utf8)

    let metadata = try await ReceiptLifecycle.attach(
        data: source,
        preferredFileName: "receipt.jpg",
        mimeType: "image/jpeg",
        displayName: "Receipt photo",
        to: expense,
        context: context,
        store: store
    )
    #expect(metadata.expenseID == expense.id)
    #expect(!metadata.isTombstoned)
    #expect(try await store.load(fileName: metadata.fileName) == source)

    try await ReceiptLifecycle.remove(metadata, context: context, store: store)
    #expect(metadata.isTombstoned)
    let storedMetadata = try context.fetch(FetchDescriptor<ReceiptMetadataItem>())
    #expect(storedMetadata.count == 1)
    #expect(storedMetadata.first?.isTombstoned == true)
    var removedFileIsUnavailable = false
    do {
        _ = try await store.load(fileName: metadata.fileName)
    } catch {
        removedFileIsUnavailable = true
    }
    #expect(removedFileIsUnavailable)
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
    #expect(expenses.filter(\.isFavorite).map(\.id) == ["fixture-rent"])
    #expect(expenses.filter { $0.reminderAt != nil }.map(\.id) == ["fixture-freight"])
    #expect(settlements.count == 1)
    #expect(try context.fetch(FetchDescriptor<ExpenseTemplateItem>()).count == 1)
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
    let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
