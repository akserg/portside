// Views/Containers/ContainerDetailViewPreviews.swift

import SwiftUI

#if DEBUG
#Preview {
    ContainerDetailView(
        containerID: "hello",
        service: ContainerDetailPreviewService(),
        lifecycleObserver: ContainerLifecycleObserver(),
        availability: PreviewAvailabilityProvider(),
        onBackToList: {}
    )
    .environment(AppState(
        systemService: XPCSystemService(),
        containerService: XPCContainerService(),
        imageService: XPCImageService(),
        registryService: CLIRegistryService()
    ))
    .environment(AIAvailabilityService())
    .frame(width: 480, height: 520)
}

private struct ContainerDetailPreviewService: ContainerServicing {
    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail {
        ContainerDetail(
            id: id,
            image: "alpine:latest",
            status: .stopped,
            command: ["/bin/sleep", "600"],
            createdAt: .now,
            startedAt: .now,
            exitCode: 1,
            restartCount: 0,
            ports: [ContainerPortBinding(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 80, proto: "tcp")],
            mounts: [],
            environment: [ContainerEnvironmentVariable(key: "SECRET", value: "hunter2")],
            networks: []
        )
    }
    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}
    func stats(id: String) async throws -> ContainerStats { fatalError() }
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
}

struct PreviewAvailabilityProvider: AvailabilityProviding {
    func currentCapability() -> AICapability { .full }
}
#endif
