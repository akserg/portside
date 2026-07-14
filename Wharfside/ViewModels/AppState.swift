// ViewModels/AppState.swift

import SwiftUI
import Observation

/// Top-level navigation sections. Builds is deferred past 0.3 (CLI-only in
/// runtime 1.0 — see SPECIFICATION.md §3.6) and intentionally absent.
enum NavigationSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case containers = "Containers"
    case images = "Images"
    case volumes = "Volumes"
    case machines = "Machines"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard:  "gauge.with.dots.needle.50percent"
        case .containers: "shippingbox"
        case .images:     "square.stack.3d.down.right"
        case .volumes:    "externaldrive"
        case .machines:   "server.rack"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selectedSection: NavigationSection = .containers

    /// Updated by `SystemServicing.health()` polling from `MainView`.
    var isServiceRunning = false

    /// Last successful health check, cached for surfaces (e.g. the diagnosis report) that
    /// need a runtime version without making their own blocking call (Issue 1.11).
    private(set) var cachedHealth: SystemHealth?

    let systemService: any SystemServicing
    let containerService: any ContainerServicing
    let imageService: any ImageServicing
    let registryService: any RegistryServicing
    /// App-derived restart counts from container list polling (issue 1.6).
    let lifecycleObserver = ContainerLifecycleObserver()

    init(
        systemService: any SystemServicing,
        containerService: any ContainerServicing,
        imageService: any ImageServicing,
        registryService: any RegistryServicing
    ) {
        self.systemService = systemService
        self.containerService = containerService
        self.imageService = imageService
        self.registryService = registryService
    }

#if DEBUG
    /// Seeds cached health for fixture / launch-asset modes (no live daemon).
    func seedCachedHealth(_ health: SystemHealth) {
        cachedHealth = health
        isServiceRunning = true
    }
#endif

    func refreshServiceStatus() async {
        do {
            cachedHealth = try await systemService.health()
            isServiceRunning = true
        } catch {
            isServiceRunning = false
        }
    }

    /// Builds report metadata from whatever is already cached — never blocks the copy path
    /// with a fresh health call (Issue 1.11).
    var diagnosisReportEnvironment: DiagnosisReportEnvironment {
        .current(
            runtimeVersion: cachedHealth?.apiServerVersion,
            runtimeCommit: cachedHealth?.apiServerCommit
        )
    }

    /// True when the connected apiserver predates the 1.0 semver line (exit-status surface differs).
    var isPreOnePointZeroDaemon: Bool {
        DaemonVersionPolicy.isPreOnePointZero(apiServerVersion: cachedHealth?.apiServerVersion)
    }
}
