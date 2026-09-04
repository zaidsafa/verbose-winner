import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Security

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

/// Not linked from production navigation. A future authenticated team entry point
/// must supply its scoped store after the full activation gates are satisfied.
struct TeamReceivedArchiveRecoveryView: View {
    @Environment(\.pinbookSkin) private var skin
    @Environment(\.scenePhase) private var scenePhase
    private let accountId: String
    private let keyStore: TeamRecoveryKeyStore
    @State private var session: TeamArchiveRecoverySession
    @State private var keyText = ""
    @State private var presentation = TeamRecoveryPresentation()
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: TeamEncryptedArchiveDocument?
    @State private var preview: TeamRecoveryPreview?
    @State private var operationError: LocalizedStringKey?
    @State private var restored = false
    @State private var showingKeySetup = false
    @State private var operationTask: Task<Void, Never>?

    private var isWorking: Bool { presentation.isWorking }

    init(store: TeamInboxStore, keyStore: TeamRecoveryKeyStore = TeamRecoveryKeyStore()) {
        accountId = store.target.userId
        self.keyStore = keyStore
        _session = State(initialValue: TeamArchiveRecoverySession(store: store))
    }

    var body: some View {
        List {
            Section {
                Text("Only received text notes are included. This does not restore team access, sent drafts, revisions or attachments.")
                    .font(.footnote)
                    .accessibilityIdentifier("team-recovery-scope")
                if presentation.needsReconciliation {
                    Text("A restore may have completed. Import and preview the archive again to check the current records.")
                        .font(.footnote)
                        .accessibilityIdentifier("team-recovery-reconcile")
                }
            }
            Section("Recovery key") {
                SecureField("Recovery key", text: $keyText)
                    .environment(\.layoutDirection, .leftToRight)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .accessibilityIdentifier("team-recovery-key")
                Button("Use saved recovery key", systemImage: "key") {
                    operationTask = Task { await loadSavedKey() }
                }
                Button("Manage recovery key", systemImage: "key.horizontal") { showingKeySetup = true }
                Text("Enter 64 hexadecimal characters without separators. Imported keys are used only for this restore and are not saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Backup") {
                Button("Import and preview", systemImage: "doc.badge.plus") { showingImporter = true }
                    .disabled(keyText.isEmpty)
                Button("Export encrypted archive", systemImage: "lock.doc") {
                    operationTask = Task { await exportArchive() }
                }
                Text("Export uses the recovery key already saved on this device. Keep a safe copy of that key separately from the encrypted archive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isWorking)
        .scrollContentBackground(.hidden)
        .background(skin.backdrop.ignoresSafeArea())
        .navigationTitle("Received-note recovery")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): operationTask = Task { await importArchive(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { operationError = "The selected backup file could not be read." }
            }
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: .data, defaultFilename: "pinbook-received-notes.pinbookarchive") { result in
            exportDocument = nil
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                operationError = "Backup operation failed"
            }
        }
        .sheet(item: $preview) { candidate in
            TeamReceivedArchivePreviewView(preview: candidate) {
                await confirm(candidate)
            }
            .onDisappear { Task { await session.cancelPreview(previewID: candidate.id) } }
        }
        .sheet(isPresented: $showingKeySetup) {
            TeamRecoveryKeySetupView(accountId: accountId, store: keyStore)
        }
        .alert("Backup operation failed", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) { Button("OK") { operationError = nil } } message: {
            if let operationError { Text(operationError) }
        }
        .alert("Received notes restored", isPresented: $restored) {
            Button("OK") { restored = false }
        } message: {
            Text("Existing notes were preserved. No team access or delivery receipts were restored.")
        }
        .onAppear { if scenePhase == .active { presentation.activate() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presentation.activate() }
            else { clearSensitiveState() }
        }
        .onDisappear { clearSensitiveState() }
    }

    @MainActor private func clearSensitiveState() {
        presentation.invalidate()
        operationTask?.cancel()
        keyText = ""
        let previousID = preview?.id
        preview = nil
        exportDocument = nil
        showingImporter = false
        showingExporter = false
        showingKeySetup = false
        operationError = nil
        restored = false
        if let previousID { Task { await session.cancelPreview(previewID: previousID) } }
    }

    private func savedKey() async throws -> SymmetricKey? {
        let store = keyStore
        let account = accountId
        let task = Task.detached { try store.load(accountId: account) }
        return try await withTaskCancellationHandler {
            let key = try await task.value
            try Task.checkCancellation()
            return key
        } onCancel: { task.cancel() }
    }

    @MainActor private func loadSavedKey() async {
        guard let ticket = presentation.begin(.readKey) else { return }
        defer { presentation.finish(ticket) }
        do {
            let key = try await savedKey()
            guard presentation.accepts(ticket) else { return }
            guard let key else { operationError = "No recovery key is saved on this device. Enter your separately saved key to import."; return }
            keyText = try TeamRecoveryKeyText.encode(key)
        } catch is CancellationError { }
        catch { if presentation.accepts(ticket) { operationError = "The saved recovery key is unavailable. It has not been replaced." } }
    }

    @MainActor private func exportArchive() async {
        guard let ticket = presentation.begin(.exportArchive) else { return }
        defer { presentation.finish(ticket) }
        do {
            let key = try await savedKey()
            guard presentation.accepts(ticket) else { return }
            guard let key else { operationError = "No recovery key is saved on this device. Enter your separately saved key to import."; return }
            let compact = try await session.export(exportedAt: .nowMilliseconds, recoveryKey: key)
            guard presentation.accepts(ticket) else { return }
            exportDocument = TeamEncryptedArchiveDocument(data: Data(compact.utf8))
            showingExporter = true
        } catch is CancellationError { }
        catch { if presentation.accepts(ticket) { operationError = "Backup operation failed" } }
    }

    @MainActor private func importArchive(_ url: URL) async {
        guard let ticket = presentation.begin(.prepare) else { return }
        defer {
            if presentation.accepts(ticket) { keyText = "" }
            presentation.finish(ticket)
        }
        do {
            let key = try TeamRecoveryKeyText.decode(keyText)
            keyText = ""
            let data = try await BackupFileRead.load(url, maximumBytes: TeamArchiveJWE.maximumCompactBytes)
            guard data.allSatisfy({ $0 < 128 }) else { throw TeamArchiveError.invalidFormat }
            try Task.checkCancellation()
            let candidate = try await session.prepare(String(decoding: data, as: UTF8.self), recoveryKey: key)
            guard !Task.isCancelled, presentation.acceptPreview(ticket) else {
                await session.cancelPreview(previewID: candidate.id)
                return
            }
            preview = candidate
        } catch is CancellationError { }
        catch {
            if presentation.accepts(ticket) {
                operationError = "The archive or recovery key is invalid, unavailable or belongs to another account. Nothing was restored."
            }
        }
    }

    @MainActor private func confirm(_ candidate: TeamRecoveryPreview) async -> Bool {
        guard let ticket = presentation.begin(.restore) else { return false }
        defer { presentation.finish(ticket) }
        do {
            _ = try await session.confirm(previewID: candidate.id)
            guard presentation.acceptRestore(ticket) else { return false }
            preview = nil
            restored = true
            return true
        } catch {
            if presentation.accepts(ticket) {
                preview = nil
                operationError = "The restore preview is no longer valid. Import and preview the archive again."
            }
            return false
        }
    }
}

/// Explicit local key setup/copy. No automatic generation, clipboard, shared upload
/// or saved bookmark. The exported plaintext key file belongs to the user's destination.
private struct TeamRecoveryKeySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var flow: TeamRecoveryKeySetup?
    @State private var setupID: UUID?
    @State private var presentation = TeamRecoveryPresentation()
    @State private var consent = false
    @State private var separateCopy = false
    @State private var confirmation = ""
    @State private var exported = false
    @State private var showingExporter = false
    @State private var document: TeamRecoveryKeyDocument?
    @State private var operation: Task<Void, Never>?
    @State private var failed = false
    @State private var saved = false
    let accountId: String
    let store: TeamRecoveryKeyStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Anyone with this key and your archive can read your notes. Save the key separately. Pinbook cannot recover a lost key.")
                    Text("If you cancel after export, the key file stays where you saved it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if setupID == nil {
                    Section {
                        Toggle("I understand that this key must be kept private.", isOn: $consent)
                            .accessibilityIdentifier("key-setup-consent")
                        Button("Create recovery key") { operation = Task { await begin(.createNew) } }
                            .accessibilityIdentifier("key-setup-create")
                            .disabled(!consent)
                        Button("Back up saved key") { operation = Task { await begin(.copyExisting) } }
                            .disabled(!consent)
                    }
                } else {
                    Section {
                        Button("Save key file", systemImage: "square.and.arrow.up") {
                            operation = Task { await exportKey() }
                        }
                        .accessibilityIdentifier("key-setup-export")
                        if exported { Label("Key file saved", systemImage: "checkmark.circle") }
                    }
                    Section {
                        SecureField("Last 8 characters from the saved key", text: $confirmation)
                            .environment(\.layoutDirection, .leftToRight)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .privacySensitive()
                            .accessibilityIdentifier("key-setup-confirmation")
                        Toggle("I saved the key separately from my archive.", isOn: $separateCopy)
                        Button("Finish setup") { operation = Task { await complete() } }
                            .accessibilityIdentifier("key-setup-finish")
                            .disabled(!exported || !separateCopy || confirmation.isEmpty)
                    }
                }
            }
            .disabled(presentation.isWorking)
            .navigationTitle("Recovery key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { clear(); dismiss() }
                }
            }
            .overlay { if presentation.isWorking { ProgressView() } }
            .fileExporter(isPresented: $showingExporter, document: document,
                          contentType: .plainText,
                          defaultFilename: "pinbook-recovery-key-\(setupID?.uuidString.prefix(8).lowercased() ?? "copy").txt") { result in
                document = nil
                guard presentation.isActive, let setupID, let flow else { return }
                switch result {
                case .success(let url):
                    operation = Task {
                        do {
                            let data = try await BackupFileRead.load(url, maximumBytes: 64)
                            guard let text = String(data: data, encoding: .ascii) else { throw TeamArchiveError.invalidKey }
                            try Task.checkCancellation()
                            try await flow.verifyExportedCopy(setupID: setupID, canonicalText: text)
                            if presentation.isActive, self.setupID == setupID { exported = true }
                        } catch { if presentation.isActive { failed = true } }
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { failed = true }
                }
            }
            .alert("Recovery key", isPresented: $failed) {
                Button("OK") { failed = false }
            } message: {
                Text("Key setup could not be confirmed. Check the saved key before trying again. Existing keys are never replaced.")
            }
            .alert("Recovery key", isPresented: $saved) {
                Button("OK") { clear(); dismiss() }
            } message: {
                Text("Recovery key saved on this device.")
            }
        }
        .onAppear {
            do { if flow == nil { flow = try TeamRecoveryKeySetup(accountId: accountId, store: store) } }
            catch { failed = true }
            if scenePhase == .active { presentation.activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { clear(); dismiss() }
            else { presentation.activate() }
        }
        .onDisappear { clear() }
    }

    @MainActor private func clear() {
        presentation.invalidate()
        operation?.cancel()
        if let setupID, let flow { Task { await flow.cancel(setupID: setupID) } }
        setupID = nil
        document = nil
        confirmation = ""
        exported = false
        separateCopy = false
        consent = false
        showingExporter = false
        failed = false
        saved = false
    }

    @MainActor private func begin(_ intent: TeamRecoveryKeySetupIntent) async {
        guard let flow, let ticket = presentation.begin(.readKey) else { return }
        defer { presentation.finish(ticket) }
        do {
            let id = try await flow.begin(intent, consent: consent)
            guard presentation.accepts(ticket), !Task.isCancelled else {
                await flow.cancel(setupID: id)
                return
            }
            setupID = id
        } catch { if presentation.accepts(ticket) { failed = true } }
    }

    @MainActor private func exportKey() async {
        guard let flow, let setupID, let ticket = presentation.begin(.exportArchive) else { return }
        defer { presentation.finish(ticket) }
        do {
            let text = try await flow.textForExport(setupID: setupID)
            guard presentation.accepts(ticket), !Task.isCancelled else { return }
            document = TeamRecoveryKeyDocument(data: Data(text.utf8))
            showingExporter = true
        } catch { if presentation.accepts(ticket) { failed = true } }
    }

    @MainActor private func complete() async {
        guard let flow, let setupID, let ticket = presentation.begin(.readKey) else { return }
        defer { presentation.finish(ticket) }
        do {
            try await flow.complete(setupID: setupID, lastEightCharacters: confirmation,
                                    separateCopyConfirmed: separateCopy)
            guard presentation.accepts(ticket) else { return }
            confirmation = ""
            self.setupID = nil
            saved = true
        } catch { if presentation.accepts(ticket) { failed = true } }
    }
}

