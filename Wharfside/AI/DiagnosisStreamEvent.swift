// AI/DiagnosisStreamEvent.swift
// Issue 1.7 — streaming diagnosis events for the diagnosis card UI.

import Foundation

enum DiagnosisStreamEvent: Sendable {
    case partial(ContainerDiagnosis.PartiallyGenerated)
    case finalized(DiagnosisResult)
}
