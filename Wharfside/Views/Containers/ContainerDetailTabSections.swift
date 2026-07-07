// Views/Containers/ContainerDetailTabSections.swift
// Issue 1.2 / 1.7 — read-only detail tab section content.

import AppKit
import SwiftUI

enum ContainerDetailTabSections {
    @ViewBuilder
    static func ports(_ ports: [ContainerPortBinding]) -> some View {
        sectionWithNoneFallback(ports.isEmpty) {
            ForEach(ports) { port in
                CopyableRowView(value: port.displayBinding)
                if port.id != ports.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    static func mounts(_ mounts: [ContainerMount]) -> some View {
        sectionWithNoneFallback(mounts.isEmpty) {
            ForEach(mounts) { mount in
                VStack(alignment: .leading, spacing: 4) {
                    CopyableValueView(label: "Destination", value: mount.destination)
                    CopyableValueView(label: "Source", value: mount.source.isEmpty ? "—" : mount.source)
                    CopyableValueView(label: "Type", value: mount.type, monospaced: false)
                    CopyableValueView(
                        label: "Access",
                        value: mount.readOnly ? "read-only" : "read-write",
                        monospaced: false
                    )
                }
                .padding(.vertical, 4)
                if mount.id != mounts.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    static func environment(
        _ variables: [ContainerEnvironmentVariable],
        viewModel: ContainerDetailViewModel
    ) -> some View {
        sectionWithNoneFallback(variables.isEmpty) {
            ForEach(variables) { variable in
                environmentRow(variable, viewModel: viewModel)
                if variable.id != variables.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    static func networks(_ networks: [ContainerNetworkAttachment]) -> some View {
        sectionWithNoneFallback(networks.isEmpty) {
            ForEach(networks) { network in
                VStack(alignment: .leading, spacing: 0) {
                    CopyableValueView(label: "Network", value: network.network)
                    CopyableValueView(label: "Hostname", value: network.hostname)
                    CopyableValueView(label: "IPv4", value: network.ipv4Address)
                    CopyableValueView(label: "Gateway", value: network.ipv4Gateway)
                    if let ipv6 = network.ipv6Address {
                        CopyableValueView(label: "IPv6", value: ipv6)
                    }
                }
                .padding(.vertical, 4)
                if network.id != networks.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private static func sectionWithNoneFallback<Content: View>(
        _ isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isEmpty {
            CopyableRowView(value: "None")
        } else {
            content()
        }
    }

    private static func environmentRow(
        _ variable: ContainerEnvironmentVariable,
        viewModel: ContainerDetailViewModel
    ) -> some View {
        let revealed = viewModel.isEnvironmentValueRevealed(key: variable.key)
        let displayValue = revealed
            ? viewModel.environmentValue(for: variable)
            : viewModel.maskedEnvironmentValue(for: variable)

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(variable.key)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayValue)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)

                Button {
                    viewModel.toggleEnvironmentReveal(key: variable.key)
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealed ? "Hide value" : "Reveal value")

                EnvironmentCopyButton(value: viewModel.environmentValue(for: variable))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Value") {
                copyToClipboard(viewModel.environmentValue(for: variable))
            }
        }
    }

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct EnvironmentCopyButton: View {
    let value: String

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}
