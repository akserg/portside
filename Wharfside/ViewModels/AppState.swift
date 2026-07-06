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

    let systemService: any SystemServicing
    let containerService: any ContainerServicing
    let imageService: any ImageServicing
    let registryService: any RegistryServicing

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

    func refreshServiceStatus() async {
        do {
            _ = try await systemService.health()
            isServiceRunning = true
        } catch {
            isServiceRunning = false
        }
    }
}
