// App/WharfsideApp.swift

import SwiftUI

@main
struct WharfsideApp: App {
    @State private var appState = AppState(
        systemService: XPCSystemService(),
        containerService: XPCContainerService()
    )
    @State private var aiAvailability = AIAvailabilityService()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .environment(aiAvailability)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
