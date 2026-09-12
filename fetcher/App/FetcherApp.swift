import SwiftData
import SwiftUI

@main
struct FetcherApp: App {
    @State private var commandCenter = AppCommandCenter()
    @State private var workspace = RequestWorkspaceModel()
    private let secretStore: any SecretStore = KeychainSecretStore()

    private let container = PersistenceController.sharedModelContainer

    var body: some Scene {
        WindowGroup {
            ContentRootView(
                commandCenter: commandCenter,
                workspace: workspace,
                secretStore: secretStore
            )
            .modelContainer(container)
            .onAppear {
                commandCenter.workspace = workspace
            }
        }
        .commands {
            AppCommands(commandCenter: commandCenter)
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            AppSettingsView()
        }
    }
}
