import Foundation

public protocol VersionedRecord: Codable, Equatable, Identifiable, Sendable where ID == String {
    var id: String { get }
    var createdAt: Int64 { get }
    var updatedAt: Int64 { get }
}

public struct ExpenseRecord: VersionedRecord {
    public var id: String
    public var amountMinor: Int64
    public var currency: String
    public var purpose: String
    public var counterparty: String
    public var bookId: String?
    public var category: String?
    public var tags: [String]?
    public var privateNote: String?
    public var isFavorite: Bool?
    public var reminderAt: Int64?
    public var reminderSentAt: Int64?
    public var occurredAt: Int64
    public var createdAt: Int64
    public var updatedAt: Int64
    public var isNoted: Bool
    public var notedAt: Int64?

    public init(
        id: String,
        amountMinor: Int64,
        currency: String,
        purpose: String,
        counterparty: String,
        bookId: String? = nil,
        category: String? = nil,
        tags: [String]? = nil,
        privateNote: String? = nil,
        isFavorite: Bool? = nil,
        reminderAt: Int64? = nil,
        reminderSentAt: Int64? = nil,
        occurredAt: Int64,
        createdAt: Int64,
        updatedAt: Int64,
        isNoted: Bool,
        notedAt: Int64? = nil
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.purpose = purpose
        self.counterparty = counterparty
        self.bookId = bookId
        self.category = category
        self.tags = tags
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
}

public struct BookRecord: VersionedRecord {
    public var id: String
    public var name: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var isArchived: Bool

    public init(id: String, name: String, createdAt: Int64, updatedAt: Int64, isArchived: Bool) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

public struct SettlementRecord: VersionedRecord {
    public var id: String
    public var expenseId: String
    public var amountMinor: Int64
    public var note: String?
    public var occurredAt: Int64
    public var createdAt: Int64
    public var updatedAt: Int64
    public var isDeleted: Bool
}

public struct TemplateRecord: VersionedRecord {
    public var id: String
    public var bookId: String
    public var name: String
    public var amountMinor: Int64
    public var currency: String
    public var purpose: String
    public var counterparty: String
    public var category: String?
    public var tags: [String]?
    public var privateNote: String?
    public var createdAt: Int64
    public var updatedAt: Int64
    public var isDeleted: Bool
}

public struct ReceiptAttachmentRecord: VersionedRecord {
    public var id: String
    public var expenseId: String
    public var fileName: String
    public var mimeType: String
    public var displayName: String
    public var contentBase64: String
    public var createdAt: Int64
    public var updatedAt: Int64
    public var isDeleted: Bool
}

public struct AppearanceRecord: Codable, Equatable, Sendable {
    public var themeMode: String
    public var interfaceSkin: String
    public var colorTheme: String
    public var font: String
    public var fontSize: String
    public var expenseLayout: String
    public var favoriteCurrencies: [String]
    public var preferredCurrency: String?
    public var activeBookId: String
    public var updatedAt: Int64
}
