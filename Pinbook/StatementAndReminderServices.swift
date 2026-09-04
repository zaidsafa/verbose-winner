import Foundation
import UIKit
import UserNotifications

enum StatementGenerationError: LocalizedError, Equatable {
    case arithmeticOverflow

    var errorDescription: String? {
        String(localized: "Statement values exceed the supported range.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
    }
}

struct LocalStatementGenerator: StatementGenerating, Sendable {
    func csv(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data {
        var rows = [
            "occurred_at,purpose,counterparty,original_minor,settled_minor,remaining_minor,currency,status"
        ]
        for line in try statementLines(for: expenses, settlements: settlements) {
            let expense = line.expense
            rows.append([
                ISO8601DateFormatter().string(from: expense.occurredAt.pinbookDate),
                spreadsheetSafeField(expense.purpose),
                spreadsheetSafeField(expense.counterparty),
                String(expense.amountMinor),
                String(line.paidMinor),
                String(line.remainingMinor),
                expense.currency,
                expense.isNoted ? "noted" : "open",
            ].map(csvField).joined(separator: ","))
        }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    func pdf(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data {
        let lines = try statementLines(for: expenses, settlements: settlements)
        let totalRemaining = try lines.reduce(Int64.zero) { total, line in
            let (sum, overflow) = total.addingReportingOverflow(line.remainingMinor)
            guard !overflow else { throw StatementGenerationError.arithmeticOverflow }
            return sum
        }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y: CGFloat = 48
            func beginPage() {
                context.beginPage()
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(page)
                y = 48
            }
            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 8) {
                if y > page.height - 80 { beginPage() }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
                let bounds = CGRect(x: 48, y: y, width: page.width - 96, height: page.height - y - 40)
                let height = (text as NSString).boundingRect(
                    with: bounds.size,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).height
                (text as NSString).draw(in: CGRect(x: bounds.minX, y: y, width: bounds.width, height: height), withAttributes: attributes)
                y += height + spacing
            }

            beginPage()
            draw(String(localized: "Pinbook statement", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale), font: .systemFont(ofSize: 26, weight: .bold), spacing: 4)
            if let first = expenses.first {
                draw(first.counterparty, font: .systemFont(ofSize: 17, weight: .semibold), color: .darkGray, spacing: 2)
                draw(first.currency, font: .monospacedSystemFont(ofSize: 14, weight: .medium), color: .darkGray, spacing: 20)
            }

            for line in lines {
                let expense = line.expense
                draw(expense.purpose, font: .systemFont(ofSize: 16, weight: .semibold), spacing: 3)
                draw(
                    expense.occurredAt.pinbookDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: PinbookLanguage.currentLocale)),
                    font: .systemFont(ofSize: 11),
                    color: .darkGray,
                    spacing: 5
                )
                let original = expense.amountMinor.formattedMoney(currency: expense.currency)
                let settled = line.paidMinor.formattedMoney(currency: expense.currency)
                let balance = line.remainingMinor.formattedMoney(currency: expense.currency)
                draw(
                    String(localized: "Original: \(original) · Paid: \(settled) · Remaining: \(balance)", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale),
                    font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                    spacing: 14
                )
            }

            if let currency = expenses.first?.currency {
                draw(
                    String(localized: "Total remaining: \(totalRemaining.formattedMoney(currency: currency))", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale),
                    font: .systemFont(ofSize: 17, weight: .bold),
                    spacing: 4
                )
            }
            draw(
                String(localized: "Generated locally by Pinbook. No exchange rate was applied.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale),
                font: .systemFont(ofSize: 10),
                color: .darkGray
            )
        }
    }

    private func statementLines(
        for expenses: [ExpenseRecord],
        settlements: [SettlementRecord]
    ) throws -> [StatementLine] {
        try expenses.sorted(by: { $0.occurredAt < $1.occurredAt }).map { expense in
            let paid = try settlements
                .filter { $0.expenseId == expense.id && !$0.isDeleted }
                .reduce(Int64.zero) { result, settlement in
                    let (sum, overflow) = result.addingReportingOverflow(settlement.amountMinor)
                    guard !overflow else { throw StatementGenerationError.arithmeticOverflow }
                    return sum
                }
            let (remaining, overflow) = expense.amountMinor.subtractingReportingOverflow(paid)
            guard !overflow else { throw StatementGenerationError.arithmeticOverflow }
            return StatementLine(expense: expense, paidMinor: paid, remainingMinor: max(0, remaining))
        }
    }

    private func spreadsheetSafeField(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        return "'\(value)"
    }

    private struct StatementLine {
        let expense: ExpenseRecord
        let paidMinor: Int64
        let remainingMinor: Int64
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum StatementFileWriter {
    static func write(_ data: Data, person: String, currency: String, extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PinbookStatements", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)

        let safePerson = person
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = safePerson.isEmpty ? "person" : safePerson
        let url = directory.appending(path: "pinbook-\(base)-\(currency.lowercased()).\(fileExtension)")
        try data.write(to: url, options: [.atomic])
        return url
    }
}

struct ReminderRequestSpec: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let dateComponents: DateComponents
}

enum ReminderRequestFactory {
    static func make(expenseID: String, at date: Date, title: String, calendar: Calendar = .current) -> ReminderRequestSpec {
        ReminderRequestSpec(
            identifier: "pinbook-expense-\(expenseID)",
            title: title,
            body: String(localized: "Open Pinbook to review a scheduled expense.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale),
            dateComponents: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        )
    }
}

actor LocalReminderScheduler: ReminderScheduling {
    static let shared = LocalReminderScheduler()
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(expenseID: String, at date: Date, title: String) async throws {
        let spec = ReminderRequestFactory.make(expenseID: expenseID, at: date, title: title)
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: spec.dateComponents, repeats: false)
        try await center.add(UNNotificationRequest(identifier: spec.identifier, content: content, trigger: trigger))
    }

    func cancel(expenseID: String) async {
        center.removePendingNotificationRequests(withIdentifiers: ["pinbook-expense-\(expenseID)"])
    }
}

extension ExpenseItem {
    var statementRecord: ExpenseRecord {
        ExpenseRecord(
            id: id,
            amountMinor: amountMinor,
            currency: currency,
            purpose: purpose,
            counterparty: counterparty,
            bookId: bookID,
            category: category,
            tags: tags,
            privateNote: nil,
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

extension SettlementItem {
    var statementRecord: SettlementRecord {
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
