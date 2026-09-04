import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PreparedLocalBackup {
    let backup: PinbookBackup
    let data: Data
    let fileName: String
}

struct PreparedRestore {
    let baseline: PinbookBackup
    let incoming: PinbookBackup
    let plan: BackupMergePlan

    var preview: BackupPreview { plan.preview }
}

enum BackupRecoveryError: LocalizedError, Equatable {
    case invalidBackup
    case unsupportedBackupVersion
    case invalidReferences
    case previewExpired
    case invalidSnapshot
    case fileAccessFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackup: String(localized: "This backup is corrupt or contains invalid data.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        case .unsupportedBackupVersion: String(localized: "This backup version is not supported.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        case .invalidReferences: String(localized: "This backup contains broken record references.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        case .previewExpired: String(localized: "Local data changed after the preview. Preview the backup again.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        case .invalidSnapshot: String(localized: "This recovery snapshot is invalid.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        case .fileAccessFailed: String(localized: "The selected backup file could not be read.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        }
    }
}

struct PinbookBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupRecoveryError.fileAccessFailed
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct BackupRecoveryService {
    let context: ModelContext
    let receiptStore: any ReceiptStoring

    init(context: ModelContext, receiptStore: any ReceiptStoring = ReceiptFileStore.shared) {
        self.context = context
        self.receiptStore = receiptStore
    }

    func prepareExport(now: Int64 = .nowMilliseconds) async throws -> PreparedLocalBackup {
        do {
            let backup = try await captureBackup(exportedAt: now)
            let data = try encode(backup)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let date = formatter.string(from: Date(timeIntervalSince1970: Double(now) / 1_000))
            return PreparedLocalBackup(
                backup: backup,
                data: data,
                fileName: "pinbook-backup-\(date)-v\(backup.formatVersion).json"
            )
        } catch {
            try? recordActivity(kind: .export, status: .failed, detailCode: detailCode(for: error))
            throw error
        }
    }

    func recordExportCompletion(_ prepared: PreparedLocalBackup, succeeded: Bool) throws {
        try recordActivity(
            kind: .export,
            status: succeeded ? .succeeded : .failed,
            formatVersion: prepared.backup.formatVersion,
            recordCount: prepared.backup.totalRecordCount,
            detailCode: succeeded ? nil : "file-export"
        )
    }

    func prepareRestore(data: Data) async throws -> PreparedRestore {
        do {
            let incoming = try JSONDecoder().decode(PinbookBackup.self, from: data)
            try BackupValidator.validate(incoming)
            let baseline = try await captureBackup(exportedAt: nil)
            let plan = try makeBackupMergePlan(local: baseline, remote: incoming)
            try validateReferences(plan.merged)
            try recordActivity(
                kind: .preview,
                status: .succeeded,
                formatVersion: incoming.formatVersion,
                recordCount: incoming.totalRecordCount,
                changedCount: plan.preview.totalAppliedChanges,
                conflictCount: plan.preview.totalConflicts
            )
            return PreparedRestore(baseline: baseline, incoming: incoming, plan: plan)
        } catch {
            try? recordActivity(
                kind: .failedRestore,
                status: .failed,
                detailCode: detailCode(for: error)
            )
            throw importError(for: error)
        }
    }

    @discardableResult
    func applyRestore(_ prepared: PreparedRestore, now: Int64 = .nowMilliseconds) async throws -> BackupSnapshotItem {
        let current = try await captureBackup(exportedAt: nil)
        guard current == prepared.baseline else {
            try? recordActivity(kind: .failedRestore, status: .failed, detailCode: "preview-expired")
            throw BackupRecoveryError.previewExpired
        }

        let snapshotBackup = try copy(prepared.baseline, exportedAt: now)
        let snapshotData = try encode(snapshotBackup)
        let snapshot = BackupSnapshotItem(
            createdAt: now,
            formatVersion: snapshotBackup.formatVersion,
            recordCount: snapshotBackup.totalRecordCount,
            backupData: snapshotData
        )
        context.insert(snapshot)
        try context.save()

        let activity = BackupActivityItem(
            kind: .appliedRestore,
            status: .succeeded,
            occurredAt: now,
            formatVersion: prepared.incoming.formatVersion,
            recordCount: prepared.incoming.totalRecordCount,
            changedCount: prepared.plan.preview.totalAppliedChanges,
            conflictCount: prepared.plan.preview.totalConflicts,
            snapshotID: snapshot.id
        )
        do {
            try await applyBackup(
                prepared.plan.merged,
                replacingAll: false,
                activity: activity,
                recoveredSnapshot: nil,
                now: now
            )
            return snapshot
        } catch {
            try? recordActivity(
                kind: .failedRestore,
                status: .failed,
                formatVersion: prepared.incoming.formatVersion,
                recordCount: prepared.incoming.totalRecordCount,
                snapshotID: snapshot.id,
                detailCode: detailCode(for: error)
            )
            throw error
        }
    }

    func recover(_ snapshot: BackupSnapshotItem, now: Int64 = .nowMilliseconds) async throws {
        do {
            let backup = try JSONDecoder().decode(PinbookBackup.self, from: snapshot.backupData)
            try BackupValidator.validate(backup)
            try validateReferences(backup)
            let activity = BackupActivityItem(
                kind: .recovery,
                status: .succeeded,
                occurredAt: now,
                formatVersion: backup.formatVersion,
                recordCount: backup.totalRecordCount,
                snapshotID: snapshot.id
            )
            try await applyBackup(
                backup,
                replacingAll: true,
                activity: activity,
                recoveredSnapshot: snapshot,
                now: now
            )
        } catch {
            try? recordActivity(
                kind: .recovery,
                status: .failed,
                snapshotID: snapshot.id,
                detailCode: detailCode(for: error)
            )
            throw error
        }
    }

    func captureBackup(exportedAt: Int64?) async throws -> PinbookBackup {
        let books = try context.fetch(FetchDescriptor<BookItem>())
            .map(\.backupRecord).sorted(by: recordOrder)
        let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
            .map(\.backupRecord).sorted(by: recordOrder)
        let settlements = try context.fetch(FetchDescriptor<SettlementItem>())
            .map(\.backupRecord).sorted(by: recordOrder)
        let templates = try context.fetch(FetchDescriptor<ExpenseTemplateItem>())
            .map(\.backupRecord).sorted(by: recordOrder)
        let metadata = try context.fetch(FetchDescriptor<ReceiptMetadataItem>())
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        var receipts: [ReceiptAttachmentRecord] = []
        for item in metadata {
            let content: String
            if item.isTombstoned {
                content = ""
            } else {
                content = try await receiptStore.load(fileName: item.fileName).base64EncodedString()
            }
            receipts.append(item.backupRecord(contentBase64: content))
        }
        let appearance = try context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first?.backupRecord
        return try PinbookBackup(
            exportedAt: exportedAt,
            expenses: expenses,
            books: books,
            settlements: settlements,
            templates: templates,
            receiptAttachments: receipts,
            appearance: appearance
        )
    }

    private func applyBackup(
        _ backup: PinbookBackup,
        replacingAll: Bool,
        activity: BackupActivityItem,
        recoveredSnapshot: BackupSnapshotItem?,
        now: Int64
    ) async throws {
        let existingReceipts = try context.fetch(FetchDescriptor<ReceiptMetadataItem>())
        let oldFileNames = existingReceipts.filter { !$0.isTombstoned }.map(\.fileName)
        var stagedNames: [String: String] = [:]
        do {
            for record in backup.receiptAttachments where !record.isDeleted {
                guard let data = Data(base64Encoded: record.contentBase64) else {
                    throw BackupValidationError.invalidReceiptContent(record.id)
                }
                stagedNames[record.id] = try await receiptStore.save(
                    data: data,
                    preferredFileName: record.fileName
                )
            }

            try applyBooks(backup.books, replacingAll: replacingAll)
            try applyExpenses(backup.expenses, replacingAll: replacingAll)
            try applySettlements(backup.settlements, replacingAll: replacingAll)
            try applyTemplates(backup.templates, replacingAll: replacingAll)
            try applyReceipts(
                backup.receiptAttachments,
                stagedNames: stagedNames,
                replacingAll: replacingAll
            )
            try applyAppearance(backup.appearance)
            context.insert(activity)
            recoveredSnapshot?.recoveredAt = now
            try context.save()
        } catch {
            context.rollback()
            for fileName in stagedNames.values { try? await receiptStore.remove(fileName: fileName) }
            throw error
        }

        let newNames = Set(stagedNames.values)
        for fileName in oldFileNames where !newNames.contains(fileName) {
            try? await receiptStore.remove(fileName: fileName)
        }
    }

    private func applyBooks(_ records: [BookRecord], replacingAll: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<BookItem>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))
        for record in records {
            if let item = byID[record.id] {
                item.name = record.name
                item.createdAt = record.createdAt
                item.updatedAt = record.updatedAt
                item.isArchived = record.isArchived
            } else {
                context.insert(BookItem(
                    id: record.id,
                    name: record.name,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    isArchived: record.isArchived
                ))
            }
        }
        if replacingAll { existing.filter { !incomingIDs.contains($0.id) }.forEach(context.delete) }
    }

    private func applyExpenses(_ records: [ExpenseRecord], replacingAll: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<ExpenseItem>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))
        for record in records {
            let item = byID[record.id] ?? ExpenseItem(
                id: record.id,
                amountMinor: record.amountMinor,
                currency: record.currency,
                purpose: record.purpose,
                counterparty: record.counterparty
            )
            if byID[record.id] == nil { context.insert(item) }
            item.amountMinor = record.amountMinor
            item.currency = record.currency.uppercased()
            item.purpose = record.purpose
            item.counterparty = record.counterparty
            item.bookID = record.bookId ?? "default"
            item.category = record.category ?? ""
            item.tags = record.tags ?? []
            item.privateNote = record.privateNote ?? ""
            item.isFavorite = record.isFavorite ?? false
            item.reminderAt = record.reminderAt
            item.reminderSentAt = record.reminderSentAt
            item.occurredAt = record.occurredAt
            item.createdAt = record.createdAt
            item.updatedAt = record.updatedAt
            item.isNoted = record.isNoted
            item.notedAt = record.notedAt
        }
        if replacingAll { existing.filter { !incomingIDs.contains($0.id) }.forEach(context.delete) }
    }

    private func applySettlements(_ records: [SettlementRecord], replacingAll: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<SettlementItem>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))
        for record in records {
            let item = byID[record.id] ?? SettlementItem(
                id: record.id,
                expenseID: record.expenseId,
                amountMinor: record.amountMinor
            )
            if byID[record.id] == nil { context.insert(item) }
            item.expenseID = record.expenseId
            item.amountMinor = record.amountMinor
            item.note = record.note ?? ""
            item.occurredAt = record.occurredAt
            item.createdAt = record.createdAt
            item.updatedAt = record.updatedAt
            item.isTombstoned = record.isDeleted
        }
        if replacingAll { existing.filter { !incomingIDs.contains($0.id) }.forEach(context.delete) }
    }

    private func applyTemplates(_ records: [TemplateRecord], replacingAll: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<ExpenseTemplateItem>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))
        for record in records {
            let item = byID[record.id] ?? ExpenseTemplateItem(
                id: record.id,
                bookID: record.bookId,
                name: record.name,
                amountMinor: record.amountMinor,
                currency: record.currency,
                purpose: record.purpose,
                counterparty: record.counterparty
            )
            if byID[record.id] == nil { context.insert(item) }
            item.bookID = record.bookId
            item.name = record.name
            item.amountMinor = record.amountMinor
            item.currency = record.currency.uppercased()
            item.purpose = record.purpose
            item.counterparty = record.counterparty
            item.category = record.category ?? ""
            item.tags = record.tags ?? []
            item.privateNote = record.privateNote ?? ""
            item.createdAt = record.createdAt
            item.updatedAt = record.updatedAt
            item.isTombstoned = record.isDeleted
        }
        if replacingAll { existing.filter { !incomingIDs.contains($0.id) }.forEach(context.delete) }
    }

    private func applyReceipts(
        _ records: [ReceiptAttachmentRecord],
        stagedNames: [String: String],
        replacingAll: Bool
    ) throws {
        let existing = try context.fetch(FetchDescriptor<ReceiptMetadataItem>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(records.map(\.id))
        for record in records {
            let fileName = stagedNames[record.id] ?? byID[record.id]?.fileName ?? UUID().uuidString
            let item = byID[record.id] ?? ReceiptMetadataItem(
                id: record.id,
                expenseID: record.expenseId,
                fileName: fileName,
                mimeType: record.mimeType,
                displayName: record.displayName
            )
            if byID[record.id] == nil { context.insert(item) }
            item.expenseID = record.expenseId
            item.fileName = fileName
            item.mimeType = record.mimeType
            item.displayName = record.displayName
            item.createdAt = record.createdAt
            item.updatedAt = record.updatedAt
            item.isTombstoned = record.isDeleted
        }
        if replacingAll { existing.filter { !incomingIDs.contains($0.id) }.forEach(context.delete) }
    }

    private func applyAppearance(_ record: AppearanceRecord?) throws {
        guard let record else { return }
        let existing = try context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first
        let item = existing ?? AppearanceSettingsItem()
        if existing == nil { context.insert(item) }
        item.themeMode = record.themeMode
        item.interfaceSkin = record.interfaceSkin
        item.colorTheme = record.colorTheme
        item.font = record.font
        item.fontSize = record.fontSize
        item.expenseLayout = record.expenseLayout
        item.favoriteCurrencies = record.favoriteCurrencies
        item.preferredCurrency = record.preferredCurrency
        item.activeBookID = record.activeBookId
        item.updatedAt = record.updatedAt
    }

    private func validateReferences(_ backup: PinbookBackup) throws {
        let bookIDs = Set(backup.books.map(\.id)).union(["default"])
        let activeBookIDs = Set(backup.books.filter { !$0.isArchived }.map(\.id))
        let expenseIDs = Set(backup.expenses.map(\.id))
        guard backup.expenses.allSatisfy({ bookIDs.contains($0.bookId ?? "default") }),
              backup.settlements.allSatisfy({ expenseIDs.contains($0.expenseId) }),
              backup.templates.allSatisfy({ bookIDs.contains($0.bookId) }),
              backup.receiptAttachments.allSatisfy({ expenseIDs.contains($0.expenseId) }),
              backup.appearance.map({ activeBookIDs.contains($0.activeBookId) }) ?? true
        else { throw BackupRecoveryError.invalidReferences }
    }

    private func encode(_ backup: PinbookBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    private func copy(_ backup: PinbookBackup, exportedAt: Int64) throws -> PinbookBackup {
        try PinbookBackup(
            formatVersion: backup.formatVersion,
            exportedAt: exportedAt,
            expenses: backup.expenses,
            books: backup.books,
            settlements: backup.settlements,
            templates: backup.templates,
            receiptAttachments: backup.receiptAttachments,
            appearance: backup.appearance
        )
    }

    private func recordActivity(
        kind: BackupActivityKind,
        status: BackupActivityStatus,
        formatVersion: Int = PinbookBackup.currentFormatVersion,
        recordCount: Int = 0,
        changedCount: Int = 0,
        conflictCount: Int = 0,
        snapshotID: String? = nil,
        detailCode: String? = nil
    ) throws {
        context.insert(BackupActivityItem(
            kind: kind,
            status: status,
            formatVersion: formatVersion,
            recordCount: recordCount,
            changedCount: changedCount,
            conflictCount: conflictCount,
            snapshotID: snapshotID,
            detailCode: detailCode
        ))
        try context.save()
    }

    private func detailCode(for error: Error) -> String {
        switch error {
        case is DecodingError: "corrupt-json"
        case let error as BackupError:
            switch error { case .unsupportedVersion: "unsupported-version" }
        case is BackupValidationError: "invalid-backup"
        case BackupRecoveryError.previewExpired: "preview-expired"
        case is BackupRecoveryError: "recovery-boundary"
        default: "operation-failed"
        }
    }

    private func importError(for error: Error) -> Error {
        switch error {
        case is DecodingError, is BackupValidationError:
            BackupRecoveryError.invalidBackup
        case is BackupError:
            BackupRecoveryError.unsupportedBackupVersion
        default:
            error
        }
    }

    private func recordOrder<Record: VersionedRecord>(_ lhs: Record, _ rhs: Record) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
    }
}

