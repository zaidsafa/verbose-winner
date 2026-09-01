import Foundation

/// Ports define future capability boundaries without claiming an implementation.
public protocol BackupTransport: Sendable {
    func download() async throws -> Data?
    func upload(_ backup: Data) async throws
}

public protocol ReceiptStoring: Sendable {
    func save(data: Data, preferredFileName: String) async throws -> String
    func load(fileName: String) async throws -> Data
    func remove(fileName: String) async throws
}

public protocol StatementGenerating: Sendable {
    func pdf(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data
    func csv(for expenses: [ExpenseRecord], settlements: [SettlementRecord]) throws -> Data
}

public protocol ReminderScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func schedule(expenseID: String, at date: Date, title: String) async throws
    func cancel(expenseID: String) async
}

public protocol ReceiptTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [String]
}
