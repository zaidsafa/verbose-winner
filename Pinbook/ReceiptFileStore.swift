import Foundation
import SwiftData

enum ReceiptFileStoreError: Error, Equatable {
    case invalidFileName
}

actor ReceiptFileStore: ReceiptStoring {
    static let shared = ReceiptFileStore()

    private let directory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootDirectory {
            directory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = applicationSupport.appending(path: "Receipts", directoryHint: .isDirectory)
        }
    }

    func save(data: Data, preferredFileName: String) async throws -> String {
        try prepareDirectory()
        let fileName = UUID().uuidString + safeExtension(from: preferredFileName)
        let fileURL = directory.appending(path: fileName, directoryHint: .notDirectory)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        return fileName
    }

    func load(fileName: String) async throws -> Data {
        try Data(contentsOf: safeURL(for: fileName), options: [.mappedIfSafe])
    }

    func remove(fileName: String) async throws {
        let fileURL = try safeURL(for: fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
    }

    private func safeURL(for fileName: String) throws -> URL {
        guard !fileName.isEmpty,
              fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.contains("/") && !fileName.contains("\\")
        else { throw ReceiptFileStoreError.invalidFileName }
        return directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    private func safeExtension(from preferredFileName: String) -> String {
        let candidate = URL(fileURLWithPath: preferredFileName).pathExtension.lowercased()
        guard !candidate.isEmpty,
              candidate.count <= 10,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return "" }
        return ".\(candidate)"
    }
}

enum ReceiptLifecycle {
    @MainActor
    @discardableResult
    static func attach(
        data: Data,
        preferredFileName: String,
        mimeType: String,
        displayName: String,
        to expense: ExpenseItem,
        context: ModelContext,
        store: any ReceiptStoring = ReceiptFileStore.shared
    ) async throws -> ReceiptMetadataItem {
        let fileName = try await store.save(data: data, preferredFileName: preferredFileName)
        let metadata = ReceiptMetadataItem(
            expenseID: expense.id,
            fileName: fileName,
            mimeType: mimeType,
            displayName: displayName
        )
        context.insert(metadata)
        do {
            try context.save()
            return metadata
        } catch {
            try? await store.remove(fileName: fileName)
            throw error
        }
    }

    @MainActor
    static func remove(
        _ metadata: ReceiptMetadataItem,
        context: ModelContext,
        store: any ReceiptStoring = ReceiptFileStore.shared
    ) async throws {
        try await store.remove(fileName: metadata.fileName)
        metadata.isTombstoned = true
        metadata.updatedAt = .nowMilliseconds
        try context.save()
    }
}
