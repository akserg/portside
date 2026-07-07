// Views/Containers/ContainerOverviewSection.swift
// Issue 1.7 — Overview tab content including the diagnosis section.

import SwiftUI

struct ContainerOverviewSection: View {
    @Environment(AIAvailabilityService.self) private var aiAvailability

    let detail: ContainerDetail
    let displayStatus: String
    let observerRestartCount: Int
    let isDiagnosisEligible: Bool
    @Bindable var diagnosisCardViewModel: DiagnosisCardViewModel
    let formattedDate: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CopyableValueView(label: "ID", value: detail.id)
            CopyableValueView(label: "Image", value: detail.image)
            CopyableValueView(label: "Status", value: displayStatus, monospaced: false)
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
                value: String(observerRestartCount),
                monospaced: false
            )

            if isDiagnosisEligible {
                Divider()
                    .padding(.vertical, 12)

                Text("Diagnosis")
                    .font(.headline)
                    .padding(.bottom, 8)

                AIGated {
                    DiagnosisCard(viewModel: diagnosisCardViewModel)
                }
                .onAppear {
                    aiAvailability.refresh()
                    diagnosisCardViewModel.onEligibleAppear()
                }
            }
        }
    }
}
