// Views/MainView.swift

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(AIAvailabilityService.self) private var availability
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            Sidebar(selection: $appState.selectedSection)
        } detail: {
            detailView(for: appState.selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(appState.selectedSection.rawValue)
        .toolbar {
            ToolbarItem(placement: .status) {
                ServiceStatusIndicator(isRunning: appState.isServiceRunning)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task {
            availability.refresh()
            while !Task.isCancelled {
                await appState.refreshServiceStatus()
                if availability.sawModelDownloading && !availability.capability.isAIAvailable {
                    availability.refresh()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availability.refresh() }
        }
    }

    @ViewBuilder
    private func detailView(for section: NavigationSection) -> some View {
        switch section {
        case .dashboard:
            PlaceholderView(
                section: section,
                message: "System overview and resource charts arrive in 0.2."
            )
        case .containers:
            ContainersView(service: appState.containerService)
                .id(NavigationSection.containers)
        case .images:
            ImagesView(
                imageService: appState.imageService,
                registryService: appState.registryService
            )
            .id(NavigationSection.images)
        case .volumes:
            PlaceholderView(
                section: section,
                message: "Volumes arrive in 0.2."
            )
        case .machines:
            PlaceholderView(
                section: section,
                message: "Machine management arrives in 0.2."
            )
        }
    }
}

/// Traffic-light dot for daemon health; wired to real polling in M0.4.
struct ServiceStatusIndicator: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(isRunning ? "Service running" : "Service stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .help(isRunning
              ? "container-apiserver is reachable"
              : "Start with: container system start")
    }
}

#Preview {
    MainView()
        .environment(AppState(
            systemService: XPCSystemService(),
            containerService: XPCContainerService(),
            imageService: XPCImageService(),
            registryService: CLIRegistryService()
        ))
        .environment(AIAvailabilityService())
}
