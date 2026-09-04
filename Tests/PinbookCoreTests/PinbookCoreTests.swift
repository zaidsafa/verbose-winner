import Foundation
import Testing
@testable import PinbookCore

@Test func decodesAndroidBackupVersionEight() throws {
    let json = """
    {
      "formatVersion": 8,
      "expenses": [{
        "id": "expense", "amountMinor": 1250, "currency": "USD",
        "purpose": "Courier", "counterparty": "Customer", "bookId": "default",
        "category": "Delivery", "tags": ["urgent"], "privateNote": "private",
        "isFavorite": true, "reminderAt": 500, "reminderSentAt": null,
        "occurredAt": 10, "createdAt": 10, "updatedAt": 20,
        "isNoted": false, "notedAt": null
      }],
      "books": [], "settlements": [], "templates": [],
      "receiptAttachments": [], "appearance": null
    }
    """

    let backup = try JSONDecoder().decode(PinbookBackup.self, from: Data(json.utf8))
    #expect(backup.formatVersion == 8)
    #expect(backup.expenses.first?.tags == ["urgent"])
    #expect(backup.expenses.first?.reminderAt == 500)
}

@Test func rejectsUnsupportedBackupVersion() {
    let json = Data(#"{"formatVersion":9}"#.utf8)
    #expect(throws: BackupError.unsupportedVersion(9)) {
        try JSONDecoder().decode(PinbookBackup.self, from: json)
    }
}

@Test func newestTimestampWinsAndLocalWinsTies() {
    let local = expense(purpose: "local", updatedAt: 20)
    let olderRemote = expense(purpose: "remote older", updatedAt: 10)
    let newerRemote = expense(purpose: "remote newer", updatedAt: 30)

    let olderResult = mergeNewest(local: [local], remote: [olderRemote])
    #expect(olderResult.records.first?.purpose == "local")
    #expect(olderResult.localWins == 1)

    let newerResult = mergeNewest(local: [local], remote: [newerRemote])
    #expect(newerResult.records.first?.purpose == "remote newer")
    #expect(newerResult.remoteWins == 1)
}

