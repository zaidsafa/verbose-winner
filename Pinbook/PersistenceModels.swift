import Foundation
import SwiftData

enum PinbookSchema {
    static let models: [any PersistentModel.Type] = [
        BookItem.self,
        ExpenseItem.self,
        SettlementItem.self,
        ExpenseTemplateItem.self,
        ReceiptMetadataItem.self,
        AppearanceSettingsItem.self,
    ]
}

@Model
final class BookItem {
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Int64
    var updatedAt: Int64
    var isArchived: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

@Model
final class ExpenseItem {
    @Attribute(.unique) var id: String
    var amountMinor: Int64
    var currency: String
    var purpose: String
    var counterparty: String
    var bookID: String
    var category: String
    var tagsRaw: String
    var privateNote: String
    var isFavorite: Bool
    var reminderAt: Int64?
    var reminderSentAt: Int64?
    var occurredAt: Int64
    var createdAt: Int64
    var updatedAt: Int64
    var isNoted: Bool
    var notedAt: Int64?

    init(
        id: String = UUID().uuidString,
        amountMinor: Int64,
        currency: String,
        purpose: String,
        counterparty: String,
        bookID: String = "default",
        category: String = "",
        tags: [String] = [],
        privateNote: String = "",
        isFavorite: Bool = false,
        reminderAt: Int64? = nil,
        reminderSentAt: Int64? = nil,
        occurredAt: Int64 = .nowMilliseconds,
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds,
        isNoted: Bool = false,
        notedAt: Int64? = nil
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.purpose = purpose
        self.counterparty = counterparty
        self.bookID = bookID
        self.category = category
        tagsRaw = tags.cleanedTags.joined(separator: "\u{001F}")
        self.privateNote = privateNote
        self.isFavorite = isFavorite
        self.reminderAt = reminderAt
        self.reminderSentAt = reminderSentAt
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isNoted = isNoted
        self.notedAt = notedAt
    }

    var tags: [String] {
        get { tagsRaw.split(separator: "\u{001F}").map(String.init) }
        set { tagsRaw = newValue.cleanedTags.joined(separator: "\u{001F}") }
    }
}

@Model
final class SettlementItem {
    @Attribute(.unique) var id: String
    var expenseID: String
    var amountMinor: Int64
    var note: String
    var occurredAt: Int64
    var createdAt: Int64
    var updatedAt: Int64
    var isDeleted: Bool

