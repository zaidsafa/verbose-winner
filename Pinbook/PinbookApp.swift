import SwiftData
import SwiftUI

@main
struct PinbookApp: App {
    private let modelContainer: ModelContainer
    private let launchConfiguration: PinbookLaunchConfiguration

    init() {
        launchConfiguration = .current
        let schema = Schema(PinbookSchema.models)
        let configuration: ModelConfiguration
#if DEBUG
        if launchConfiguration.usesFixtures {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("Pinbook", schema: schema)
        }
#else
        configuration = ModelConfiguration("Pinbook", schema: schema)
#endif
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Pinbook's local store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(launchConfiguration: launchConfiguration)
        }
        .modelContainer(modelContainer)
    }
}
