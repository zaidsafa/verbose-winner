import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ReceiptSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pinbookSkin) private var skin
    @Query(sort: \ReceiptMetadataItem.createdAt, order: .reverse) private var allReceipts: [ReceiptMetadataItem]
    let expense: ExpenseItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImporting = false
    @State private var operationError: String?
    @State private var pendingDeletion: ReceiptMetadataItem?

    private var receipts: [ReceiptMetadataItem] {
        allReceipts.filter { $0.expenseID == expense.id && !$0.isTombstoned }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Import receipt photo", systemImage: "photo.badge.plus")
                    }
                    .disabled(isImporting)

                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("Copying to private storage…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Pinbook receives only the photo you choose and copies it into app-private storage. It does not request access to your full photo library.")
                }

                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No receipts",
                        systemImage: "paperclip",
                        description: Text("Attach a receipt photo to keep it with this expense.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Attached receipts") {
                        ForEach(receipts) { receipt in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(receipt.displayName)
                                    Text(receipt.createdAt.pinbookDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tint)
                            }
                            .accessibilityElement(children: .combine)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = receipt
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(skin.backdrop.ignoresSafeArea())
            .navigationTitle("Receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await importReceipt(item) }
            }
            .confirmationDialog(
                "Delete this receipt?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete receipt", role: .destructive) {
                    guard let receipt = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { await remove(receipt) }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("The private file and its attachment record will be removed from this device.")
            }
            .alert("Unable to update receipts", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK") { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    @MainActor
    private func importReceipt(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                operationError = String(localized: "The selected photo could not be read.")
                return
            }
            let contentType = item.supportedContentTypes.first ?? .image
            let fileExtension = contentType.preferredFilenameExtension ?? "img"
            let displayName = String(localized: "Receipt photo")
            try await ReceiptLifecycle.attach(
                data: data,
                preferredFileName: "receipt.\(fileExtension)",
                mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                displayName: displayName,
                to: expense,
                context: modelContext
            )
        } catch {
            operationError = error.localizedDescription
        }
    }

    @MainActor
    private func remove(_ receipt: ReceiptMetadataItem) async {
        do {
            try await ReceiptLifecycle.remove(receipt, context: modelContext)
        } catch {
            operationError = error.localizedDescription
        }
    }
}
