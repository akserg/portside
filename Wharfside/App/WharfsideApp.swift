// App/WharfsideApp.swift

import SwiftUI

@main
struct WharfsideApp: App {
    @State private var appState = AppState(
        systemService: XPCSystemService(),
        containerService: XPCContainerService(),
        imageService: XPCImageService(),
        registryService: CLIRegistryService()
    )
    @State private var aiAvailability = AIAvailabilityService()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .environment(aiAvailability)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_000, height: 700)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
