// Views/Containers/ContainersView.swift

import SwiftUI
import WharfsideAnalysis

enum ContainerListMetrics {
    /// Content-column widths. With sidebar(190) + detail(440) → ≈890 < 1100 (I-UI-2).
    static let listMinWidth: CGFloat = 260
    static let listIdealWidth: CGFloat = 320
    static let listMaxWidth: CGFloat = 480
    static let topContentInset: CGFloat = 16
}

/// The container list — the `content` column of the app's single NavigationSplitView.
/// Selection lives in `AppState.containerList`, so the detail column (a sibling column,
/// not a nested split) renders the chosen container.
struct ContainersView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isSearchFocused: Bool

    private var viewModel: ContainerListViewModel { appState.containerList }

    var body: some View {
        @Bindable var viewModel = appState.containerList

        listColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .searchable(text: $viewModel.searchText, prompt: "Search containers…")
            .focused($isSearchFocused)
            .navigationTitle("Containers")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = viewModel.actions.actionBannerMessage {
                    ActionErrorBanner(message: message)
                }
            }
            .confirmationDialog(
                viewModel.actions.pendingConfirmation.map { viewModel.confirmationTitle(for: $0) } ?? "",
                isPresented: Binding(
                    get: { viewModel.actions.pendingConfirmation != nil },
                    set: { if !$0 { viewModel.cancelPendingAction() } }
                ),
                titleVisibility: .visible
            ) {
                if let action = viewModel.actions.pendingConfirmation {
                    Button(viewModel.destructiveConfirmationLabel(for: action), role: .destructive) {
                        let confirmed = action
                        Task { await viewModel.confirm(confirmed) }
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelPendingAction()
                    }
                }
            } message: {
                if let action = viewModel.actions.pendingConfirmation {
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

    @ViewBuilder
    private var listColumn: some View {
        Group {
            if let error = viewModel.listError {
                serviceErrorView(error)
            } else if viewModel.filteredContainers.isEmpty && !viewModel.isInitialLoading {
                emptyStateView
            } else {
                containerList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var containerList: some View {
        @Bindable var viewModel = appState.containerList

        return VStack(spacing: 0) {
            Spacer()
                .frame(height: ContainerListMetrics.topContentInset)
            List(viewModel.filteredContainers, selection: $viewModel.selectedContainerID) { container in
                ContainerRowView(
                    container: container,
                    isPerformingAction: viewModel.actions.actionInProgressIDs.contains(container.id),
                    onStart: { viewModel.requestStart(id: container.id) },
                    onStop: { viewModel.requestStop(id: container.id) },
                    onKill: { viewModel.requestKill(id: container.id) },
                    onDelete: { viewModel.requestDelete(id: container.id) }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowSeparator(.hidden)
                .tag(container.id)
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Picker("Status", selection: Binding(
                get: { appState.containerList.statusFilter },
                set: { appState.containerList.statusFilter = $0 }
            )) {
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
        HStack(spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .font(.body)
                    .lineLimit(1)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if isPerformingAction {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 32, height: 28)
            } else {
                primaryActionButton
            }
        }
        .padding(.vertical, 6)
        .contextMenu { actionButtons }
    }

    private var statusDot: some View {
        Circle()
            .fill(container.status == .running ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .accessibilityLabel(container.status == .running ? "Running" : "Stopped")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if container.status == .stopped {
            actionButton("Start", systemImage: "play.fill", action: onStart)
        } else if container.status == .running || container.status == .stopping {
            actionButton("Stop", systemImage: "stop.fill", action: onStop)
        }
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

#if DEBUG
#Preview {
    ContainersView()
        .environment(AppState(
            systemService: XPCSystemService(),
            containerService: MockContainerService(),
            imageService: XPCImageService(),
            registryService: CLIRegistryService()
        ))
        .environment(AIAvailabilityService())
        .frame(width: 360, height: 500)
}

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
    func exitStatus(id: String) async -> ExitStatus { .unavailable(reason: .noEvidence) }
}
#endif
