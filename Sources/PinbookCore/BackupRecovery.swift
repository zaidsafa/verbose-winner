import Foundation

public enum BackupEntityKind: String, CaseIterable, Codable, Equatable, Sendable {
    case books
    case expenses
    case settlements
    case templates
    case receiptAttachments
    case appearance
}

public struct BackupChangeSummary: Codable, Equatable, Sendable {
    public let entity: BackupEntityKind
    public let added: Int
    public let updated: Int
    public let unchanged: Int
    public let conflicts: Int

    public init(entity: BackupEntityKind, added: Int, updated: Int, unchanged: Int, conflicts: Int) {
        self.entity = entity
        self.added = added
        self.updated = updated
        self.unchanged = unchanged
        self.conflicts = conflicts
    }

    public var incomingCount: Int { added + updated + unchanged + conflicts }
    public var appliedChangeCount: Int { added + updated }
}

public struct BackupPreview: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let exportedAt: Int64?
    public let summaries: [BackupChangeSummary]

    public init(formatVersion: Int, exportedAt: Int64?, summaries: [BackupChangeSummary]) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.summaries = summaries
    }

    public var totalIncomingRecords: Int { summaries.reduce(0) { $0 + $1.incomingCount } }
    public var totalAppliedChanges: Int { summaries.reduce(0) { $0 + $1.appliedChangeCount } }
    public var totalConflicts: Int { summaries.reduce(0) { $0 + $1.conflicts } }
}

public struct BackupMergePlan: Equatable, Sendable {
    public let preview: BackupPreview
    public let merged: PinbookBackup

    public init(preview: BackupPreview, merged: PinbookBackup) {
        self.preview = preview
        self.merged = merged
    }
}

public enum BackupValidationError: Error, Equatable, Sendable {
    case emptyIdentifier(BackupEntityKind)
    case duplicateIdentifier(BackupEntityKind, String)
    case invalidCurrency(BackupEntityKind, String, String)
    case invalidReceiptContent(String)
    case emptyActiveBook
}

public enum BackupValidator {
    public static func validate(_ backup: PinbookBackup) throws {
        try validateIdentifiers(backup.books, entity: .books)
        try validateIdentifiers(backup.expenses, entity: .expenses)
        try validateIdentifiers(backup.settlements, entity: .settlements)
        try validateIdentifiers(backup.templates, entity: .templates)
        try validateIdentifiers(backup.receiptAttachments, entity: .receiptAttachments)

        for expense in backup.expenses {
            do {
                _ = try MoneyAmount(minorUnits: expense.amountMinor, currencyCode: expense.currency)
            } catch {
                throw BackupValidationError.invalidCurrency(.expenses, expense.id, expense.currency)
            }
        }
        for template in backup.templates {
            do {
                _ = try MoneyAmount(minorUnits: template.amountMinor, currencyCode: template.currency)
            } catch {
                throw BackupValidationError.invalidCurrency(.templates, template.id, template.currency)
            }
        }
        for receipt in backup.receiptAttachments where !receipt.isDeleted {
            guard Data(base64Encoded: receipt.contentBase64) != nil else {
                throw BackupValidationError.invalidReceiptContent(receipt.id)
            }
        }
        if let appearance = backup.appearance {
            if appearance.activeBookId.isEmpty {
                throw BackupValidationError.emptyActiveBook
            }
            for currency in appearance.favoriteCurrencies {
                try validateCurrency(currency, entity: .appearance, id: "favoriteCurrencies")
            }
            if let preferredCurrency = appearance.preferredCurrency {
                try validateCurrency(preferredCurrency, entity: .appearance, id: "preferredCurrency")
            }
        }
    }

    private static func validateIdentifiers<Record: VersionedRecord>(
        _ records: [Record],
        entity: BackupEntityKind
    ) throws {
        var seen = Set<String>()
        for record in records {
            guard !record.id.isEmpty else { throw BackupValidationError.emptyIdentifier(entity) }
            guard seen.insert(record.id).inserted else {
                throw BackupValidationError.duplicateIdentifier(entity, record.id)
            }
        }
    }

