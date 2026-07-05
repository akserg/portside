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
        }
        .navigationTitle(appState.selectedSection.rawValue)
        .toolbar {
            ToolbarItem(placement: .status) {
                ServiceStatusIndicator(isRunning: appState.isServiceRunning)
            }
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
            #if DEBUG
            DebugContainerList(service: appState.containerService)
            #else
            PlaceholderView(
                section: section,
                message: "Container list is issue #8 — the first real view."
            )
            #endif
        case .images:
            PlaceholderView(
                section: section,
                message: "Image management is issue #10."
            )
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
        Label(
            isRunning ? "Service running" : "Service stopped",
            systemImage: "circle.fill"
        )
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(isRunning ? .green : .red)
        .help(isRunning
              ? "container-apiserver is reachable"
              : "Start with: container system start")
    }
}

#Preview {
    MainView()
        .environment(AppState(
            systemService: XPCSystemService(),
            containerService: XPCContainerService()
        ))
        .environment(AIAvailabilityService())
}
