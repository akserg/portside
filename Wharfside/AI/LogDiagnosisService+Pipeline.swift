// AI/LogDiagnosisService+Pipeline.swift
// Issue 1.7 — validation and streaming pipeline helpers for LogDiagnosisService.

import Foundation
import RulebookCore
import WharfsideAnalysis

extension LogDiagnosisService {
    struct DiagnosisContext {
        let digest: LogDigest
        let renderedDigest: String
        let basePrompt: String
        let buildResult: DigestBuildResult
        let matchLines: [String]

        var evaluation: RuleEvaluation { buildResult.evaluation }
        var ruleMetadata: DiagnosisRuleMetadata { DiagnosisRuleMetadata(buildResult: buildResult) }
    }

    func runValidatedDiagnosis(
        context: DiagnosisContext,
        generationSettings: DiagnosisGenerationSettings
    ) async throws -> DiagnosisResult {
        if let conclusion = context.evaluation.precheckConclusion,
           let diagnosis = PrecheckDiagnosisBuilder.diagnosis(
               from: conclusion,
               containerName: context.digest.containerName,
               exitStatus: context.digest.exitStatus
           ) {
            return DiagnosisResult(
                diagnosis: diagnosis,
                wasDegraded: false,
                telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
                renderedDigest: context.renderedDigest,
                ruleMetadata: context.ruleMetadata,
                source: .deterministicPrecheck(ruleID: conclusion.ruleID),
                exitStatus: context.digest.exitStatus
            )
        }

        var retryCount = 0
        var allViolations: [DiagnosisViolation] = []

        let first = try await generateDiagnosis(
            prompt: context.basePrompt,
            generationSettings: generationSettings
        )
        if let result = processDiagnosis(
            first,
            context: context,
            renderedDigest: context.renderedDigest,
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
        if let conclusion = context.evaluation.precheckConclusion,
           let diagnosis = PrecheckDiagnosisBuilder.diagnosis(
               from: conclusion,
               containerName: context.digest.containerName,
               exitStatus: context.digest.exitStatus
           ) {
            return DiagnosisResult(
                diagnosis: diagnosis,
                wasDegraded: false,
                telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
                renderedDigest: context.renderedDigest,
                ruleMetadata: context.ruleMetadata,
                source: .deterministicPrecheck(ruleID: conclusion.ruleID),
                exitStatus: context.digest.exitStatus
            )
        }

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
            renderedDigest: context.renderedDigest,
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
        let exitStatus = await resolvedExitStatus(for: container, entries: entries)
        let context = ContainerContext(
            containerName: container.id,
            image: container.image,
            exitStatus: exitStatus,
            restartCount: restartCount
        )
        let window = digestWindow(for: container)
        let buildResult = digestBuilder.buildWithRules(
            entries: entries,
            context: context,
            window: window,
            rulebookPipeline: rulebookPipeline
        )
        let rendered = promptRenderer.render(buildResult.digest)
        let matchContext = MatchContextBuilder.make(entries: entries, context: context)
        return DiagnosisContext(
            digest: buildResult.digest,
            renderedDigest: rendered,
            basePrompt: rendered,
            buildResult: buildResult,
            matchLines: matchContext.logLines
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
            renderedDigest: retryPrompt,
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
            ),
            renderedDigest: retryPrompt,
            ruleMetadata: context.ruleMetadata,
            exitStatus: context.digest.exitStatus
        )
    }

    private func processDiagnosis(
        _ raw: ContainerDiagnosis,
        context: DiagnosisContext,
        renderedDigest: String,
        retryCount: inout Int,
        allViolations: inout [DiagnosisViolation]
    ) -> DiagnosisResult? {
        var diagnosis = raw
        _ = validator.repairVocabulary(&diagnosis)

        let violations = validator.validate(
            diagnosis,
            against: context.digest,
            renderedDigest: context.renderedDigest,
            evaluation: context.evaluation,
            matchLines: context.matchLines
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
            ),
            renderedDigest: renderedDigest,
            ruleMetadata: context.ruleMetadata,
            exitStatus: context.digest.exitStatus
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
        try Task.checkCancellation()
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

    func resolvedExitStatus(for container: ContainerDetail, entries: [LogEntry]) async -> ExitStatus {
        switch container.status {
        case .running:
            return .unavailable(reason: .stillRunning)
        case .stopping, .stopped, .unknown:
            break
        }

        let runtime: ExitStatus
        if let containerService {
            runtime = await containerService.exitStatus(id: container.id)
        } else {
            runtime = container.exitStatus
        }
        return ExitStatusResolver.resolve(runtime: runtime, bootEntries: entries)
    }
}
