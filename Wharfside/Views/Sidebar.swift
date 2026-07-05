// Views/Sidebar.swift

import SwiftUI

struct Sidebar: View {
    @Binding var selection: NavigationSection

    var body: some View {
        List(NavigationSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.rawValue, systemImage: section.systemImage)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
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
        .frame(width: 220, height: 400)
}
