// App/WharfsideApp.swift

import SwiftUI

@main
struct WharfsideApp: App {
    @State private var appState = AppState(systemService: XPCSystemService())

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
