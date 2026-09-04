import SwiftData
import SwiftUI

@main
struct PinbookApp: App {
    private let modelContainer: ModelContainer
    private let launchConfiguration: PinbookLaunchConfiguration

    init() {
        launchConfiguration = .current
#if DEBUG
        if launchConfiguration.usesEphemeralStore {
            let arguments = ProcessInfo.processInfo.arguments
            if !arguments.contains("-PinbookPreserveLanguage") {
                PinbookLanguage.preferenceStore.removeObject(forKey: PinbookLanguage.preferenceKey)
            }
            if let index = arguments.firstIndex(of: "-PinbookLanguage"),
               arguments.indices.contains(index + 1),
               let language = PinbookLanguage(rawValue: arguments[index + 1]) {
                PinbookLanguage.preferenceStore.set(language.rawValue, forKey: PinbookLanguage.preferenceKey)
            }
        }
#endif
        let schema = Schema(PinbookSchema.models)
        let configuration: ModelConfiguration
#if DEBUG
        if launchConfiguration.usesEphemeralStore {
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
