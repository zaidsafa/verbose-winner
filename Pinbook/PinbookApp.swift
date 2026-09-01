import SwiftData
import SwiftUI

@main
struct PinbookApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema(PinbookSchema.models)
        let configuration = ModelConfiguration("Pinbook", schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Pinbook's local store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .modelContainer(modelContainer)
    }
}
