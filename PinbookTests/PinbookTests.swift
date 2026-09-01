import Foundation
import SwiftData
import Testing
import UIKit
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
    #expect(try context.fetch(FetchDescriptor<BackupActivityItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).isEmpty)
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

@Test func statementCSVNeutralizesSpreadsheetFormulas() throws {
    let first = ExpenseRecord(
        id: "first",
        amountMinor: 100,
        currency: "USD",
        purpose: "=1+1",
        counterparty: "+SUM(A1:A2)",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isNoted: false
    )
    let second = ExpenseRecord(
        id: "second",
        amountMinor: 200,
        currency: "USD",
        purpose: "-2+3",
        counterparty: "@SUM(A1:A2)",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isNoted: false
    )

    let csv = try LocalStatementGenerator().csv(for: [first, second], settlements: [])
    let text = try #require(String(data: csv, encoding: .utf8))
    #expect(text.contains(",'=1+1,'+SUM(A1:A2),"))
    #expect(text.contains(",'-2+3,'@SUM(A1:A2),"))
}

@Test func statementArithmeticOverflowFailsExplicitly() throws {
    let expense = ExpenseRecord(
        id: "overflow",
        amountMinor: Int64.max,
        currency: "USD",
        purpose: "Overflow",
        counterparty: "Test",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isNoted: false
    )
    let payments = [
        SettlementRecord(
            id: "max",
            expenseId: expense.id,
            amountMinor: Int64.max,
            note: nil,
            occurredAt: 1,
            createdAt: 1,
            updatedAt: 1,
            isDeleted: false
        ),
        SettlementRecord(
            id: "one",
            expenseId: expense.id,
            amountMinor: 1,
            note: nil,
            occurredAt: 2,
            createdAt: 2,
            updatedAt: 2,
            isDeleted: false
        ),
    ]

    do {
        _ = try LocalStatementGenerator().csv(for: [expense], settlements: payments)
        Issue.record("CSV generation should reject settlement overflow")
    } catch let error as StatementGenerationError {
        #expect(error == .arithmeticOverflow)
    }

    let second = ExpenseRecord(
        id: "second-overflow",
        amountMinor: Int64.max,
        currency: "USD",
        purpose: "Overflow total",
        counterparty: "Test",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isNoted: false
    )
    do {
        _ = try LocalStatementGenerator().pdf(for: [expense, second], settlements: [])
        Issue.record("PDF generation should reject total overflow")
    } catch let error as StatementGenerationError {
        #expect(error == .arithmeticOverflow)
    }
}

@Test func statementPDFPaintsWhitePagesWithDarkInkInDarkMode() throws {
    let expense = ExpenseRecord(
        id: "dark-pdf",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Print-safe statement",
        counterparty: "Dark appearance",
        occurredAt: 1_788_192_000_000,
        createdAt: 1_788_192_000_000,
        updatedAt: 1_788_192_000_000,
        isNoted: false
    )
    var generationResult: Result<Data, Error>?
    UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
        generationResult = Result {
            try LocalStatementGenerator().pdf(for: [expense], settlements: [])
        }
    }
    let pdf = try #require(generationResult).get()
    let dataProvider = try #require(CGDataProvider(data: pdf as CFData))
    let document = try #require(CGPDFDocument(dataProvider))
    let page = try #require(document.page(at: 1))
    let width = 595
    let height = 842
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(UIColor.magenta.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.drawPDFPage(page)

    let corner = (10 * width + 10) * 4
    #expect(pixels[corner] > 245)
    #expect(pixels[corner + 1] > 245)
    #expect(pixels[corner + 2] > 245)
    let darkPixelCount = stride(from: 0, to: pixels.count, by: 4).filter { index in
        pixels[index] < 80 && pixels[index + 1] < 80 && pixels[index + 2] < 80
    }.count
    #expect(darkPixelCount > 100)
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

@MainActor
@Test func failedReceiptTombstoneSaveKeepsThePrivateFile() async throws {
    enum ExpectedFailure: Error { case save }

    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptFailedRemoval-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let source = Data("keep this receipt".utf8)
    let fileName = try await store.save(data: source, preferredFileName: "receipt.jpg")
    let metadata = ReceiptMetadataItem(
        expenseID: "expense",
        fileName: fileName,
        mimeType: "image/jpeg",
        displayName: "Receipt photo",
        updatedAt: 123
    )
    var rollbackCalled = false

    do {
        try await ReceiptLifecycle.remove(
            metadata,
            store: store,
            persist: { throw ExpectedFailure.save },
            rollback: {
                rollbackCalled = true
                metadata.isTombstoned = false
                metadata.updatedAt = 123
            }
        )
        Issue.record("Receipt removal should surface the tombstone save failure")
    } catch ExpectedFailure.save {
        // Expected: the private file must not be removed before metadata persists.
    }

    #expect(rollbackCalled)
    #expect(!metadata.isTombstoned)
    #expect(metadata.updatedAt == 123)
    #expect(try await store.load(fileName: fileName) == source)
}

@Test func scrollClearanceKeepsFinalRowsAboveTheLiquidGlassTabBar() {
    #expect(PinbookLayout.tabBarScrollClearance >= 96)
}

@MainActor
@Test func localBackupExportsAndroidV8WithReceiptBytesAndAllEntityTypes() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookBackupExport-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    try PinbookBootstrap.prepare(context)

    let expense = ExpenseItem(
        id: "expense",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Courier",
        counterparty: "Customer",
        category: "Delivery",
        tags: ["urgent"],
        privateNote: "private",
        updatedAt: 20
    )
    context.insert(expense)
    context.insert(SettlementItem(id: "payment", expenseID: expense.id, amountMinor: 2_345, updatedAt: 21))
    context.insert(ExpenseTemplateItem(
        id: "template",
        bookID: "default",
        name: "Monthly",
        amountMinor: 900,
        currency: "EUR",
        purpose: "Template",
        counterparty: "Supplier",
        updatedAt: 22
    ))
    try context.save()
    let receiptBytes = Data("private receipt bytes".utf8)
    _ = try await ReceiptLifecycle.attach(
        data: receiptBytes,
        preferredFileName: "receipt.png",
        mimeType: "image/png",
        displayName: "Receipt photo",
        to: expense,
        context: context,
        store: store
    )

    let prepared = try await BackupRecoveryService(context: context, receiptStore: store)
        .prepareExport(now: 1_788_192_000_000)
    let decoded = try JSONDecoder().decode(PinbookBackup.self, from: prepared.data)
    #expect(decoded.formatVersion == 8)
    #expect(decoded.books.count == 1)
    #expect(decoded.expenses.count == 1)
    #expect(decoded.settlements.count == 1)
    #expect(decoded.templates.count == 1)
    #expect(decoded.receiptAttachments.count == 1)
    #expect(decoded.appearance != nil)
    #expect(Data(base64Encoded: decoded.receiptAttachments[0].contentBase64) == receiptBytes)
    #expect(prepared.fileName.contains("v8"))
    #expect(decoded.totalRecordCount == 6)
}

