// AI/GenerableModels.swift
// Issue 1.6 — @Generable diagnosis output types (AI_INTEGRATION.md §4.2).

import Foundation
import FoundationModels

@Generable
struct ContainerDiagnosis: Sendable, Equatable {
    @Guide(description: "One-sentence summary of the most likely root cause.")
    var summary: String

    @Guide(description: "Likely root cause category.")
    var category: FailureCategory

    @Guide(description: "2–4 concrete, actionable next steps the developer should try, most likely fix first.")
    var suggestedActions: [String]

    @Guide(description: "Confidence in this diagnosis based only on the evidence provided.")
    var confidence: Confidence
}

@Generable
enum FailureCategory: String, Sendable {
    case dependencyUnreachable
    case configuration
    case outOfMemory
    case applicationBug
    case imageOrRuntime
    case stopped
    case unknown
}

@Generable
enum Confidence: String, Sendable {
    case low
    case medium
    case high
}

enum DiagnosisError: Error, Sendable {
    case aiUnavailable(reason: DegradedReason)
    case timedOut
    case cancelled
    case incompleteResponse
}

extension ContainerDiagnosis {
    init(partial: PartiallyGenerated) throws {
        guard
            let summary = partial.summary,
            let category = partial.category,
            let suggestedActions = partial.suggestedActions,
            let confidence = partial.confidence
        else {
            throw DiagnosisError.incompleteResponse
        }
        self.summary = summary
        self.category = category
        self.suggestedActions = suggestedActions
        self.confidence = confidence
    }
}
