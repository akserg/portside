// AI/LogDiagnosisService+Pipeline.swift
// Issue 1.7 — validation and streaming pipeline helpers for LogDiagnosisService.

import Foundation
import WharfsideAnalysis

extension LogDiagnosisService {
    struct DiagnosisContext {
        let digest: LogDigest
        let renderedDigest: String
        let basePrompt: String
    }

    func runValidatedDiagnosis(
        context: DiagnosisContext,
        generationSettings: DiagnosisGenerationSettings
    ) async throws -> DiagnosisResult {
        var retryCount = 0
        var allViolations: [DiagnosisViolation] = []

        let first = try await generateDiagnosis(
            prompt: context.basePrompt,
            generationSettings: generationSettings
        )
        if let result = processDiagnosis(
            first,
            context: context,
            retryCount: &retryCount,
            allViolations: &allViolations
        ) {
            return result
        }

        return try await retryOrDegrade(
            context: context,
            generationSettings: generationSettings,
            retryCount: &retryCount,
            allViolations: &allViolations
        )
    }

    func runStreamingValidatedDiagnosis(
        context: DiagnosisContext,
        generationSettings: DiagnosisGenerationSettings,
        onPartial: (ContainerDiagnosis.PartiallyGenerated) -> Void
    ) async throws -> DiagnosisResult {
        var retryCount = 0
        var allViolations: [DiagnosisViolation] = []

        let first = try await streamToDiagnosis(
            prompt: context.basePrompt,
            generationSettings: generationSettings,
            onPartial: onPartial
        )
        if let result = processDiagnosis(
            first,
            context: context,
            retryCount: &retryCount,
            allViolations: &allViolations
        ) {
            return result
        }

        return try await retryOrDegrade(
            context: context,
            generationSettings: generationSettings,
            retryCount: &retryCount,
            allViolations: &allViolations
        )
    }

    func withDiagnosisTimeout<T>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: Self.diagnosisTimeout)
                throw DiagnosisError.timedOut
            }
            guard let result = try await group.next() else {
                throw DiagnosisError.incompleteResponse
            }
            group.cancelAll()
            return result
        }
    }

    func buildContext(container: ContainerDetail, entries: [LogEntry]) async -> DiagnosisContext {
        let restartCount = await lifecycleObserver.restartCount(for: container.id)
        let context = ContainerContext(
            containerName: container.id,
            image: container.image,
            exitCode: container.exitCode,
            restartCount: restartCount
        )
        let window = digestWindow(for: container)
        let digest = digestBuilder.build(entries: entries, context: context, window: window)
        let rendered = promptRenderer.render(digest)
        return DiagnosisContext(
            digest: digest,
            renderedDigest: rendered,
            basePrompt: rendered
        )
    }

    // MARK: - Private pipeline

    private func retryOrDegrade(
        context: DiagnosisContext,
        generationSettings: DiagnosisGenerationSettings,
        retryCount: inout Int,
        allViolations: inout [DiagnosisViolation]
    ) async throws -> DiagnosisResult {
        let corrections = validator.correctionLines(for: allViolations, digest: context.digest)
        let retryPrompt = context.basePrompt + "\n\nCORRECTION: " + corrections.joined(separator: " ")
        retryCount = 1

        let second = try await generateDiagnosis(
            prompt: retryPrompt,
            generationSettings: generationSettings
        )
        if let result = processDiagnosis(
            second,
            context: context,
            retryCount: &retryCount,
            allViolations: &allViolations
        ) {
            return result
        }

        var degraded = validator.degrade(
            diagnosis: second,
            digest: context.digest,
            violations: allViolations
        )
        _ = validator.repairVocabulary(&degraded)

        return DiagnosisResult(
            diagnosis: degraded,
            wasDegraded: true,
            telemetry: DiagnosisTelemetry(
                violations: allViolations,
                retryCount: retryCount,
                wasDegraded: true
            )
        )
    }

    private func processDiagnosis(
        _ raw: ContainerDiagnosis,
        context: DiagnosisContext,
        retryCount: inout Int,
        allViolations: inout [DiagnosisViolation]
    ) -> DiagnosisResult? {
        var diagnosis = raw
        _ = validator.repairVocabulary(&diagnosis)

        let violations = validator.validate(
            diagnosis,
            against: context.digest,
            renderedDigest: context.renderedDigest
        )
        let retryable = violations.filter {
            if case .wrongCLIVocabulary = $0 { return false }
            return true
        }

        allViolations = violations

        guard retryable.isEmpty else { return nil }

        return DiagnosisResult(
            diagnosis: diagnosis,
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(
                violations: violations,
                retryCount: retryCount,
                wasDegraded: false
            )
        )
    }

    private func generateDiagnosis(
        prompt: String,
        generationSettings: DiagnosisGenerationSettings
    ) async throws -> ContainerDiagnosis {
        try await streamToDiagnosis(
            prompt: prompt,
            generationSettings: generationSettings,
            onPartial: { _ in }
        )
    }

    private func streamToDiagnosis(
        prompt: String,
        generationSettings: DiagnosisGenerationSettings,
        onPartial: (ContainerDiagnosis.PartiallyGenerated) -> Void
    ) async throws -> ContainerDiagnosis {
        var latest: ContainerDiagnosis.PartiallyGenerated?
        let stream = sessionFactory.stream(
            instructions: Self.instructions,
            prompt: prompt,
            options: generationSettings
        )
        for try await partial in stream {
            try Task.checkCancellation()
            latest = partial
            onPartial(partial)
        }
        guard let latest else { throw DiagnosisError.incompleteResponse }
        return try ContainerDiagnosis(partial: latest)
    }

    private func digestWindow(for container: ContainerDetail) -> DigestWindow {
        switch container.status {
        case .stopped:
            DigestWindow(description: "logs before container exit")
        case .running, .stopping:
            DigestWindow(description: "recent logs")
        case .unknown:
            DigestWindow(description: "available logs")
        }
    }
}
