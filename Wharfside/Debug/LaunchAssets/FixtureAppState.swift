// Debug/LaunchAssets/FixtureAppState.swift
// B5 — DEBUG-gated AppState factory: fixture-driven services, no live daemon.

#if DEBUG
import Foundation
import Observation
import WharfsideAnalysis

@MainActor
enum FixtureAppState {
    struct Bundle {
        let appState: AppState
        let aiAvailability: AIAvailabilityService
        let containerService: FixtureContainerService
        let degradedAIAvailability: AIAvailabilityService
    }

    static func make(fixtureName: String = "report2") -> Bundle {
        _ = fixtureName // reserved for additional packs

        let details = makeDetails()
        let containerService = FixtureContainerService(
            details: details,
            logChunksByID: makeLogChunks(for: details)
        )
        let appState = makeAppState(containerService: containerService)
        let aiAvailability = AIAvailabilityService(
            provider: LaunchAssetFixedAvailability(capability: .full)
        )
        aiAvailability.refresh()
        let degradedAIAvailability = AIAvailabilityService(
            provider: LaunchAssetFixedAvailability(
                capability: .heuristicsOnly(.appleIntelligenceNotEnabled)
            )
        )
        degradedAIAvailability.refresh()

        return Bundle(
            appState: appState,
            aiAvailability: aiAvailability,
            containerService: containerService,
            degradedAIAvailability: degradedAIAvailability
        )
    }

    private static func makeDetails() -> [ContainerDetail] {
        let hello = FixtureReplay.helloContainerDetail()
        let crashy = ContainerDetail(
            id: "crashy",
            image: "crashy:latest",
            status: .stopped,
            command: ["crashy"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: nil,
            exitStatus: .known(1, source: .runtime),
            restartCount: 1,
            ports: [],
            mounts: [],
            environment: [],
            networks: []
        )
        let web = ContainerDetail(
            id: "web",
            image: "nginx:alpine",
            status: .running,
            command: ["nginx"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: Date(timeIntervalSince1970: 1_700_010_000),
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0,
            ports: [
                ContainerPortBinding(
                    hostAddress: "0.0.0.0",
                    hostPort: 8080,
                    containerPort: 80,
                    proto: "tcp"
                )
            ],
            mounts: [],
            environment: [],
            networks: []
        )
        return [hello, crashy, web]
    }

    private static func makeLogChunks(for details: [ContainerDetail]) -> [String: [LogChunk]] {
        let report2 = (try? FixtureReplay.loadLogChunks(named: FixtureReplay.report2LogName)) ?? []
        let noisy = (try? FixtureReplay.loadLogChunks(named: FixtureReplay.noisyLogName)) ?? report2
        var map: [String: [LogChunk]] = [:]
        for detail in details {
            map[detail.id] = detail.id == "crashy" ? noisy : report2
        }
        return map
    }

    private static func makeAppState(containerService: FixtureContainerService) -> AppState {
        let appState = AppState(
            systemService: FixtureSystemService(),
            containerService: containerService,
            imageService: FixtureImageService(),
            registryService: FixtureRegistryService()
        )
        appState.selectedSection = .containers
        appState.isServiceRunning = true
        appState.seedCachedHealth(
            SystemHealth(
                apiServerVersion: "1.0.0",
                apiServerCommit: "ee848e3",
                apiServerBuild: "release",
                apiServerAppName: "container",
                appRoot: URL(fileURLWithPath: "/tmp"),
                installRoot: URL(fileURLWithPath: "/tmp"),
                logRootPath: nil
            )
        )
        return appState
    }
}

// MARK: - Fixture services

@MainActor
final class FixtureContainerService: ContainerServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var detailsByID: [String: ContainerDetail]
    private var logChunksByID: [String: [LogChunk]]

    init(details: [ContainerDetail], logChunksByID: [String: [LogChunk]] = [:]) {
        var map: [String: ContainerDetail] = [:]
        for detail in details {
            map[detail.id] = detail
        }
        self.detailsByID = map
        self.logChunksByID = logChunksByID
    }

    func list() async throws -> [ContainerSummary] {
        lock.withLock {
            detailsByID.values
                .sorted { $0.id < $1.id }
                .map { detail in
                    ContainerSummary(
                        id: detail.id,
                        image: detail.image,
                        status: detail.status,
                        startedAt: detail.startedAt,
                        portSummary: detail.ports.isEmpty
                            ? "—"
                            : detail.ports.map { "\($0.hostPort):\($0.containerPort)" }.joined(separator: ", ")
                    )
                }
        }
    }

    func get(id: String) async throws -> ContainerDetail {
        try lock.withLock {
            guard let detail = detailsByID[id] else {
                throw WharfsideError.notFound(id)
            }
            return detail
        }
    }

    func exitStatus(id: String) async -> ExitStatus {
        (try? await get(id: id))?.exitStatus ?? .unavailable(reason: .noEvidence)
    }

    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}

    func stats(id: String) async throws -> ContainerStats {
        ContainerStats(
            id: id,
            memoryUsageBytes: nil,
            memoryLimitBytes: nil,
            cpuUsageMicroseconds: nil,
            networkRxBytes: nil,
            networkTxBytes: nil,
            blockReadBytes: nil,
            blockWriteBytes: nil,
            processCount: nil
        )
    }

    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        let chunks = lock.withLock { logChunksByID[id] ?? [] }
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                if let source, chunk.source != source { continue }
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
}

final class FixtureSystemService: SystemServicing, @unchecked Sendable {
    func health() async throws -> SystemHealth {
        SystemHealth(
            apiServerVersion: "1.0.0",
            apiServerCommit: "ee848e3",
            apiServerBuild: "release",
            apiServerAppName: "container",
            appRoot: URL(fileURLWithPath: "/tmp"),
            installRoot: URL(fileURLWithPath: "/tmp"),
            logRootPath: nil
        )
    }

    func defaultKernelInstalled() async -> Bool { true }
}

final class FixtureImageService: ImageServicing, @unchecked Sendable {
    func list() async throws -> [ImageSummary] { [] }
    func pull(
        reference: String,
        onProgress: (@Sendable (PullProgress) -> Void)?
    ) async throws -> ImageSummary {
        ImageSummary(reference: reference, digest: "sha256:fixture", sizeBytes: 0, createdAt: .now)
    }
    func delete(reference: String) async throws {}
    func tag(source: String, target: String) async throws -> ImageSummary {
        ImageSummary(reference: target, digest: "sha256:fixture", sizeBytes: 0, createdAt: .now)
    }
}

final class FixtureRegistryService: RegistryServicing, @unchecked Sendable {
    func list() async throws -> [RegistryEntry] { [] }
    func login(registry: String, username: String, password: String) async throws {}
    func logout(registry: String) async throws {}
}
#endif
