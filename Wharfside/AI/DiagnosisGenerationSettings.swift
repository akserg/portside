// AI/DiagnosisGenerationSettings.swift
// Issue 1.6.1 — per-call FoundationModels sampling controls for diagnosis.

import Foundation
import FoundationModels

/// Wharfside-facing generation settings threaded into each diagnosis call.
struct DiagnosisGenerationSettings: Sendable, Equatable {
    /// Sampling temperature; lower values reduce variance. `nil` leaves the SDK default.
    var temperature: Double?

    nonisolated static let diagnosisDefault = DiagnosisGenerationSettings(temperature: 0.2)

    func generationOptions() -> GenerationOptions {
        var options = GenerationOptions()
        if let temperature {
            options.temperature = temperature
        }
        return options
    }
}