@MainActor
@Test func corruptAndUnsupportedBackupsNeverMutateFinancialRecords() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    try PinbookBootstrap.prepare(context)
    context.insert(ExpenseItem(
        id: "original",
        amountMinor: 500,
        currency: "USD",
        purpose: "Keep me",
        counterparty: "Person",
        updatedAt: 10
    ))
    try context.save()
    let service = BackupRecoveryService(context: context)

    let invalidCases: [(Data, BackupRecoveryError)] = [
        (Data("not-json".utf8), .invalidBackup),
        (Data(#"{"formatVersion":9}"#.utf8), .unsupportedBackupVersion),
    ]
    for (invalidData, expectedError) in invalidCases {
        do {
            _ = try await service.prepareRestore(data: invalidData)
            Issue.record("Invalid backup should be rejected")
        } catch let error as BackupRecoveryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Invalid backup should use a localized recovery error")
        }
        let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.id == "original")
        #expect(expenses.first?.purpose == "Keep me")
        #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).isEmpty)
    }
    let failures = try context.fetch(FetchDescriptor<BackupActivityItem>())
    #expect(failures.count == 2)
    #expect(failures.allSatisfy { $0.kind == .failedRestore && $0.status == .failed })
}

@MainActor
@Test func appliedRestoreCreatesSnapshotAndRecoveryRollsBackExactly() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookBackupRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    try PinbookBootstrap.prepare(context)
    context.insert(ExpenseItem(
        id: "shared",
        amountMinor: 100,
        currency: "USD",
        purpose: "Original local",
        counterparty: "Person",
        updatedAt: 10
    ))
    try context.save()
    let service = BackupRecoveryService(context: context, receiptStore: store)
    let baseline = try await service.captureBackup(exportedAt: nil)
    let updated = ExpenseRecord(
        id: "shared",
        amountMinor: 150,
        currency: "USD",
        purpose: "Newer imported",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 20,
        isNoted: false
    )
    let addedEUR = ExpenseRecord(
        id: "added-eur",
        amountMinor: 200,
        currency: "EUR",
        purpose: "Separate currency",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 20,
        isNoted: false
    )
    let incoming = try PinbookBackup(
        formatVersion: 8,
        exportedAt: 30,
        expenses: [addedEUR, updated],
        books: baseline.books,
        appearance: baseline.appearance
    )
    let encoded = try JSONEncoder().encode(incoming)

    let prepared = try await service.prepareRestore(data: encoded)
    let expenseSummary = try #require(prepared.preview.summaries.first { $0.entity == .expenses })
    #expect(expenseSummary.added == 1)
    #expect(expenseSummary.updated == 1)
    let snapshot = try await service.applyRestore(prepared, now: 40)
    let applied = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(Set(applied.map(\.currency)) == ["USD", "EUR"])
    #expect(applied.first { $0.id == "shared" }?.purpose == "Newer imported")
    #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).count == 1)

    try await service.recover(snapshot, now: 50)
    let recovered = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(recovered.count == 1)
    #expect(recovered.first?.id == "shared")
    #expect(recovered.first?.purpose == "Original local")
    #expect(snapshot.recoveredAt == 50)
    let activities = try context.fetch(FetchDescriptor<BackupActivityItem>())
    #expect(activities.contains { $0.kind == .preview && $0.status == .succeeded })
    #expect(activities.contains { $0.kind == .appliedRestore && $0.status == .succeeded })
    #expect(activities.contains { $0.kind == .recovery && $0.status == .succeeded })
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
