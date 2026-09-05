import CryptoKit
import Foundation

struct PersonalCloudReconciliation: Sendable {
    let merged: PinbookBackup
    let remoteSnapshotCount: Int
    let downloadedSnapshotCount: Int
    let appliedChanges: Int
    let conflicts: Int
    private let verifiedContent: Set<String>

    init(merged: PinbookBackup, remoteSnapshotCount: Int,
         downloadedSnapshotCount: Int, appliedChanges: Int,
         conflicts: Int, verifiedContent: Set<String>) {
        self.merged = merged
        self.remoteSnapshotCount = remoteSnapshotCount
        self.downloadedSnapshotCount = downloadedSnapshotCount
        self.appliedChanges = appliedChanges
        self.conflicts = conflicts
        self.verifiedContent = verifiedContent
    }

    func alreadyContains(_ data: Data) -> Bool {
        verifiedContent.contains(Self.identity(data))
    }

    private static func identity(_ data: Data) -> String {
        let digest = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        return "\(data.count):\(digest)"
    }
}

/// Bounded provider-neutral read/verify/decode/merge phase. It performs no local
/// mutation and no upload, so callers can preview or save a recovery snapshot
/// before applying the returned complete backup-v8 state.
enum PersonalCloudSyncEngine {
    static let maximumRemoteBytes = 512 * 1024 * 1024

    static func reconcile(local: PinbookBackup,
                          using transport: any BackupTransport) async throws
        -> PersonalCloudReconciliation {
        let inventory = try await BackupTransportGuard.inventory(
            using: transport, maximumPages: 20, maximumObjects: 500
        )
        var merged = try canonical(local)
        var verifiedContent = Set<String>()
        var downloaded = 0
        var totalBytes = 0
        var appliedChanges = 0
        var conflicts = 0

        for snapshot in inventory {
            try Task.checkCancellation()
            let identity = "\(snapshot.byteCount):\(snapshot.sha256)"
            if verifiedContent.contains(identity) { continue }
            guard totalBytes <= maximumRemoteBytes - snapshot.byteCount else {
                throw BackupTransportError.inventoryLimit
            }
            let data = try await BackupTransportGuard.downloadVerified(
                snapshot, using: transport
            )
            totalBytes += data.count
            verifiedContent.insert(identity)
            downloaded += 1
            let remote = try canonical(JSONDecoder().decode(PinbookBackup.self, from: data))
            let plan = try makeBackupMergePlan(local: merged, remote: remote)
            appliedChanges += plan.preview.totalAppliedChanges
            conflicts += plan.preview.totalConflicts
            merged = try canonical(plan.merged)
        }
        return PersonalCloudReconciliation(
            merged: merged,
            remoteSnapshotCount: inventory.count,
            downloadedSnapshotCount: downloaded,
            appliedChanges: appliedChanges,
            conflicts: conflicts,
            verifiedContent: verifiedContent
        )
    }

    static func canonical(_ backup: PinbookBackup) throws -> PinbookBackup {
        try BackupValidator.validate(backup)
        return try PinbookBackup(
            formatVersion: backup.formatVersion, exportedAt: nil,
            expenses: backup.expenses, books: backup.books,
            settlements: backup.settlements, templates: backup.templates,
            receiptAttachments: backup.receiptAttachments,
            appearance: backup.appearance
        )
    }

    static func encode(_ backup: PinbookBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(canonical(backup))
    }
}
