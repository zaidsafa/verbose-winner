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
        BackupActivityItem.self,
        BackupSnapshotItem.self,
    ]
}

enum BackupActivityKind: String, Codable {
    case export
    case preview
    case appliedRestore
    case failedRestore
    case recovery
}

enum BackupActivityStatus: String, Codable {
    case succeeded
    case failed
}

@Model
final class BackupActivityItem {
    @Attribute(.unique) var id: String
    var kindRaw: String
    var statusRaw: String
    var occurredAt: Int64
    var formatVersion: Int
    var recordCount: Int
    var changedCount: Int
    var conflictCount: Int
    var snapshotID: String?
    var detailCode: String?

    init(
        id: String = UUID().uuidString,
        kind: BackupActivityKind,
        status: BackupActivityStatus,
        occurredAt: Int64 = .nowMilliseconds,
        formatVersion: Int = PinbookBackup.currentFormatVersion,
        recordCount: Int = 0,
        changedCount: Int = 0,
        conflictCount: Int = 0,
        snapshotID: String? = nil,
        detailCode: String? = nil
    ) {
        self.id = id
        kindRaw = kind.rawValue
        statusRaw = status.rawValue
        self.occurredAt = occurredAt
        self.formatVersion = formatVersion
        self.recordCount = recordCount
        self.changedCount = changedCount
        self.conflictCount = conflictCount
        self.snapshotID = snapshotID
        self.detailCode = detailCode
    }

    var kind: BackupActivityKind { BackupActivityKind(rawValue: kindRaw) ?? .failedRestore }
    var status: BackupActivityStatus { BackupActivityStatus(rawValue: statusRaw) ?? .failed }
}

@Model
final class BackupSnapshotItem {
    @Attribute(.unique) var id: String
    var createdAt: Int64
    var formatVersion: Int
    var recordCount: Int
    var backupData: Data
    var recoveredAt: Int64?

    init(
        id: String = UUID().uuidString,
        createdAt: Int64 = .nowMilliseconds,
        formatVersion: Int,
        recordCount: Int,
        backupData: Data,
        recoveredAt: Int64? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.formatVersion = formatVersion
        self.recordCount = recordCount
        self.backupData = backupData
        self.recoveredAt = recoveredAt
    }
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
    var isTombstoned: Bool

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
        isTombstoned = isDeleted
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
    var isTombstoned: Bool

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
        isTombstoned = isDeleted
    }

    var tags: [String] {
        get { tagsRaw.split(separator: "\u{001F}").map(String.init) }
        set { tagsRaw = newValue.cleanedTags.joined(separator: "\u{001F}") }
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
    var isTombstoned: Bool

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
        isTombstoned = isDeleted
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
        var books = try context.fetch(FetchDescriptor<BookItem>())
        if !books.contains(where: { $0.id == "default" }) {
            let defaultBook = BookItem(id: "default", name: "Pinbook", createdAt: 0, updatedAt: 0)
            context.insert(defaultBook)
            books.append(defaultBook)
        }

        let appearances = try context.fetch(FetchDescriptor<AppearanceSettingsItem>())
        if !appearances.contains(where: { $0.id == "appearance" }) {
            context.insert(AppearanceSettingsItem())
        } else if let settings = appearances.first,
                  !books.contains(where: { $0.id == settings.activeBookID && !$0.isArchived }) {
            settings.activeBookID = books.first(where: { !$0.isArchived })?.id ?? "default"
            settings.updatedAt = .nowMilliseconds
        }
        try context.save()
    }
}

enum BookOperations {
    static func cleanedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    @discardableResult
    static func create(named name: String, in context: ModelContext) throws -> BookItem? {
        let cleanName = cleanedName(name)
        guard !cleanName.isEmpty else { return nil }
        let book = BookItem(name: cleanName)
        context.insert(book)
        try context.save()
        return book
    }

    @MainActor
    static func rename(_ book: BookItem, to name: String, in context: ModelContext) throws {
        let cleanName = cleanedName(name)
        guard !cleanName.isEmpty else { return }
        book.name = cleanName
        book.updatedAt = .nowMilliseconds
        try context.save()
    }

    @MainActor
    static func select(_ book: BookItem, settings: AppearanceSettingsItem, in context: ModelContext) throws {
        guard !book.isArchived else { return }
        settings.activeBookID = book.id
        settings.updatedAt = .nowMilliseconds
        try context.save()
    }

    @MainActor
    static func setArchived(
        _ archived: Bool,
        for book: BookItem,
        settings: AppearanceSettingsItem,
        in context: ModelContext
    ) throws {
        guard !archived || book.id != settings.activeBookID else { return }
        book.isArchived = archived
        book.updatedAt = .nowMilliseconds
        try context.save()
    }
}

enum PinbookQueries {
    static func expenses(
        _ expenses: [ExpenseItem],
        in bookID: String,
        noted: Bool? = nil
    ) -> [ExpenseItem] {
        expenses.filter { expense in
            guard expense.bookID == bookID else { return false }
            guard let noted else { return true }
            return expense.isNoted == noted
        }
    }

    static func favoriteExpenses(_ expenses: [ExpenseItem], in bookID: String) -> [ExpenseItem] {
        self.expenses(expenses, in: bookID).filter { $0.isFavorite }
    }

    static func statementExpenses(
        _ expenses: [ExpenseItem],
        in bookID: String,
        person: String,
        currency: String
    ) -> [ExpenseItem] {
        self.expenses(expenses, in: bookID).filter {
            $0.counterparty == person && $0.currency == currency
        }
    }

    static func templates(_ templates: [ExpenseTemplateItem], in bookID: String) -> [ExpenseTemplateItem] {
        templates.filter { $0.bookID == bookID && !$0.isTombstoned }
    }
}

struct ExpenseDraft: Equatable {
    var amountMinor: Int64
    var currency: String
    var purpose: String
    var counterparty: String
    var category: String
    var tags: [String]
    var privateNote: String

    init(template: ExpenseTemplateItem) {
        amountMinor = template.amountMinor
        currency = template.currency
        purpose = template.purpose
        counterparty = template.counterparty
        category = template.category
        tags = template.tags
        privateNote = template.privateNote
    }

    init(favorite expense: ExpenseItem) {
        amountMinor = expense.amountMinor
        currency = expense.currency
        purpose = expense.purpose
        counterparty = expense.counterparty
        category = expense.category
        tags = expense.tags
        privateNote = expense.privateNote
    }
}

enum QuickAddOperations {
    @MainActor
    @discardableResult
    static func createExpense(
        from draft: ExpenseDraft,
        in bookID: String,
        context: ModelContext,
        now: Int64 = .nowMilliseconds
    ) throws -> ExpenseItem {
        let expense = ExpenseItem(
            amountMinor: draft.amountMinor,
            currency: draft.currency,
            purpose: draft.purpose,
            counterparty: draft.counterparty,
            bookID: bookID,
            category: draft.category,
            tags: draft.tags,
            privateNote: draft.privateNote,
            occurredAt: now,
            createdAt: now,
            updatedAt: now
        )
        context.insert(expense)
        try context.save()
        return expense
    }
}

enum TemplateOperations {
    @MainActor
    static func setDeleted(_ deleted: Bool, for template: ExpenseTemplateItem, in context: ModelContext) throws {
        template.isTombstoned = deleted
        template.updatedAt = .nowMilliseconds
        try context.save()
    }
}

enum ExpenseCalculations {
    static func remainingMinor(for expense: ExpenseItem, settlements: [SettlementItem]) -> Int64 {
        let paid = settlements
            .filter { $0.expenseID == expense.id && !$0.isTombstoned }
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