    init(
        id: String = UUID().uuidString,
        expenseID: String,
        amountMinor: Int64,
        note: String = "",
        occurredAt: Int64 = .nowMilliseconds,
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.expenseID = expenseID
        self.amountMinor = amountMinor
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

@Model
final class ExpenseTemplateItem {
    @Attribute(.unique) var id: String
    var bookID: String
    var name: String
    var amountMinor: Int64
    var currency: String
    var purpose: String
    var counterparty: String
    var category: String
    var tagsRaw: String
    var privateNote: String
    var createdAt: Int64
    var updatedAt: Int64
    var isDeleted: Bool

    init(
        id: String = UUID().uuidString,
        bookID: String,
        name: String,
        amountMinor: Int64,
        currency: String,
        purpose: String,
        counterparty: String,
        category: String = "",
        tags: [String] = [],
        privateNote: String = "",
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.purpose = purpose
        self.counterparty = counterparty
        self.category = category
        tagsRaw = tags.cleanedTags.joined(separator: "\u{001F}")
        self.privateNote = privateNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

@Model
final class ReceiptMetadataItem {
    @Attribute(.unique) var id: String
    var expenseID: String
    var fileName: String
    var mimeType: String
    var displayName: String
    var createdAt: Int64
    var updatedAt: Int64
    var isDeleted: Bool

    init(
        id: String = UUID().uuidString,
        expenseID: String,
        fileName: String,
        mimeType: String,
        displayName: String,
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.expenseID = expenseID
        self.fileName = fileName
        self.mimeType = mimeType
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

@Model
final class AppearanceSettingsItem {
    @Attribute(.unique) var id: String
    var themeMode: String
    var interfaceSkin: String
    var colorTheme: String
    var font: String
    var fontSize: String
    var expenseLayout: String
    var favoriteCurrenciesRaw: String
    var preferredCurrency: String?
    var activeBookID: String
    var automaticSyncEnabled: Bool
    var createdAt: Int64
    var updatedAt: Int64

    init(
        id: String = "appearance",
        themeMode: String = "system",
        interfaceSkin: String = PinbookSkin.paperGlass.rawValue,
        colorTheme: String = "default",
        font: String = "system",
        fontSize: String = "standard",
        expenseLayout: String = "notebook",
        favoriteCurrencies: [String] = [],
        preferredCurrency: String? = nil,
        activeBookID: String = "default",
        automaticSyncEnabled: Bool = false,
        createdAt: Int64 = .nowMilliseconds,
        updatedAt: Int64 = .nowMilliseconds
    ) {
        self.id = id
        self.themeMode = themeMode
        self.interfaceSkin = interfaceSkin
        self.colorTheme = colorTheme
        self.font = font
        self.fontSize = fontSize
        self.expenseLayout = expenseLayout
        favoriteCurrenciesRaw = favoriteCurrencies.map { $0.uppercased() }.joined(separator: ",")
        self.preferredCurrency = preferredCurrency?.uppercased()
        self.activeBookID = activeBookID
        self.automaticSyncEnabled = automaticSyncEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var favoriteCurrencies: [String] {
        get { favoriteCurrenciesRaw.split(separator: ",").map(String.init) }
        set {
            favoriteCurrenciesRaw = newValue.map { $0.uppercased() }.joined(separator: ",")
            if let preferredCurrency, !newValue.contains(preferredCurrency) {
                self.preferredCurrency = newValue.first
            }
            updatedAt = .nowMilliseconds
        }
    }
}

enum PinbookBootstrap {
    @MainActor
    static func prepare(_ context: ModelContext) throws {
        let books = try context.fetch(FetchDescriptor<BookItem>())
        if !books.contains(where: { $0.id == "default" }) {
            context.insert(BookItem(id: "default", name: "Pinbook", createdAt: 0, updatedAt: 0))
        }

        let appearances = try context.fetch(FetchDescriptor<AppearanceSettingsItem>())
        if !appearances.contains(where: { $0.id == "appearance" }) {
            context.insert(AppearanceSettingsItem())
        }
        try context.save()
    }
}

enum ExpenseCalculations {
    static func remainingMinor(for expense: ExpenseItem, settlements: [SettlementItem]) -> Int64 {
        let paid = settlements
            .filter { $0.expenseID == expense.id && !$0.isDeleted }
            .reduce(Int64.zero) { partial, settlement in
                let (sum, overflow) = partial.addingReportingOverflow(settlement.amountMinor)
                return overflow ? Int64.max : sum
            }
        let (remaining, overflow) = expense.amountMinor.subtractingReportingOverflow(paid)
        return overflow ? 0 : max(0, remaining)
    }

    static func totalsByCurrency(
        expenses: [ExpenseItem],
        settlements: [SettlementItem]
    ) -> [String: Int64] {
        expenses.reduce(into: [:]) { totals, expense in
            let remaining = remainingMinor(for: expense, settlements: settlements)
            let current = totals[expense.currency, default: 0]
            let (sum, overflow) = current.addingReportingOverflow(remaining)
            totals[expense.currency] = overflow ? Int64.max : sum
        }
    }
}

extension Int64 {
    static var nowMilliseconds: Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }

    var pinbookDate: Date { Date(timeIntervalSince1970: Double(self) / 1_000) }
}

private extension Array where Element == String {
    var cleanedTags: [String] {
        reduce(into: []) { result, value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
            else { return }
            result.append(cleaned)
        }
    }
}
