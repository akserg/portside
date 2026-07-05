// Views/Containers/DebugContainerList.swift
// M0 exit criteria: "lists real containers in a debug view."
// Deliberately throwaway — replaced by the real ContainersView in issue #8 (M1.1).
// DEBUG-only so it can't leak into a release build.

#if DEBUG
import SwiftUI

struct DebugContainerList: View {
    let service: any ContainerServicing

    @State private var containers: [ContainerSummary] = []
    @State private var error: WharfsideError?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView {
                    Label("Couldn't load containers", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if containers.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No containers", systemImage: "shippingbox")
                } description: {
                    Text("Create one with: container run --name hello alpine sleep 600")
                        .font(.callout.monospaced())
                }
            } else {
                List(containers) { container in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(container.status == .running ? .green : .red)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(container.id).font(.body.monospaced())
                            Text(container.image)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(container.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("DEBUG list — real view is issue #8")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            containers = try await service.list()
            error = nil
        } catch let mapped as WharfsideError {
            error = mapped
        } catch let caught {
            error = ErrorMapper.map(caught)
        }
    }
}
#endif