private struct TeamRecoveryKeyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count == 64,
              let text = String(data: data, encoding: .ascii) else { throw TeamArchiveError.invalidKey }
        _ = try TeamRecoveryKeyText.decode(text)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct TeamEncryptedArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= TeamArchiveJWE.maximumCompactBytes else { throw TeamArchiveError.tooLarge }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct TeamReceivedArchivePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: TeamRecoveryPreview
    let apply: @MainActor () async -> Bool
    @State private var confirming = false
    @State private var applying = false

    var body: some View {
        NavigationStack {
            List {
                Section("Backup") {
                    LabeledContent("Incoming records", value: "\(preview.recordCount)")
                    LabeledContent("Teams", value: "\(preview.teamCount)")
                    LabeledContent("Exported", value: formattedBackupTimestamp(preview.exportedAt))
                }
                Section {
                    HStack {
                        PreviewCount(title: "Add", value: preview.changes.newRecords)
                        PreviewCount(title: "Unchanged", value: preview.changes.unchangedRecords)
                        PreviewCount(title: "Conflict", value: preview.changes.conflictingRecords)
                    }
                    Text("Existing notes are never overwritten. Any conflict blocks the entire restore. No team access or delivery receipts are restored.")
                        .font(.footnote)
                    Button("Apply restore") { confirming = true }
                        .accessibilityIdentifier("team-restore-preview-apply")
                        .disabled(applying || !preview.changes.canRestore || preview.changes.newRecords == 0)
                }
            }
            .navigationTitle("Restore preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(applying)
                }
            }
            .confirmationDialog("Apply this restore?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Apply restore") {
                    Task {
                        applying = true
                        if await apply() { dismiss() }
                        applying = false
                    }
                }
                .accessibilityIdentifier("team-restore-confirm")
                Button("Cancel", role: .cancel) { }
                    .accessibilityIdentifier("team-restore-confirm-cancel")
            }
        }
        .interactiveDismissDisabled(applying)
    }
}

