import Foundation
import UIKit
import UserNotifications

struct LocalStatementGenerator: StatementGenerating, Sendable {
    func csv(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data {
        var rows = [
            "occurred_at,purpose,counterparty,original_minor,settled_minor,remaining_minor,currency,status"
        ]
        for expense in expenses.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            let paid = paidMinor(for: expense, settlements: settlements)
            let remaining = remainingMinor(for: expense, paidMinor: paid)
            rows.append([
                ISO8601DateFormatter().string(from: expense.occurredAt.pinbookDate),
                expense.purpose,
                expense.counterparty,
                String(expense.amountMinor),
                String(paid),
                String(remaining),
                expense.currency,
                expense.isNoted ? "noted" : "open",
            ].map(csvField).joined(separator: ","))
        }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    func pdf(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y: CGFloat = 48
            func beginPage() {
                context.beginPage()
                y = 48
            }
            func draw(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 8) {
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
            draw(String(localized: "Pinbook statement"), font: .systemFont(ofSize: 26, weight: .bold), spacing: 4)
            if let first = expenses.first {
                draw(first.counterparty, font: .systemFont(ofSize: 17, weight: .semibold), color: .secondaryLabel, spacing: 2)
                draw(first.currency, font: .monospacedSystemFont(ofSize: 14, weight: .medium), color: .secondaryLabel, spacing: 20)
            }

            for expense in expenses.sorted(by: { $0.occurredAt < $1.occurredAt }) {
                let paid = paidMinor(for: expense, settlements: settlements)
                let remaining = remainingMinor(for: expense, paidMinor: paid)
                draw(expense.purpose, font: .systemFont(ofSize: 16, weight: .semibold), spacing: 3)
                draw(
                    expense.occurredAt.pinbookDate.formatted(date: .abbreviated, time: .omitted),
                    font: .systemFont(ofSize: 11),
                    color: .secondaryLabel,
                    spacing: 5
                )
                let original = expense.amountMinor.formattedMoney(currency: expense.currency)
                let settled = paid.formattedMoney(currency: expense.currency)
                let balance = remaining.formattedMoney(currency: expense.currency)
                draw(
                    String(localized: "Original: \(original) · Paid: \(settled) · Remaining: \(balance)"),
                    font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                    spacing: 14
                )
            }

            let totalRemaining = expenses.reduce(Int64.zero) { total, expense in
                let remaining = remainingMinor(
                    for: expense,
                    paidMinor: paidMinor(for: expense, settlements: settlements)
                )
                let (sum, overflow) = total.addingReportingOverflow(remaining)
                return overflow ? Int64.max : sum
            }
            if let currency = expenses.first?.currency {
                draw(
                    String(localized: "Total remaining: \(totalRemaining.formattedMoney(currency: currency))"),
                    font: .systemFont(ofSize: 17, weight: .bold),
                    spacing: 4
                )
            }
            draw(
                String(localized: "Generated locally by Pinbook. No exchange rate was applied."),
                font: .systemFont(ofSize: 10),
                color: .secondaryLabel
            )
        }
    }

    private func paidMinor(for expense: ExpenseRecord, settlements: [SettlementRecord]) -> Int64 {
        settlements
            .filter { $0.expenseId == expense.id && !$0.isDeleted }
            .reduce(Int64.zero) { result, settlement in
                let (sum, overflow) = result.addingReportingOverflow(settlement.amountMinor)
                return overflow ? Int64.max : sum
            }
    }

    private func remainingMinor(for expense: ExpenseRecord, paidMinor: Int64) -> Int64 {
        let (remaining, overflow) = expense.amountMinor.subtractingReportingOverflow(paidMinor)
        return overflow ? 0 : max(0, remaining)
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
            body: String(localized: "Open Pinbook to review a scheduled expense."),
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