@Test func backupVersionEightRoundTripsEveryAndroidCompatibleEntity() throws {
    let backup = try PinbookBackup(
        formatVersion: 8,
        exportedAt: 900,
        expenses: [expense(purpose: "Round trip", updatedAt: 20)],
        books: [BookRecord(id: "default", name: "Pinbook", createdAt: 0, updatedAt: 2, isArchived: false)],
        settlements: [SettlementRecord(
            id: "payment",
            expenseId: "same",
            amountMinor: 25,
            note: "Partial",
            occurredAt: 3,
            createdAt: 3,
            updatedAt: 4,
            isDeleted: false
        )],
        templates: [TemplateRecord(
            id: "template",
            bookId: "default",
            name: "Monthly",
            amountMinor: 100,
            currency: "USD",
            purpose: "Template",
            counterparty: "Person",
            category: "Recurring",
            tags: ["repeat"],
            privateNote: "private",
            createdAt: 5,
            updatedAt: 6,
            isDeleted: false
        )],
        receiptAttachments: [ReceiptAttachmentRecord(
            id: "receipt",
            expenseId: "same",
            fileName: "receipt.png",
            mimeType: "image/png",
            displayName: "Receipt photo",
            contentBase64: Data("receipt".utf8).base64EncodedString(),
            createdAt: 7,
            updatedAt: 8,
            isDeleted: false
        )],
        appearance: AppearanceRecord(
            themeMode: "system",
            interfaceSkin: "paperGlass",
            colorTheme: "default",
            font: "system",
            fontSize: "standard",
            expenseLayout: "notebook",
            favoriteCurrencies: ["USD"],
            preferredCurrency: "USD",
            activeBookId: "default",
            updatedAt: 9
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(backup)
    let decoded = try JSONDecoder().decode(PinbookBackup.self, from: data)
    #expect(decoded == backup)
    #expect(decoded.formatVersion == 8)
    #expect(decoded.totalRecordCount == 6)
}

@Test func backupPreviewIsDeterministicKeepsLocalTiesAndSeparatesCurrencies() throws {
    let tiedLocal = ExpenseRecord(
        id: "tie",
        amountMinor: 100,
        currency: "USD",
        purpose: "Local tie",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 20,
        isNoted: false
    )
    let tiedRemote = ExpenseRecord(
        id: "tie",
        amountMinor: 999,
        currency: "EUR",
        purpose: "Remote tie",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 20,
        isNoted: false
    )
    let addedEUR = ExpenseRecord(
        id: "added",
        amountMinor: 200,
        currency: "EUR",
        purpose: "Added EUR",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 30,
        isNoted: false
    )
    let book = BookRecord(id: "default", name: "Pinbook", createdAt: 0, updatedAt: 0, isArchived: false)
    let local = try PinbookBackup(expenses: [tiedLocal], books: [book])
    let remote = try PinbookBackup(expenses: [addedEUR, tiedRemote], books: [book])

    let first = try makeBackupMergePlan(local: local, remote: remote)
    let second = try makeBackupMergePlan(local: local, remote: remote)
    #expect(first == second)
    #expect(first.preview.summaries.map(\.entity) == BackupEntityKind.allCases)
    let expenseSummary = try #require(first.preview.summaries.first { $0.entity == .expenses })
    #expect(expenseSummary.added == 1)
    #expect(expenseSummary.conflicts == 1)
    #expect(first.preview.totalConflicts == 1)
    #expect(first.merged.expenses.first { $0.id == "tie" }?.purpose == "Local tie")
    #expect(Set(first.merged.expenses.map(\.currency)) == ["USD", "EUR"])
}

@Test func moneyUsesISOReferencedMinorUnits() throws {
    #expect(try MoneyAmount(minorUnits: 1_250, currencyCode: "USD").decimalValue == Decimal(string: "12.5"))
    #expect(try MoneyAmount(minorUnits: 1_250, currencyCode: "IQD").decimalValue == Decimal(string: "1.25"))
    #expect(try MoneyAmount(minorUnits: 1_250, currencyCode: "JPY").decimalValue == Decimal(1_250))
}

@Test func moneyParsingRejectsPrecisionLoss() throws {
    let locale = Locale(identifier: "en_US_POSIX")
    #expect(try MoneyAmount.parse("123.45", currencyCode: "USD", locale: locale).minorUnits == 12_345)
    #expect(throws: MoneyError.tooManyFractionDigits) {
        try MoneyAmount.parse("123.456", currencyCode: "USD", locale: locale)
    }
}

@Test func moneyParsesLocalizedDigitsWithoutChangingMinorUnits() throws {
    for (locale, text) in [("de_DE", "12,34"), ("ar_SA", "١٢٫٣٤"), ("ur_PK", "۱۲٫۳۴"), ("hi_IN", "१२.३४")] {
        #expect(try MoneyAmount.parse(text, currencyCode: "USD", locale: Locale(identifier: locale)).minorUnits == 1234)
    }
    #expect(try MoneyAmount.parse("١٢٫٣٤٥", currencyCode: "KWD", locale: Locale(identifier: "ar_KW")).minorUnits == 12345)
}

@Test func moneyRejectsPartialAndAmbiguousLocalizedInput() {
    for input in ["12oops", "1,234", "12.3.4", "١٢٬٣٤", "1e2", "Ⅻ"] {
        #expect(throws: MoneyError.invalidAmount(input)) {
            try MoneyAmount.parse(input, currencyCode: "USD", locale: Locale(identifier: "en_US"))
        }
    }
    #expect(throws: MoneyError.invalidAmount("1.234")) {
        try MoneyAmount.parse("1.234", currencyCode: "USD", locale: Locale(identifier: "de_DE"))
    }
}

private func expense(purpose: String, updatedAt: Int64) -> ExpenseRecord {
    ExpenseRecord(
        id: "same",
        amountMinor: 100,
        currency: "USD",
        purpose: purpose,
        counterparty: "Person",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: updatedAt,
        isNoted: false
    )
}
