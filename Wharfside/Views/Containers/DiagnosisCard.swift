// Views/Containers/DiagnosisCard.swift
// Issue 1.7 — "Explain this crash" diagnosis card.

import SwiftUI

struct DiagnosisCard: View {
    @Bindable var viewModel: DiagnosisCardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.phase {
            case .idle:
                idleContent
            case .running(let state):
                runningContent(state)
            case .result(let state):
                resultContent(state)
            case .failed(let message):
                failedContent(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.explain()
            } label: {
                Label("Explain this crash", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("On-device analysis of this container's logs. Nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func runningContent(_ state: DiagnosisCardViewModel.RunningState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowSkeleton(state) {
                VStack(alignment: .leading, spacing: 8) {
                    DiagnosisSkeletonLine(widthFraction: 0.92)
                    DiagnosisSkeletonLine(widthFraction: 0.78)
                    DiagnosisSkeletonLine(widthFraction: 0.55)
                }
            }

            if let partial = state.partialSummary, !partial.isEmpty {
                Text(partial)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shouldShowStatusMessage(state) {
                Text("Analyzing container logs…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(diagnosisCardBackground(for: .high, wasDegraded: false), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func resultContent(_ state: DiagnosisCardViewModel.ResultState) -> some View {
        DiagnosisResultCard(
            result: state.result,
            isDimmed: false,
            isVerifying: state.isVerifying,
            showsRegenerate: true,
            isRunning: viewModel.isRunning,
            onRegenerate: { viewModel.regenerate() }
        )
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry") {
                viewModel.retryAfterFailure()
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func shouldShowSkeleton(_ state: DiagnosisCardViewModel.RunningState) -> Bool {
        switch DiagnosisCardViewModel.loadingStyle {
        case .directStream:
            false
        case .skeletonUntilFirstToken, .skeletonWithStatus:
            !state.hasReceivedFirstToken
        }
    }

    private func shouldShowStatusMessage(_ state: DiagnosisCardViewModel.RunningState) -> Bool {
        DiagnosisCardViewModel.loadingStyle == .skeletonWithStatus && !state.hasReceivedFirstToken
    }
}