    private static func validateCurrency(
        _ currency: String,
        entity: BackupEntityKind,
        id: String
    ) throws {
        do {
            _ = try MoneyAmount(minorUnits: 0, currencyCode: currency)
        } catch {
            throw BackupValidationError.invalidCurrency(entity, id, currency)
        }
    }
}

public func makeBackupMergePlan(local: PinbookBackup, remote: PinbookBackup) throws -> BackupMergePlan {
    try BackupValidator.validate(local)
    try BackupValidator.validate(remote)

    let books = mergeNewest(local: local.books, remote: remote.books)
    let expenses = mergeNewest(local: local.expenses, remote: remote.expenses)
    let settlements = mergeNewest(local: local.settlements, remote: remote.settlements)
    let templates = mergeNewest(local: local.templates, remote: remote.templates)
    let receipts = mergeNewest(local: local.receiptAttachments, remote: remote.receiptAttachments)
    let appearance = mergeAppearance(local: local.appearance, remote: remote.appearance)

    let summaries = [
        classify(local: local.books, remote: remote.books, entity: .books),
        classify(local: local.expenses, remote: remote.expenses, entity: .expenses),
        classify(local: local.settlements, remote: remote.settlements, entity: .settlements),
        classify(local: local.templates, remote: remote.templates, entity: .templates),
        classify(local: local.receiptAttachments, remote: remote.receiptAttachments, entity: .receiptAttachments),
        appearance.summary,
    ]

    let merged = try PinbookBackup(
        formatVersion: PinbookBackup.currentFormatVersion,
        exportedAt: max(local.exportedAt ?? 0, remote.exportedAt ?? 0),
        expenses: expenses.records,
        books: books.records,
        settlements: settlements.records,
        templates: templates.records,
        receiptAttachments: receipts.records,
        appearance: appearance.record
    )
    return BackupMergePlan(
        preview: BackupPreview(
            formatVersion: remote.formatVersion,
            exportedAt: remote.exportedAt,
            summaries: summaries
        ),
        merged: merged
    )
}

public extension PinbookBackup {
    var totalRecordCount: Int {
        expenses.count
            + books.count
            + settlements.count
            + templates.count
            + receiptAttachments.count
            + (appearance == nil ? 0 : 1)
    }
}

private func classify<Record: VersionedRecord>(
    local: [Record],
    remote: [Record],
    entity: BackupEntityKind
) -> BackupChangeSummary {
    let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    var added = 0
    var updated = 0
    var unchanged = 0
    var conflicts = 0

    for incoming in remote {
        guard let existing = localByID[incoming.id] else {
            added += 1
            continue
        }
        if incoming == existing || incoming.updatedAt < existing.updatedAt {
            unchanged += 1
        } else if incoming.updatedAt > existing.updatedAt {
            updated += 1
        } else {
            conflicts += 1
        }
    }
    return BackupChangeSummary(
        entity: entity,
        added: added,
        updated: updated,
        unchanged: unchanged,
        conflicts: conflicts
    )
}

private func mergeAppearance(
    local: AppearanceRecord?,
    remote: AppearanceRecord?
) -> (record: AppearanceRecord?, summary: BackupChangeSummary) {
    guard let remote else {
        return (local, BackupChangeSummary(entity: .appearance, added: 0, updated: 0, unchanged: 0, conflicts: 0))
    }
    guard let local else {
        return (remote, BackupChangeSummary(entity: .appearance, added: 1, updated: 0, unchanged: 0, conflicts: 0))
    }
    if remote == local || remote.updatedAt < local.updatedAt {
        return (local, BackupChangeSummary(entity: .appearance, added: 0, updated: 0, unchanged: 1, conflicts: 0))
    }
    if remote.updatedAt > local.updatedAt {
        return (remote, BackupChangeSummary(entity: .appearance, added: 0, updated: 1, unchanged: 0, conflicts: 0))
    }
    return (local, BackupChangeSummary(entity: .appearance, added: 0, updated: 0, unchanged: 0, conflicts: 1))
}
