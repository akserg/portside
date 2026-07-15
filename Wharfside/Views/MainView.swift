// Views/MainView.swift

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(AIAvailabilityService.self) private var availability
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState

        // One NavigationSplitView only (enforced by `make purity`). Column mins:
        // I-UI-2 — sidebar(190) + list(260) + detail(440) ≈ 890 < 1100 window floor.
        // The system collapses sidebar then content via dividers/toolbar; no nested split.
        NavigationSplitView {
            Sidebar(selection: $appState.selectedSection)
        } content: {
            contentColumn(for: appState.selectedSection)
                .navigationSplitViewColumnWidth(
                    min: ContainerListMetrics.listMinWidth,
                    ideal: ContainerListMetrics.listIdealWidth,
                    max: ContainerListMetrics.listMaxWidth
                )
        } detail: {
            detailColumn(for: appState.selectedSection)
                .navigationSplitViewColumnWidth(min: 440, ideal: 640)
        }
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
    private func contentColumn(for section: NavigationSection) -> some View {
        switch section {
        case .containers:
            ContainersView()
        case .images:
            ImagesView(
                imageService: appState.imageService,
                registryService: appState.registryService
            )
        case .dashboard, .volumes, .machines:
            // Single-pane sections put their placeholder in the wide detail column; the
            // content column stays empty until these gain a real list in 0.2.
            Color(nsColor: .windowBackgroundColor)
        }
    }

    @ViewBuilder
    private func detailColumn(for section: NavigationSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.isPreOnePointZeroDaemon {
                PreOnePointZeroDaemonBanner()
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            // Real content aligns top-leading; placeholder/empty states center themselves
            // (each applies a filling frame below), so nothing shrinks toward the middle.
            sectionDetail(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func sectionDetail(for section: NavigationSection) -> some View {
        @Bindable var appState = appState

        switch section {
        case .containers:
            if let selectedID = appState.containerList.selectedContainerID {
                ContainerDetailView(
                    containerID: selectedID,
                    service: appState.containerService,
                    lifecycleObserver: appState.lifecycleObserver,
                    availability: availability,
                    exitStatusBackfill: appState.exitStatusBackfill,
                    reportEnvironmentProvider: { appState.diagnosisReportEnvironment },
                    onBackToList: { appState.containerList.selectedContainerID = nil }
                )
                .id(selectedID)
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "shippingbox")
                } description: {
                    Text("Select a container to inspect its configuration.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .images:
            ContentUnavailableView {
                Label("Images", systemImage: section.systemImage)
            } description: {
                Text("Select an image from the list to see its details.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .dashboard:
            PlaceholderView(
                section: section,
                message: "System overview and resource charts arrive in 0.2."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .volumes:
            PlaceholderView(
                section: section,
                message: "Volumes arrive in 0.2."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .machines:
            PlaceholderView(
                section: section,
                message: "Machine management arrives in 0.2."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
