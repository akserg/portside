// Views/MainView.swift

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

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
            while !Task.isCancelled {
                await appState.refreshServiceStatus()
                try? await Task.sleep(for: .seconds(5))
            }
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
            PlaceholderView(
                section: section,
                message: "Container list is issue #8 — the first real view."
            )
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
    MainView().environment(AppState(systemService: XPCSystemService()))
}
