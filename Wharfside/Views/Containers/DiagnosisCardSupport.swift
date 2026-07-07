// Views/Containers/DiagnosisCardSupport.swift
// Issue 1.7 — presentation helpers and visual modifiers for DiagnosisCard.

import AppKit
import SwiftUI

struct DiagnosisPresentation {
    let result: DiagnosisResult

    var diagnosis: ContainerDiagnosis { result.diagnosis }

    var usesMutedSummary: Bool {
        result.wasDegraded || diagnosis.confidence == .low
    }

    var showsLowConfidenceLabel: Bool {
        diagnosis.confidence == .low && !result.wasDegraded
    }

    var showsMediumConfidenceChip: Bool {
        diagnosis.confidence == .medium && !result.wasDegraded
    }

    var showsMediumConfidenceSubtext: Bool {
        showsMediumConfidenceChip
    }

    var categoryTitle: String {
        switch diagnosis.category {
        case .dependencyUnreachable: "Dependency unreachable"
        case .configuration: "Configuration"
        case .outOfMemory: "Out of memory"
        case .applicationBug: "Application bug"
        case .imageOrRuntime: "Image / runtime"
        case .unknown: "Unknown"
        }
    }

    var categorySymbol: String {
        switch diagnosis.category {
        case .dependencyUnreachable: "network"
        case .configuration: "gearshape"
        case .outOfMemory: "memorychip"
        case .applicationBug: "ladybug"
        case .imageOrRuntime: "shippingbox"
        case .unknown: "questionmark.circle"
        }
    }

    var categoryChipBackground: Color {
        if result.wasDegraded || diagnosis.confidence == .low {
            return Color.secondary.opacity(0.12)
        }
        return Color.accentColor.opacity(0.12)
    }

    var categoryChipForeground: Color {
        if result.wasDegraded || diagnosis.confidence == .low {
            return .secondary
        }
        return .primary
    }

    var footerText: String {
        let confidence = diagnosis.confidence.displayTitle.lowercased()
        return "on-device · \(categoryTitle.lowercased()) · \(confidence)"
    }

    static func containsCopyableCommand(_ action: String) -> Bool {
        action.contains("`container") || action.lowercased().contains("container ")
    }

    static func extractCommand(from action: String) -> String? {
        if let range = action.range(of: "`([^`]+)`", options: .regularExpression) {
            let match = action[range]
            return match.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
        if let range = action.range(of: "container [^\\s]+.*", options: .regularExpression) {
            return String(action[range])
        }
        return nil
    }
}

extension Confidence {
    var displayTitle: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

struct DiagnosisSkeletonLine: View {
    let widthFraction: CGFloat
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(shimmer ? 0.22 : 0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 12)
            .scaleEffect(x: widthFraction, y: 1, anchor: .leading)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}

struct DiagnosisVerifyingShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var shimmer = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && shimmer ? 0.72 : 1)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    shimmer = true
                }
            }
            .onChange(of: isActive) { _, active in
                shimmer = active
            }
    }
}

struct DiagnosisCopyActionButton: View {
    let text: String
    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy command")
    }
}

func diagnosisCardBackground(for confidence: Confidence, wasDegraded: Bool) -> Color {
    if wasDegraded || confidence == .low {
        return Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    }
    return Color(nsColor: .controlBackgroundColor)
}
