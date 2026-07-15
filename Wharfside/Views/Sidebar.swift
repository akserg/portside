// Views/Sidebar.swift

import SwiftUI

private enum SidebarMetrics {
    /// Labels never clip at this min. I-UI-2: 190 + list(260) + detail(440) ≈ 890 < 1100.
    static let minWidth: CGFloat = 190
    static let idealWidth: CGFloat = 210
    static let maxWidth: CGFloat = 260
}

struct Sidebar: View {
    @Binding var selection: NavigationSection

    var body: some View {
        List(NavigationSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.rawValue, systemImage: section.systemImage)
                    .lineLimit(1)
            }
        }
        .navigationSplitViewColumnWidth(
            min: SidebarMetrics.minWidth,
            ideal: SidebarMetrics.idealWidth,
            max: SidebarMetrics.maxWidth
        )
        .listStyle(.sidebar)
    }
}

// Views/Shared/PlaceholderView.swift

/// Empty-state placeholder used until each section's real view lands.
struct PlaceholderView: View {
    let section: NavigationSection
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(section.rawValue, systemImage: section.systemImage)
        } description: {
            Text(message)
        }
    }
}

// Views/Settings/SettingsPlaceholderView.swift

struct SettingsPlaceholderView: View {
    var body: some View {
        Form {
            Text("Settings arrive with the preferences service.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
    }
}

#Preview {
    Sidebar(selection: .constant(.containers))
        .frame(width: SidebarMetrics.idealWidth, height: 400)
}
