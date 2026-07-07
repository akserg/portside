// Views/Containers/DiagnosisResultCard.swift
// Issue 1.7 — typed diagnosis result rendering for DiagnosisCard.

import SwiftUI

struct DiagnosisResultCard: View {
    let result: DiagnosisResult
    let isDimmed: Bool
    let isVerifying: Bool
    let showsRegenerate: Bool
    let isRunning: Bool
    let onRegenerate: () -> Void

    var body: some View {
        let diagnosis = result.diagnosis
        let presentation = DiagnosisPresentation(result: result)

        VStack(alignment: .leading, spacing: 12) {
            if result.wasDegraded {
                Text("Limited analysis")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if presentation.showsLowConfidenceLabel {
                Text("Low confidence")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(diagnosis.summary)
                .font(.body)
                .foregroundStyle(summaryColor(presentation: presentation))
                .modifier(DiagnosisVerifyingShimmerModifier(isActive: isVerifying))

            HStack(spacing: 8) {
                diagnosisCategoryChip(presentation: presentation)
                if presentation.showsMediumConfidenceChip {
                    diagnosisConfidenceChip()
                }
            }

            if presentation.showsMediumConfidenceSubtext {
                Text("Likely cause — worth verifying.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if result.wasDegraded {
                Text(
                    "The analysis couldn't be fully verified against the logs, "
                    + "so Wharfside is showing only what the logs directly support."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !diagnosis.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(diagnosis.suggestedActions.enumerated()), id: \.offset) { index, action in
                        diagnosisActionRow(number: index + 1, action: action)
                    }
                }
            }

            HStack(spacing: 12) {
                Text(presentation.footerText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                if showsRegenerate {
                    Button("Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(isRunning)
                }
            }
        }
        .padding(14)
        .opacity(isDimmed ? 0.45 : 1)
        .background(
            diagnosisCardBackground(for: diagnosis.confidence, wasDegraded: result.wasDegraded),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func summaryColor(presentation: DiagnosisPresentation) -> Color {
        if isDimmed || presentation.usesMutedSummary { return .secondary }
        return .primary
    }

    private func diagnosisCategoryChip(presentation: DiagnosisPresentation) -> some View {
        Label(presentation.categoryTitle, systemImage: presentation.categorySymbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(presentation.categoryChipBackground, in: Capsule())
            .foregroundStyle(presentation.categoryChipForeground)
    }

    private func diagnosisConfidenceChip() -> some View {
        Text(Confidence.medium.displayTitle)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }

    private func diagnosisActionRow(number: Int, action: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(action)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if DiagnosisPresentation.containsCopyableCommand(action) {
                DiagnosisCopyActionButton(
                    text: DiagnosisPresentation.extractCommand(from: action) ?? action
                )
            }
        }
    }
}
