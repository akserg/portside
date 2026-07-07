// Views/Containers/ContainerDetailView.swift

import AppKit
import SwiftUI

struct ContainerDetailView: View {
    @State private var viewModel: ContainerDetailViewModel
    @State private var logViewModel: LogViewModel
    @State private var diagnosisCardViewModel: DiagnosisCardViewModel

    private let service: any ContainerServicing
    private let lifecycleObserver: ContainerLifecycleObserver
    let onBackToList: () -> Void

    init(
        containerID: String,
        service: any ContainerServicing,
        lifecycleObserver: ContainerLifecycleObserver,
        availability: any AvailabilityProviding,
        onBackToList: @escaping () -> Void
    ) {
        self.service = service
        self.lifecycleObserver = lifecycleObserver
        self.onBackToList = onBackToList
        _viewModel = State(
            initialValue: ContainerDetailViewModel(containerID: containerID, service: service)
        )
        _logViewModel = State(initialValue: LogViewModel(containerID: containerID, service: service))
        _diagnosisCardViewModel = State(
            initialValue: DiagnosisCardViewModel(
                containerID: containerID,
                diagnosisService: LogDiagnosisService(
                    availability: availability,
                    lifecycleObserver: lifecycleObserver
                ),
                containerService: service,
                logEntriesProvider: { [] }
            )
        )
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
        .onAppear {
            viewModel.startPolling()
            bindDiagnosisContext()
        }
        .onDisappear {
            viewModel.stopPolling()
            diagnosisCardViewModel.onDisappear()
        }
        .onChange(of: viewModel.detail?.id) { _, _ in
            bindDiagnosisContext()
        }
        .onChange(of: viewModel.detail?.status) { _, _ in
            bindDiagnosisContext()
        }
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
                viewModel: logViewModel,
                containerStatus: detail.status
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .overview:
                        ContainerOverviewSection(
                            detail: detail,
                            displayStatus: viewModel.displayStatusLabel(for: detail),
                            observerRestartCount: diagnosisCardViewModel.observerRestartCount,
                            isDiagnosisEligible: diagnosisCardViewModel.isEligible,
                            diagnosisCardViewModel: diagnosisCardViewModel,
                            formattedDate: formattedDate
                        )
                    case .ports:
                        ContainerDetailTabSections.ports(detail.ports)
                    case .mounts:
                        ContainerDetailTabSections.mounts(detail.mounts)
                    case .environment:
                        ContainerDetailTabSections.environment(detail.environment, viewModel: viewModel)
                    case .networks:
                        ContainerDetailTabSections.networks(detail.networks)
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

    private func bindDiagnosisContext() {
        diagnosisCardViewModel.logEntriesProvider = {
            logViewModel.recentEntries(window: DiagnosisCardViewModel.logEntriesWindow)
        }

        guard let detail = viewModel.detail else { return }
        diagnosisCardViewModel.updateContainer(detail)
        Task {
            let count = await lifecycleObserver.restartCount(for: detail.id)
            diagnosisCardViewModel.updateObserverRestartCount(count)
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
}
