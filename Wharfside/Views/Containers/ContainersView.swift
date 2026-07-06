// Views/Containers/ContainersView.swift

import SwiftUI

struct ContainersView: View {
    @State private var viewModel: ContainerListViewModel
    @FocusState private var isSearchFocused: Bool

    init(service: any ContainerServicing) {
        _viewModel = State(initialValue: ContainerListViewModel(service: service))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if let error = viewModel.listError {
                serviceErrorView(error)
            } else if viewModel.filteredContainers.isEmpty && !viewModel.isInitialLoading {
                emptyStateView
            } else {
                containerList
            }
        }
        .navigationTitle("Containers")
        .searchable(text: $viewModel.searchText, prompt: "Search containers…")
        .focused($isSearchFocused)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.actionBannerMessage {
                ActionErrorBanner(message: message)
            }
        }
        .confirmationDialog(
            viewModel.pendingConfirmation.map { viewModel.confirmationTitle(for: $0) } ?? "",
            isPresented: Binding(
                get: { viewModel.pendingConfirmation != nil },
                set: { if !$0 { viewModel.pendingConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = viewModel.pendingConfirmation {
                Button(viewModel.destructiveConfirmationLabel(for: action), role: .destructive) {
                    let confirmed = action
                    Task { await viewModel.confirm(confirmed) }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelPendingAction()
                }
            }
        } message: {
            if let action = viewModel.pendingConfirmation {
                Text(viewModel.confirmationMessage(for: action))
            }
        }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .onDeleteCommand(perform: deleteSelectedContainer)
        .onKeyPress(.space) {
            viewModel.toggleSelectedContainer()
            return .handled
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var containerList: some View {
        List(viewModel.filteredContainers, selection: $viewModel.selectedContainerID) { container in
            ContainerRowView(
                container: container,
                isPerformingAction: viewModel.actionInProgressIDs.contains(container.id),
                onStart: { viewModel.requestStart(id: container.id) },
                onStop: { viewModel.requestStop(id: container.id) },
                onKill: { viewModel.requestKill(id: container.id) },
                onDelete: { viewModel.requestDelete(id: container.id) }
            )
            .tag(container.id)
        }
        .overlay {
            if viewModel.isInitialLoading && viewModel.containers.isEmpty {
                ProgressView()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No containers", systemImage: "shippingbox")
        } description: {
            if viewModel.searchText.isEmpty && viewModel.statusFilter == .all {
                Text("Create one with: container run --name hello alpine sleep 600")
                    .font(.callout.monospaced())
            } else {
                Text("No containers match the current search or filter.")
            }
        }
    }

    @ViewBuilder
    private func serviceErrorView(_ error: WharfsideError) -> some View {
        ContentUnavailableView {
            Label("Couldn't load containers", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                if error == .serviceNotRunning {
                    Text("Start with: container system start")
                        .font(.callout.monospaced())
                }
            }
        } actions: {
            Button("Retry") { Task { await viewModel.refresh() } }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Picker("Status", selection: $viewModel.statusFilter) {
                ForEach(ContainerStatusFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh container list")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private func deleteSelectedContainer() {
        guard let id = viewModel.selectedContainerID else { return }
        viewModel.requestDelete(id: id)
    }
}

// MARK: - Row

private struct ContainerRowView: View {
    let container: ContainerSummary
    let isPerformingAction: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onKill: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .font(.body)
                    .lineLimit(1)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(ContainerSummaryFormatting.uptimeOrExitSummary(
                status: container.status,
                startedAt: container.startedAt
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .trailing)

            Text(container.portSummary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
                .lineLimit(1)

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 48)
            } else {
                rowActions
                    .frame(minWidth: 48, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { actionButtons }
    }

    private var statusDot: some View {
        Circle()
            .fill(container.status == .running ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .accessibilityLabel(container.status == .running ? "Running" : "Stopped")
    }

    private var rowActions: some View {
        HStack(spacing: 6) {
            primaryActionButton
            overflowMenu
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if container.status == .stopped {
            actionButton("Start", systemImage: "play.fill", action: onStart)
        } else if container.status == .running || container.status == .stopping {
            actionButton("Stop", systemImage: "stop.fill", action: onStop)
        }
    }

    private var overflowMenu: some View {
        Menu {
            overflowMenuButtons
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More actions")
    }

    @ViewBuilder
    private var overflowMenuButtons: some View {
        if container.status == .running || container.status == .stopping {
            Button("Kill", systemImage: "bolt.fill", action: onKill)
        }
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if container.status == .stopped {
            Button("Start", systemImage: "play.fill", action: onStart)
        }
        if container.status == .running || container.status == .stopping {
            Button("Stop", systemImage: "stop.fill", action: onStop)
            Button("Kill", systemImage: "bolt.fill", action: onKill)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .help(title)
    }
}

// MARK: - Banner

private struct ActionErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}

#Preview {
    ContainersView(service: MockContainerService())
        .frame(width: 900, height: 500)
}

#if DEBUG
private struct MockContainerService: ContainerServicing {
    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail { fatalError() }
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
