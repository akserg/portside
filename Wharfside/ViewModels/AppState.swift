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

    /// Populated by SystemServicing.health() polling (M0.4/M0.5 wiring).
    var isServiceRunning: Bool = false
}
