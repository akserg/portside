// Views/Containers/DiagnosisCardPreviews.swift
// Issue 1.7 — SwiftUI previews for every diagnosis card state.

import SwiftUI

#if DEBUG
enum DiagnosisCardPreviewData {
    static let highConfidence = DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "PostgreSQL shut down because the host disk is full — writes failed.",
            category: .configuration,
            suggestedActions: [
                "Free disk space on the host, then run `container start db`",
                "Inspect volume usage with `container inspect db`"
            ],
            confidence: .high
        ),
        wasDegraded: false,
        telemetry: .init(violations: [], retryCount: 0, wasDegraded: false)
    )

    static let mediumConfidence = DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "The API could not connect to its database — connection refused on localhost:5432.",
            category: .dependencyUnreachable,
            suggestedActions: [
                "Start the database container with `container start db`",
                "Verify the port mapping with `container inspect api`"
            ],
            confidence: .medium
        ),
        wasDegraded: false,
        telemetry: .init(violations: [], retryCount: 0, wasDegraded: false)
    )

    static let lowConfidence = DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "Logs show a clean exit with no errors — Wharfside cannot infer a crash cause.",
            category: .unknown,
            suggestedActions: [
                "Check `container logs quiet` for startup messages",
                "Confirm the container command exits intentionally"
            ],
            confidence: .low
        ),
        wasDegraded: false,
        telemetry: .init(violations: [], retryCount: 0, wasDegraded: false)
    )

    static let degraded = DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "Logs report: ERROR: No space left on device",
            category: .configuration,
            suggestedActions: ["Free disk space on the host"],
            confidence: .low
        ),
        wasDegraded: true,
        telemetry: .init(
            violations: [.fabricatedEvidence(term: "disk")],
            retryCount: 1,
            wasDegraded: true
        )
    )
}

#Preview("Idle") {
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: .idle))
        .padding()
        .frame(width: 480)
}

#Preview("Running — skeleton") {
    let phase: DiagnosisCardViewModel.Phase = .running(
        .init(partialSummary: nil, hasReceivedFirstToken: false)
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Running — partial") {
    let phase: DiagnosisCardViewModel.Phase = .running(
        .init(
            partialSummary: "PostgreSQL shut down because the host disk",
            hasReceivedFirstToken: true
        )
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Result — high confidence") {
    let phase: DiagnosisCardViewModel.Phase = .result(
        .init(result: DiagnosisCardPreviewData.highConfidence, isVerifying: false)
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Result — medium confidence") {
    let phase: DiagnosisCardViewModel.Phase = .result(
        .init(result: DiagnosisCardPreviewData.mediumConfidence, isVerifying: false)
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Result — low confidence") {
    let phase: DiagnosisCardViewModel.Phase = .result(
        .init(result: DiagnosisCardPreviewData.lowConfidence, isVerifying: false)
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Degraded") {
    let phase: DiagnosisCardViewModel.Phase = .result(
        .init(result: DiagnosisCardPreviewData.degraded, isVerifying: false)
    )
    DiagnosisCard(viewModel: DiagnosisCardViewModel.preview(phase: phase))
        .padding()
        .frame(width: 480)
}

#Preview("Failed") {
    DiagnosisCard(
        viewModel: DiagnosisCardViewModel.preview(phase: .failed("Diagnosis timed out. Try again."))
    )
    .padding()
    .frame(width: 480)
}
#endif
