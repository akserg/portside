// Views/Images/ImagesView.swift

import SwiftUI

private enum ImageListMetrics {
    static let topContentInset: CGFloat = 16
}

struct ImagesView: View {
    @State private var viewModel: ImageListViewModel
    @State private var isPullSheetPresented = false
    @State private var isRegistrySheetPresented = false
    @State private var tagTarget: TagSheetTarget?
    @FocusState private var isSearchFocused: Bool

    private let registryService: any RegistryServicing

    init(imageService: any ImageServicing, registryService: any RegistryServicing) {
        self.registryService = registryService
        _viewModel = State(initialValue: ImageListViewModel(service: imageService))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            listContent
                .searchable(text: $viewModel.searchText, prompt: "Search images…")
                .focused($isSearchFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Images")
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.bannerMessage {
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
        .sheet(isPresented: $isPullSheetPresented) {
            PullImageSheet(
                pulls: viewModel.pulls,
                onPull: { reference in
                    viewModel.startPull(reference: reference)
                }
            )
        }
        .sheet(isPresented: $isRegistrySheetPresented) {
            RegistrySheet(service: registryService)
        }
        .sheet(item: $tagTarget) { target in
            TagImageSheet(
                sourceReference: target.reference,
                onTag: { newReference in
                    do {
                        try await viewModel.tag(source: target.reference, target: newReference)
                    } catch {
                        viewModel.actions.presentTransientBanner(ErrorMapper.map(error).localizedDescription)
                    }
                }
            )
        }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .onDeleteCommand(perform: deleteSelectedImage)
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    @ViewBuilder
    private var listContent: some View {
        Group {
            if let error = viewModel.listError {
                serviceErrorView(error)
            } else if viewModel.filteredImages.isEmpty
                && viewModel.pulls.activePulls.isEmpty
                && !viewModel.isInitialLoading {
                emptyStateView
            } else {
                imageList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var imageList: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ImageListMetrics.topContentInset)
            List(selection: $viewModel.selectedImageReference) {
                ForEach(viewModel.pulls.activePulls) { pull in
                    PullProgressRow(pull: pull)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowSeparator(.hidden)
                }

                ForEach(viewModel.filteredImages) { image in
                    ImageRowView(
                        image: image,
                        isPerformingAction: viewModel.actions.actionInProgressReferences.contains(image.reference),
                        onTag: { tagTarget = TagSheetTarget(reference: image.reference) },
                        onDelete: { viewModel.requestDelete(reference: image.reference) }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowSeparator(.hidden)
                    .tag(image.reference)
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if viewModel.isInitialLoading && viewModel.images.isEmpty && viewModel.pulls.activePulls.isEmpty {
                ProgressView()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No images", systemImage: "square.stack.3d.down.right")
        } description: {
            if viewModel.searchText.isEmpty {
                Text("Pull one with Pull Image… or from the terminal: container image pull alpine")
                    .font(.callout.monospaced())
            } else {
                Text("No images match the current search.")
            }
        }
    }

    @ViewBuilder
    private func serviceErrorView(_ error: WharfsideError) -> some View {
        ContentUnavailableView {
            Label("Couldn't load images", systemImage: "exclamationmark.triangle")
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
        ToolbarItem(placement: .primaryAction) {
            Button {
                isRegistrySheetPresented = true
            } label: {
                Label("Registries…", systemImage: "key")
            }
            .help("Manage registry logins")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                isPullSheetPresented = true
            } label: {
                Label("Pull Image…", systemImage: "arrow.down.circle")
            }
            .help("Pull an image from a registry")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh image list")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private func deleteSelectedImage() {
        guard let reference = viewModel.selectedImageReference else { return }
        viewModel.requestDelete(reference: reference)
    }
}

// MARK: - Rows

private struct ImageRowView: View {
    let image: ImageSummary
    let isPerformingAction: Bool
    let onTag: () -> Void
    let onDelete: () -> Void

    private var displayReference: String {
        ImageSummaryFormatting.displayReference(image.reference)
    }

    private var isUntagged: Bool {
        ImageSummaryFormatting.isUntagged(image.reference)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayReference)
                    .font(.body.monospaced())
                    .foregroundStyle(isUntagged ? .secondary : .primary)
                    .lineLimit(1)
                Text(ImageSummaryFormatting.shortDigest(image.digest))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, alignment: .leading)
            .layoutPriority(1)

            Text(ImageSummaryFormatting.formattedSize(image.sizeBytes))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(ImageSummaryFormatting.relativeCreated(image.createdAt))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            if isPerformingAction {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 32, height: 28)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Tag…", systemImage: "tag", action: onTag)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

private struct PullProgressRow: View {
    let pull: PullTaskCoordinator.ActivePull

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                if let fraction = PullProgressFormatting.progressFraction(pull.progress) {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                        .frame(width: 32)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pulling \(pull.reference)")
                        .font(.body.monospaced())
                        .lineLimit(1)
                    Text(PullProgressFormatting.statusLabel(
                        progress: pull.progress,
                        startedAt: pull.startedAt,
                        now: context.date
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pulling \(pull.reference)")
        }
    }
}

private struct TagSheetTarget: Identifiable {
    let reference: String
    var id: String { reference }
}

#Preview {
    ImagesView(imageService: PreviewImageService(), registryService: PreviewRegistryService())
        .frame(width: 900, height: 500)
}

#if DEBUG
private struct PreviewImageService: ImageServicing {
    func list() async throws -> [ImageSummary] {
        [
            ImageSummary(
                reference: "alpine:latest",
                digest: "sha256:abcdef1234567890",
                sizeBytes: 8_388_608,
                createdAt: Date().addingTimeInterval(-86_400 * 14)
            )
        ]
    }

    func pull(reference: String, onProgress: (@Sendable (PullProgress) -> Void)?) async throws -> ImageSummary {
        ImageSummary(reference: reference, digest: "sha256:preview")
    }

    func delete(reference: String) async throws {}
    func tag(source: String, target: String) async throws -> ImageSummary {
        ImageSummary(reference: target, digest: "sha256:preview")
    }
}

private struct PreviewRegistryService: RegistryServicing {
    func list() async throws -> [RegistryEntry] { [] }
    func login(registry: String, username: String, password: String) async throws {}
    func logout(registry: String) async throws {}
}
#endif
