import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupRecoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query(sort: \BackupActivityItem.occurredAt, order: .reverse) private var activities: [BackupActivityItem]
    @Query(sort: \BackupSnapshotItem.createdAt, order: .reverse) private var snapshots: [BackupSnapshotItem]
    @Query private var books: [BookItem]
    @Query private var expenses: [ExpenseItem]
    @Query private var settlements: [SettlementItem]
    @Query private var templates: [ExpenseTemplateItem]
    @Query private var receipts: [ReceiptMetadataItem]
    @Query private var appearances: [AppearanceSettingsItem]

    @State private var preparedExport: PreparedLocalBackup?
    @State private var exportDocument: PinbookBackupDocument?
    @State private var preparedRestore: PreparedRestore?
    @State private var recoveryCandidate: BackupSnapshotItem?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingPreview = false
    @State private var isWorking = false
    @State private var operationError: String?
    @State private var completionMessage: String?
    @State private var importTask: Task<Void, Never>?

    private var service: BackupRecoveryService { BackupRecoveryService(context: modelContext) }
    private var recordCount: Int {
        books.count + expenses.count + settlements.count + templates.count + receipts.count + appearances.count
    }
    private var latestSuccessfulExport: BackupActivityItem? {
        activities.first { $0.kind == .export && $0.status == .succeeded }
    }
    private var healthStatus: String {
        latestSuccessfulExport == nil
            ? String(localized: "Not exported yet", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
            : String(localized: "Backup exported", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
    }

    var body: some View {
        List {
            backupHealthSection
            manualBackupSection
            recoverySnapshotsSection
            localActivitySection
        }
        .contentMargins(.bottom, PinbookLayout.tabBarScrollClearance, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Backup & Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .onDisappear { importTask?.cancel() }
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: preparedExport?.fileName ?? "pinbook-backup.json"
        ) { result in
            guard let preparedExport else { return }
            do {
                _ = try result.get()
                try service.recordExportCompletion(preparedExport, succeeded: true)
                completionMessage = String(localized: "Backup exported", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
            } catch {
                if (error as NSError).code != NSUserCancelledError {
                    try? service.recordExportCompletion(preparedExport, succeeded: false)
                    operationError = error.localizedDescription
                }
            }
            self.preparedExport = nil
            exportDocument = nil
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importTask = Task { await importBackup(from: url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { operationError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingPreview, onDismiss: { preparedRestore = nil }) {
            if let preparedRestore {
                RestorePreviewView(prepared: preparedRestore) {
                    await apply(preparedRestore)
                }
            }
        }
        .confirmationDialog(
            "Recover this snapshot?",
            isPresented: Binding(
                get: { recoveryCandidate != nil },
                set: { if !$0 { recoveryCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Recover snapshot", role: .destructive) {
                guard let snapshot = recoveryCandidate else { return }
                recoveryCandidate = nil
                Task { await recover(snapshot) }
            }
            Button("Keep current data", role: .cancel) { recoveryCandidate = nil }
        } message: {
            Text("Current financial records will be replaced with the exact pre-restore snapshot. Backup history and snapshots remain available.")
        }
        .alert("Backup operation failed", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
        .alert("Backup & Recovery", isPresented: Binding(
            get: { completionMessage != nil },
            set: { if !$0 { completionMessage = nil } }
        )) {
            Button("OK") { completionMessage = nil }
        } message: {
            Text(completionMessage ?? "")
        }
    }

    private var backupHealthSection: some View {
        Section("Backup health") {
            LabeledContent("Status", value: healthStatus)
            LabeledContent("Backup format", value: "v\(PinbookBackup.currentFormatVersion)")
            LabeledContent("Local records", value: "\(recordCount)")
            if let latestSuccessfulExport {
                LabeledContent("Last export") {
                    Text(formattedBackupTimestamp(latestSuccessfulExport.occurredAt))
                }
            }
        }
    }

    private var manualBackupSection: some View {
        Section("Manual backup") {
            Button("Export backup", systemImage: "square.and.arrow.up") {
                Task { await prepareExport() }
            }
            Button("Import and preview", systemImage: "doc.badge.plus") {
                showingImporter = true
            }
            Text("Export and import use the system Files workflow. No cloud provider is connected, and no data leaves this device unless you choose a destination.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recoverySnapshotsSection: some View {
        if !snapshots.isEmpty {
            Section {
                ForEach(snapshots.prefix(3)) { snapshot in
                    Button {
                        recoveryCandidate = snapshot
                    } label: {
                        BackupSnapshotRow(snapshot: snapshot)
                    }
                }
            } header: {
                Text("Recovery snapshots")
            } footer: {
                Text("Pinbook creates a local snapshot before every applied restore. Recovery replaces financial records with that exact pre-restore state.")
            }
        }
    }

    private var localActivitySection: some View {
        Section {
            if activities.isEmpty {
                Text("No backup activity yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activities.prefix(12)) { activity in
                    BackupActivityRow(activity: activity)
                }
            }
        } header: {
            Text("Local activity")
        } footer: {
            Text("History stores only action, status, time, format, and counts. It never stores people, purposes, amounts, filenames, or receipt contents.")
                .accessibilityIdentifier("backup-history-privacy-footer")
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let prepared = try await service.prepareExport()
            preparedExport = prepared
            exportDocument = PinbookBackupDocument(data: prepared.data)
            showingExporter = true
        } catch {
            operationError = error.localizedDescription
        }
    }

    @MainActor
    private func importBackup(from url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await BackupFileRead.load(url)
            try Task.checkCancellation()
            preparedRestore = try await service.prepareRestore(data: data)
            try Task.checkCancellation()
            showingPreview = true
        } catch is CancellationError {
            preparedRestore = nil
        } catch {
            operationError = error.localizedDescription
        }
    }

    @MainActor
    private func apply(_ prepared: PreparedRestore) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await service.applyRestore(prepared)
            showingPreview = false
            completionMessage = String(localized: "Restore applied. A recovery snapshot was saved.", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func recover(_ snapshot: BackupSnapshotItem) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.recover(snapshot)
            completionMessage = String(localized: "Recovery completed", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct BackupSnapshotRow: View {
    let snapshot: BackupSnapshotItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedBackupTimestamp(snapshot.createdAt))
            Text(backupSnapshotSummary(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
            if snapshot.recoveredAt != nil {
                Text("Recovered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RestorePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinbookSkin) private var skin
    let prepared: PreparedRestore
    let apply: @MainActor () async -> Bool
    @State private var confirmingApply = false
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            List {
                Section("Backup") {
                    LabeledContent("Format", value: "v\(prepared.preview.formatVersion)")
                    LabeledContent("Incoming records", value: "\(prepared.preview.totalIncomingRecords)")
                    if let exportedAt = prepared.preview.exportedAt {
                        LabeledContent("Exported") {
                            Text(formattedBackupTimestamp(exportedAt))
                        }
                    }
                }

                Section("Changes by entity") {
                    ForEach(prepared.preview.summaries, id: \.entity) { summary in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(summary.entity.localizedTitle).font(.headline)
                            HStack {
                                PreviewCount(title: "Add", value: summary.added)
                                PreviewCount(title: "Update", value: summary.updated)
                                PreviewCount(title: "Unchanged", value: summary.unchanged)
                                PreviewCount(title: "Conflict", value: summary.conflicts)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Text("Conflicts are equal-timestamp differences. Pinbook keeps the local record on ties. Currency codes remain attached to each record and are never converted or combined.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Apply restore", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", role: .destructive) {
                        confirmingApply = true
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isApplying || prepared.preview.totalAppliedChanges == 0)
                } footer: {
                    Text("Applying creates a recoverable local snapshot first. No records change until you confirm.")
                }
            }
            .contentMargins(.bottom, PinbookLayout.tabBarScrollClearance, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(skin.backdrop.ignoresSafeArea())
            .navigationTitle("Restore preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .confirmationDialog("Apply this restore?", isPresented: $confirmingApply, titleVisibility: .visible) {
                Button("Apply restore", role: .destructive) {
                    Task {
                        isApplying = true
                        if await apply() { dismiss() }
                        isApplying = false
                    }
                }
                Button("Keep current data", role: .cancel) {}
            } message: {
                Text("Pinbook will save the current state as a recovery snapshot, then apply only newer and new records. Equal-timestamp conflicts stay local.")
            }
        }
        .interactiveDismissDisabled(isApplying)
    }
}

private struct PreviewCount: View {
    let title: LocalizedStringKey
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(value)").font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BackupActivityRow: View {
    let activity: BackupActivityItem

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: activity.status == .succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(activity.status == .succeeded ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.kind.localizedTitle)
                Text(formattedBackupTimestamp(activity.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(backupActivitySummary(activity))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(activity.status == .succeeded ? "Succeeded" : "Failed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension BackupEntityKind {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .books: "Books"
        case .expenses: "Expenses"
        case .settlements: "Payments"
        case .templates: "Templates"
        case .receiptAttachments: "Receipts"
        case .appearance: "Appearance"
        }
    }
}

private extension BackupActivityKind {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .export: "Backup export"
        case .preview: "Restore preview"
        case .appliedRestore: "Restore applied"
        case .failedRestore: "Restore failed"
        case .recovery: "Snapshot recovery"
        }
    }
}

private func formattedBackupTimestamp(_ milliseconds: Int64) -> String {
    milliseconds.pinbookDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: PinbookLanguage.currentLocale))
}

private func backupSnapshotSummary(_ snapshot: BackupSnapshotItem) -> String {
    String(localized: "v\(snapshot.formatVersion) · \(snapshot.recordCount) records", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
}

private func backupActivitySummary(_ activity: BackupActivityItem) -> String {
    String(localized: "v\(activity.formatVersion) · \(activity.recordCount) records · \(activity.changedCount) changes · \(activity.conflictCount) conflicts", bundle: PinbookLanguage.localizedBundle, locale: PinbookLanguage.currentLocale)
}
