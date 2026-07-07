// AI/AIAvailabilityService.swift
// Issue 0.5 — availability gating + degraded-mode plumbing (AI_INTEGRATION.md §3).
//
// Design notes:
// - SystemLanguageModel.availability is a synchronous property with no change
//   notifications, so we re-check at meaningful moments (launch, app foreground,
//   before any AI feature runs) rather than polling on a timer.
// - The FoundationModels dependency is isolated behind AvailabilityProviding so
//   every UI state is unit-testable without Apple Intelligence.

import AppKit
import Foundation
import FoundationModels
import Observation

// MARK: - Capability model

enum AICapability: Equatable, Sendable {
    case full
    case heuristicsOnly(DegradedReason)

    var isAIAvailable: Bool { self == .full }
}

enum DegradedReason: Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case checking
    case other(String)

    var userMessage: String {
        switch self {
        case .deviceNotEligible:
            "This Mac doesn't support Apple Intelligence, so AI features are unavailable. "
            + "Everything else works normally."
        case .appleIntelligenceNotEnabled:
            "Enable Apple Intelligence in System Settings to unlock crash diagnosis and AI assistance."
        case .modelNotReady:
            "The on-device model is still downloading. AI features will activate automatically when it's ready."
        case .checking:
            "Checking Apple Intelligence availability…"
        case .other(let detail):
            "AI features are temporarily unavailable (\(detail)). Heuristic analysis still works."
        }
    }

    /// Only the user-fixable state gets a call-to-action button.
    var isUserActionable: Bool {
        if case .appleIntelligenceNotEnabled = self { return true }
        return false
    }
}

// MARK: - Provider seam (testability)

protocol AvailabilityProviding: Sendable {
    func currentCapability() -> AICapability
}

struct SystemModelAvailabilityProvider: AvailabilityProviding {
    func currentCapability() -> AICapability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .full
        case .unavailable(.deviceNotEligible):
            return .heuristicsOnly(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .heuristicsOnly(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .heuristicsOnly(.modelNotReady)
        case .unavailable(let other):
            return .heuristicsOnly(.other(String(describing: other)))
        @unknown default:
            return .heuristicsOnly(.other("unknown availability state"))
        }
    }
}

// MARK: - Service

@MainActor
@Observable
final class AIAvailabilityService {
    private(set) var capability: AICapability = .heuristicsOnly(.checking)

    /// True once modelNotReady has been observed — lets the UI say "still
    /// downloading" vs generic unavailable, and justifies opportunistic re-checks.
    private(set) var sawModelDownloading = false

    private let provider: any AvailabilityProviding

    init() {
        self.provider = SystemModelAvailabilityProvider()
    }

    init(provider: any AvailabilityProviding) {
        self.provider = provider
    }

    /// Call at: app launch, scenePhase → .active, and immediately before any
    /// AI feature entry point (cheap synchronous check — no reason to trust stale
    /// state when the user clicks "Explain this crash").
    func refresh() {
        let next = provider.currentCapability()
        if case .heuristicsOnly(.modelNotReady) = next { sawModelDownloading = true }
        capability = next
    }

    /// Opens System Settings for the user-actionable case.
    /// NOTE: verify this pane identifier on a macOS 26 machine — Settings pane
    /// URLs are not API-stable across releases. Fallback opens Settings root.
    func openAppleIntelligenceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.siri",
            "x-apple.systempreferences:"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

extension AIAvailabilityService: AvailabilityProviding {
    func currentCapability() -> AICapability {
        capability
    }
}