#if DEBUG
/// Entirely in-memory test custody; never reads or writes real Keychain items.
private final class TeamKeySetupDebugKeychain: TeamRecoveryKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: Any]?
    func add(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            guard value == nil else { return errSecDuplicateItem }
            value = query
            return errSecSuccess
        }
    }
    func copy(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lock.withLock {
            guard let value else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, value as CFDictionary)
        }
    }
}

struct TeamRecoveryKeySetupDebugHost: View {
    @State private var store = TeamRecoveryKeyStore(testService: "public-ui-fixture", keychain: TeamKeySetupDebugKeychain())
    var body: some View { TeamRecoveryKeySetupView(accountId: "public-test-user", store: store) }
}

/// Public synthetic data only, reachable solely with both the ephemeral-store and
/// explicit preview-fixture launch flags. Never reads production custody/accounts.
struct TeamRecoveryPreviewDebugHost: View {
    @State private var preview: TeamRecoveryPreview?
    @State private var session: TeamArchiveRecoverySession?
    @State private var result = false
    @State private var failed = false

    var body: some View {
        Group {
            if result {
                Text("Received notes restored").accessibilityIdentifier("team-fixture-restored")
            } else if failed {
                Text("Backup operation failed").accessibilityIdentifier("team-fixture-error")
            } else if let preview, let session {
                TeamReceivedArchivePreviewView(preview: preview) {
                    do {
                        let restored = try await session.confirm(previewID: preview.id)
                        result = restored.inserted == 1 && restored.unchanged == 0
                        failed = !result
                        return result
                    } catch { failed = true; return false }
                }
            } else { ProgressView() }
        }
        .task {
            guard preview == nil && !result && !failed else { return }
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinbookRecoveryUIPublic-\(UUID())")
                let target = try DeliveryTarget(userId: "public-test-user", deviceId: "public-test-device", enrollmentId: "public-test-enrollment")
                let store = try TeamInboxStore(applicationSupportDirectory: root, target: target, teamId: "public-test-team")
                let body = "Public recovery UI fixture"
                let envelope = TeamNoteEnvelope(protocolVersion: 1, teamId: "public-test-team", deliveryId: "public-delivery",
                    noteId: "public-note", authorUserId: "public-author", recipient: target, body: body,
                    bodySha256: TeamDeliveryRules.textSHA256(body), acceptedAt: 1000, expiresAt: 2_592_001_000,
                    attachmentCount: 0)
                let archive = try TeamPortableArchive(accountId: target.userId, exportedAt: 3000,
                    notes: [ArchivedTeamNote(envelope: envelope, savedAt: 2000)])
                let key = SymmetricKey(data: Data(0..<32))
                let compact = try TeamArchiveJWE.encrypt(archive, recoveryKey: key)
                let flow = TeamArchiveRecoverySession(store: store)
                self.session = flow
                self.preview = try await flow.prepare(compact, recoveryKey: key)
            } catch { failed = true }
        }
    }
}
#endif
