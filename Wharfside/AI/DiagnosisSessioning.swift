// AI/DiagnosisSessioning.swift
// Issue 1.6 — session factory seam for CI-safe diagnosis logic tests.

import Foundation
import FoundationModels

protocol DiagnosisSessioning: Sendable {
    func prewarm(instructions: String) async throws
    func stream(
        instructions: String,
        prompt: String,
        options: DiagnosisGenerationSettings
    ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error>
}

struct FoundationModelsDiagnosisSession: DiagnosisSessioning {
    func prewarm(instructions: String) async throws {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
    }

    func stream(
        instructions: String,
        prompt: String,
        options: DiagnosisGenerationSettings
    ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
        let session = LanguageModelSession(instructions: instructions)
        let generationOptions = options.generationOptions()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: ContainerDiagnosis.self,
                        options: generationOptions
                    )
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DiagnosisError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