private extension BookItem {
    var backupRecord: BookRecord {
        BookRecord(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, isArchived: isArchived)
    }
}

private extension ExpenseItem {
    var backupRecord: ExpenseRecord {
        ExpenseRecord(
            id: id,
            amountMinor: amountMinor,
            currency: currency,
            purpose: purpose,
            counterparty: counterparty,
            bookId: bookID,
            category: category,
            tags: tags,
            privateNote: privateNote,
            isFavorite: isFavorite,
            reminderAt: reminderAt,
            reminderSentAt: reminderSentAt,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isNoted: isNoted,
            notedAt: notedAt
        )
    }
}

private extension SettlementItem {
    var backupRecord: SettlementRecord {
        SettlementRecord(
            id: id,
            expenseId: expenseID,
            amountMinor: amountMinor,
            note: note,
            occurredAt: occurredAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isTombstoned
        )
    }
}

private extension ExpenseTemplateItem {
    var backupRecord: TemplateRecord {
        TemplateRecord(
            id: id,
            bookId: bookID,
            name: name,
            amountMinor: amountMinor,
            currency: currency,
            purpose: purpose,
            counterparty: counterparty,
            category: category,
            tags: tags,
            privateNote: privateNote,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isTombstoned
        )
    }
}

private extension ReceiptMetadataItem {
    func backupRecord(contentBase64: String) -> ReceiptAttachmentRecord {
        ReceiptAttachmentRecord(
            id: id,
            expenseId: expenseID,
            fileName: fileName,
            mimeType: mimeType,
            displayName: displayName,
            contentBase64: contentBase64,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isTombstoned
        )
    }
}

private extension AppearanceSettingsItem {
    var backupRecord: AppearanceRecord {
        AppearanceRecord(
            themeMode: themeMode,
            interfaceSkin: interfaceSkin,
            colorTheme: colorTheme,
            font: font,
            fontSize: fontSize,
            expenseLayout: expenseLayout,
            favoriteCurrencies: favoriteCurrencies,
            preferredCurrency: preferredCurrency,
            activeBookId: activeBookID,
            updatedAt: updatedAt
        )
    }
}
