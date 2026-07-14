// App/WharfsideApp.swift

import SwiftUI

@main
struct WharfsideApp: App {
#if DEBUG
    private let launchArgs: LaunchAssetArguments
    @NSApplicationDelegateAdaptor(LaunchAssetAppDelegate.self) private var appDelegate
#endif

    @State private var appState: AppState
    @State private var aiAvailability: AIAvailabilityService
#if DEBUG
    @State private var poseController: LaunchAssetPoseController?
#endif

    init() {
#if DEBUG
        let args = LaunchAssetArguments.parse()
        self.launchArgs = args
        // Snapshot / pose modes start from LaunchAssetAppDelegate after NSApp is ready.
        LaunchAssetBootstrap.arguments = args
        if args.usesFixtures {
            let fixture = FixtureAppState.make(fixtureName: args.fixtureName)
            _appState = State(initialValue: fixture.appState)
            _aiAvailability = State(initialValue: fixture.aiAvailability)
            if case .pose = args.mode {
                let controller = LaunchAssetPoseController(fixtureName: args.fixtureName)
                LaunchAssetBootstrap.poseController = controller
                LaunchAssetBootstrap.poseAppState = fixture.appState
                LaunchAssetBootstrap.poseAIAvailability = fixture.aiAvailability
                _poseController = State(initialValue: controller)
            }
        } else {
            _appState = State(
                initialValue: AppState(
                    systemService: XPCSystemService(),
                    containerService: XPCContainerService(),
                    imageService: XPCImageService(),
                    registryService: CLIRegistryService()
                )
            )
            _aiAvailability = State(initialValue: AIAvailabilityService())
        }
#else
        _appState = State(
            initialValue: AppState(
                systemService: XPCSystemService(),
                containerService: XPCContainerService(),
                imageService: XPCImageService(),
                registryService: CLIRegistryService()
            )
        )
        _aiAvailability = State(initialValue: AIAvailabilityService())
#endif
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            launchRoot
#else
            MainView()
                .environment(appState)
                .environment(aiAvailability)
                .frame(minWidth: 900, minHeight: 600)
#endif
        }
        .defaultSize(width: 1_000, height: 700)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsPlaceholderView()
        }
    }

#if DEBUG
    @ViewBuilder
    private var launchRoot: some View {
        switch launchArgs.mode {
        case .normal:
            MainView()
                .environment(appState)
                .environment(aiAvailability)
                .frame(minWidth: 900, minHeight: 600)
        case .snapshot:
            // Snapshot work starts from LaunchAssetAppDelegate — keep a tiny host view alive.
            Color.clear.frame(width: 1, height: 1)
        case .pose:
            // Real UI is hosted in an explicit NSWindow (see LaunchAssetBootstrap.openPoseWindow).
            // Keep WindowGroup alive with a 1×1 host so the App lifecycle stays valid.
            Color.clear.frame(width: 1, height: 1)
        }
    }
#endif
}
