import Foundation

public struct PinbookBackup: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 8

    public var formatVersion: Int
    public var exportedAt: Int64?
    public var expenses: [ExpenseRecord]
    public var books: [BookRecord]
    public var settlements: [SettlementRecord]
    public var templates: [TemplateRecord]
    public var receiptAttachments: [ReceiptAttachmentRecord]
    public var appearance: AppearanceRecord?

    public init(
        formatVersion: Int = currentFormatVersion,
        exportedAt: Int64? = nil,
        expenses: [ExpenseRecord] = [],
        books: [BookRecord] = [],
        settlements: [SettlementRecord] = [],
        templates: [TemplateRecord] = [],
        receiptAttachments: [ReceiptAttachmentRecord] = [],
        appearance: AppearanceRecord? = nil
    ) throws {
        guard (1...Self.currentFormatVersion).contains(formatVersion) else {
            throw BackupError.unsupportedVersion(formatVersion)
        }
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.expenses = expenses
        self.books = books
        self.settlements = settlements
        self.templates = templates
        self.receiptAttachments = receiptAttachments
        self.appearance = appearance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        guard (1...Self.currentFormatVersion).contains(formatVersion) else {
            throw BackupError.unsupportedVersion(formatVersion)
        }
        exportedAt = try values.decodeIfPresent(Int64.self, forKey: .exportedAt)
        expenses = try values.decodeIfPresent([ExpenseRecord].self, forKey: .expenses) ?? []
        books = try values.decodeIfPresent([BookRecord].self, forKey: .books) ?? []
        settlements = try values.decodeIfPresent([SettlementRecord].self, forKey: .settlements) ?? []
        templates = try values.decodeIfPresent([TemplateRecord].self, forKey: .templates) ?? []
        receiptAttachments = try values.decodeIfPresent(
            [ReceiptAttachmentRecord].self,
            forKey: .receiptAttachments
        ) ?? []
        appearance = try values.decodeIfPresent(AppearanceRecord.self, forKey: .appearance)
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}
