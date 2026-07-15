// Views/Containers/DiagnosisResultCard.swift
// Issue 1.7 — typed diagnosis result rendering for DiagnosisCard.
// Issue 1.11 — "Copy report" affordance, available in every result state (degraded included).

import SwiftUI

struct DiagnosisResultCard: View {
    let result: DiagnosisResult
    let isDimmed: Bool
    let isVerifying: Bool
    let showsRegenerate: Bool
    /// Footer "Copy report" / "Regenerate" controls. Off for some `ImageRenderer` stills.
    var showsFooterActions: Bool = true
    /// SF Symbol labels in the footer. Off for ImageRenderer — those glyphs paint yellow.
    var showsFooterActionSymbols: Bool = true
    /// Per-action `doc.on.doc` copy chips next to suggested commands.
    var showsInlineCopyButtons: Bool = true
    let isRunning: Bool
    let onRegenerate: () -> Void
    let onCopyReport: () -> Void

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

            if presentation.showsOrderlyStopSubtext {
                Text("Observed in boot log — not a crash.")
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

                if showsFooterActions {
                    if showsFooterActionSymbols {
                        footerActionButton(
                            title: "Copy report",
                            systemImage: "doc.on.doc",
                            action: onCopyReport
                        )
                        .help(
                            "Copy a reproduction bundle (digest, diagnosis, versions) to paste into a bug report"
                        )

                        if showsRegenerate {
                            footerActionButton(
                                title: "Regenerate",
                                systemImage: "arrow.clockwise",
                                action: onRegenerate
                            )
                            .disabled(isRunning)
                        }
                    } else {
                        // ImageRenderer paints yellow placeholders for borderless Buttons —
                        // stills use inert text so the action bar remains legible.
                        Text("Copy report")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showsRegenerate {
                            Text("Regenerate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .opacity(isDimmed ? 0.45 : 1)
        .background(
            diagnosisCardBackground(for: diagnosis.confidence, wasDegraded: result.wasDegraded),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contextMenu {
            Button(action: onCopyReport) {
                Label("Copy report", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private func footerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderless)
        .font(.caption)
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

            if showsInlineCopyButtons, DiagnosisPresentation.containsCopyableCommand(action) {
                DiagnosisCopyActionButton(
                    text: DiagnosisPresentation.extractCommand(from: action) ?? action
                )
            }
        }
    }
}
