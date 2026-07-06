// Views/Containers/ContainerDetailView.swift

import AppKit
import SwiftUI

struct ContainerDetailView: View {
    @State private var viewModel: ContainerDetailViewModel
    private let service: any ContainerServicing
    let onBackToList: () -> Void

    init(containerID: String, service: any ContainerServicing, onBackToList: @escaping () -> Void) {
        self.service = service
        _viewModel = State(
            initialValue: ContainerDetailViewModel(containerID: containerID, service: service)
        )
        self.onBackToList = onBackToList
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isGone {
                goneStateView
            } else if viewModel.isInitialLoading && viewModel.detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.detail {
                detailContent(detail)
            } else {
                ContentUnavailableView("Couldn't load container", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(viewModel.containerID)
        .toolbar { toolbarContent(for: viewModel.detail) }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.actions.actionBannerMessage {
                ActionErrorBanner(message: message)
            }
        }
        .confirmationDialog(
            viewModel.actions.pendingConfirmation.map { viewModel.actions.confirmationTitle(for: $0) } ?? "",
            isPresented: Binding(
                get: { viewModel.actions.pendingConfirmation != nil },
                set: { if !$0 { viewModel.actions.cancelPendingAction() } }
            ),
            titleVisibility: .visible
        ) {
            if let action = viewModel.actions.pendingConfirmation {
                Button(viewModel.actions.destructiveConfirmationLabel(for: action), role: .destructive) {
                    let confirmed = action
                    Task { await viewModel.actions.confirm(confirmed) }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.actions.cancelPendingAction()
                }
            }
        } message: {
            if let action = viewModel.actions.pendingConfirmation {
                Text(viewModel.actions.confirmationMessage(for: action))
            }
        }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    @ViewBuilder
    private func detailContent(_ detail: ContainerDetail) -> some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 0) {
            Picker("Section", selection: $viewModel.selectedTab) {
                ForEach(ContainerDetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            tabContent(for: detail, tab: viewModel.selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func tabContent(for detail: ContainerDetail, tab: ContainerDetailTab) -> some View {
        if tab == .logs {
            LogView(
                containerID: detail.id,
                service: service,
                containerStatus: detail.status
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .overview:
                        overviewSection(detail)
                    case .ports:
                        portsSection(detail.ports)
                    case .mounts:
                        mountsSection(detail.mounts)
                    case .environment:
                        environmentSection(detail.environment)
                    case .networks:
                        networksSection(detail.networks)
                    case .logs:
                        EmptyView()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var goneStateView: some View {
        ContentUnavailableView {
            Label("This container no longer exists", systemImage: "shippingbox")
        } description: {
            Text("It may have been removed outside Wharfside.")
        } actions: {
            Button("Back to List") {
                onBackToList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func overviewSection(_ detail: ContainerDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CopyableValueView(label: "ID", value: detail.id)
            CopyableValueView(label: "Image", value: detail.image)
            CopyableValueView(label: "Status", value: viewModel.displayStatusLabel(for: detail), monospaced: false)
            CopyableValueView(label: "Created", value: formattedDate(detail.createdAt), monospaced: false)
            if let startedAt = detail.startedAt {
                CopyableValueView(label: "Started", value: formattedDate(startedAt), monospaced: false)
            }
            CopyableValueView(
                label: "Exit code",
                value: detail.exitCode.map(String.init) ?? "—",
                monospaced: false
            )
            CopyableValueView(
                label: "Restart count",
                value: String(detail.restartCount),
                monospaced: false
            )
        }
    }

    private func portsSection(_ ports: [ContainerPortBinding]) -> some View {
        sectionWithNoneFallback(ports.isEmpty) {
            ForEach(ports) { port in
                CopyableRowView(value: port.displayBinding)
                if port.id != ports.last?.id {
                    Divider()
                }
            }
        }
    }

    private func mountsSection(_ mounts: [ContainerMount]) -> some View {
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

    private func environmentSection(_ variables: [ContainerEnvironmentVariable]) -> some View {
        sectionWithNoneFallback(variables.isEmpty) {
            ForEach(variables) { variable in
                environmentRow(variable)
                if variable.id != variables.last?.id {
                    Divider()
                }
            }
        }
    }

    private func environmentRow(_ variable: ContainerEnvironmentVariable) -> some View {
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

    private func networksSection(_ networks: [ContainerNetworkAttachment]) -> some View {
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
    private func sectionWithNoneFallback<Content: View>(
        _ isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isEmpty {
            CopyableRowView(value: "None")
        } else {
            content()
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for detail: ContainerDetail?) -> some ToolbarContent {
        if let detail {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.actions.actionInProgressIDs.contains(detail.id) {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 36, height: 32)
                        .padding(.horizontal, 6)
                } else {
                    lifecycleButtons(for: detail)
                }
            }
        }
    }

    @ViewBuilder
    private func lifecycleButtons(for detail: ContainerDetail) -> some View {
        switch detail.status {
        case .stopped:
            Button("Start", systemImage: "play.fill") {
                viewModel.actions.requestStart(id: detail.id)
            }
        case .running, .stopping:
            Button("Stop", systemImage: "stop.fill") {
                viewModel.actions.requestStop(id: detail.id)
            }
            Button("Kill", systemImage: "bolt.fill") {
                viewModel.actions.requestKill(id: detail.id)
            }
        case .unknown:
            EmptyView()
        }

        Button("Delete", systemImage: "trash", role: .destructive) {
            viewModel.actions.requestDelete(id: detail.id)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func copyToClipboard(_ text: String) {
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

#Preview {
    ContainerDetailView(containerID: "hello", service: MockContainerService()) {}
        .frame(width: 480, height: 520)
}

#if DEBUG
private struct MockContainerService: ContainerServicing {
    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail {
        ContainerDetail(
            id: id,
            image: "alpine:latest",
            status: .running,
            command: ["/bin/sleep", "600"],
            createdAt: .now,
            startedAt: .now,
            exitCode: nil,
            restartCount: 0,
            ports: [ContainerPortBinding(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 80, proto: "tcp")],
            mounts: [],
            environment: [ContainerEnvironmentVariable(key: "SECRET", value: "hunter2")],
            networks: []
        )
    }
    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}
    func stats(id: String) async throws -> ContainerStats { fatalError() }
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
}
#endif
