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
