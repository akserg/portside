// Views/Shared/AIStatusBanner.swift
// Issue 0.5 — the reusable degraded-state surface. Every future AI panel
// (diagnosis card, advice tier, palette) wraps itself in `AIGated` instead of
// implementing its own availability handling.

import SwiftUI

/// Shows AI content when available; otherwise the explanatory banner.
/// Usage:
///     AIGated {
///         DiagnosisCard(...)      // only built when capability == .full
///     }
struct AIGated<Content: View>: View {
    @Environment(AIAvailabilityService.self) private var availability
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch availability.capability {
        case .full:
            content()
        case .heuristicsOnly(let reason):
            AIStatusBanner(reason: reason)
        }
    }
}

struct AIStatusBanner: View {
    @Environment(AIAvailabilityService.self) private var availability
    let reason: DegradedReason
    /// Link button fails under `ImageRenderer` (yellow missing-glyph placeholder) — off for stills.
    var showsActionButton: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 6) {
                Text(reason.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsActionButton, reason.isUserActionable {
                    Button("Open System Settings…") {
                        availability.openAppleIntelligenceSettings()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch reason {
        case .modelNotReady, .checking: "arrow.down.circle.dotted"
        case .appleIntelligenceNotEnabled: "sparkles"
        case .deviceNotEligible, .other: "sparkles.slash" // falls back if glyph absent
        }
    }
}

#Preview("Not enabled") {
    AIStatusBanner(reason: .appleIntelligenceNotEnabled)
        .environment(AIAvailabilityService())
        .padding().frame(width: 420)
}

#Preview("Downloading") {
    AIStatusBanner(reason: .modelNotReady)
        .environment(AIAvailabilityService())
        .padding().frame(width: 420)
}
