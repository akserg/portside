import ArgumentParser
import ContainerAPIClient
import ContainerResource
import ContainerXPC
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation
import MachineAPIClient

struct ProbeCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xpc-probe",
        abstract: "Throwaway XPC capability probe for apple/container 1.0",
        subcommands: [
            RunAll.self,
            ListContainers.self,
            InspectContainer.self,
            CreateContainer.self,
            StartContainer.self,
            StopContainer.self,
            KillContainer.self,
            DeleteContainer.self,
            PauseProbe.self,
            LogsProbe.self,
            StatsProbe.self,
            ExecProbe.self,
            ListImages.self,
            PullImage.self,
            BuildProbe.self,
            ImageOpsProbe.self,
            RegistryProbe.self,
            VolumeProbe.self,
            MachineProbe.self,
            SystemHealthProbe.self,
            EventsProbe.self,
            ExitStatusProbe.self,
            FailureModes.self,
            Cleanup.self,
        ],
        defaultSubcommand: RunAll.self
    )
}

struct RunAll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run all probes in sequence")

    func run() async throws {
        try await ListContainers().run()
        try await CreateContainer().run()
        try await StartContainer().run()
        try await InspectContainer().run()
        try await StopContainer().run()
        try await KillContainer().run()
        try await DeleteContainer().run()
        try await PauseProbe().run()
        try await LogsProbe().run()
        try await StatsProbe().run()
        try await ExecProbe().run()
        try await ListImages().run()
        try await PullImage().run()
        try await BuildProbe().run()
        try await ImageOpsProbe().run()
        try await RegistryProbe().run()
        try await VolumeProbe().run()
        try await MachineProbe().run()
        try await SystemHealthProbe().run()
        try await EventsProbe().run()
    }
}

struct ListContainers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #1: list containers")

    func run() async throws {
        let client = ContainerClient()
        let all = try await client.list(filters: .all)
        printResult("list.all.count", all.count)

        let running = try await client.list(filters: ContainerListFilters(status: .running))
        printResult("list.running.count", running.count)

        let stopped = try await client.list(filters: ContainerListFilters(status: .stopped))
        printResult("list.stopped.count", stopped.count)

        let missing = try await client.list(filters: ContainerListFilters(ids: ["spike-nonexistent"]))
        printResult("list.missing.count", missing.count)

        do {
            _ = try await client.get(id: "spike-nonexistent")
            print("FAIL get.missing: expected notFound")
        } catch let err as ContainerizationError where err.isCode(.notFound) {
            printResult("get.missing", err.message)
        }
    }
}

struct InspectContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #2: inspect container")

    func run() async throws {
        let containerId = "spike-create"
        let client = ContainerClient()
        let snap = try await client.get(id: containerId)
        printResult("inspect.id", snap.id)
        printResult("inspect.status", snap.status.rawValue)
        printResult("inspect.ports.count", snap.configuration.publishedPorts.count)
        printResult("inspect.mounts.count", snap.configuration.mounts.count)
        printResult("inspect.env.count", snap.configuration.initProcess.environment.count)
        printResult("inspect.networks.count", snap.networks.count)
        let encoded = try JSONEncoder().encode(snap)
        printResult("inspect.json.bytes", encoded.count)
    }
}

struct CreateContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #3: create container")

    func run() async throws {
        let containerId = "spike-create"
        let image = "python:alpine"
        let systemConfig = try await loadSystemConfig()
        _ = try await prepareInitImage(systemConfig: systemConfig)
        let imageObj = try await prepareImage(reference: image, systemConfig: systemConfig)
        let (config, kernel) = try await makeContainerConfig(
            id: containerId,
            image: imageObj,
            command: ["/bin/sleep", "300"],
            systemConfig: systemConfig
        )

        let client = ContainerClient()
        try await client.create(configuration: config, options: .default, kernel: kernel)
        printResult("create.id", containerId)
        printResult("create.kernel.path", kernel.path.path)
        printResult("create.kernel.args", kernel.kernelArgs.joined(separator: " "))

        let snap = try await client.get(id: containerId)
        printResult("create.status", snap.status.rawValue)
    }
}

struct StartContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #4: start container")

    func run() async throws {
        let containerId = "spike-create"
        let client = ContainerClient()
        let nullOut = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
        let process = try await client.bootstrap(id: containerId, stdio: [nil, nullOut, nullOut])
        try await process.start()
        let snap = try await client.get(id: containerId)
        printResult("start.status", snap.status.rawValue)

        // Idempotent second start
        let process2 = try await client.bootstrap(id: containerId, stdio: [nil, nullOut, nullOut])
        try await process2.start()
        printResult("start.idempotent", "ok")
    }
}

struct StopContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #5: stop container")

    func run() async throws {
        let containerId = "spike-create"
        let client = ContainerClient()
        try await client.stop(id: containerId, opts: ContainerStopOptions(timeoutInSeconds: 3, signal: nil))
        let snap = try await client.get(id: containerId)
        printResult("stop.status", snap.status.rawValue)

        // Already stopped
        try await client.stop(id: containerId)
        printResult("stop.alreadyStopped", "ok")
    }
}

struct KillContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #6: kill container")

    func run() async throws {
        let containerId = "spike-kill"
        _ = try await createAndStartContainer(id: containerId, imageRef: "python:alpine", command: ["/bin/sleep", "300"])
        let client = ContainerClient()
        try await client.kill(id: containerId, signal: "KILL")
        printResult("kill.signal", "KILL")
        let snap = try await client.get(id: containerId)
        printResult("kill.statusAfter", snap.status.rawValue)
    }
}

struct DeleteContainer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #7: delete container")

    func run() async throws {
        let containerId = "spike-delete"
        let systemConfig = try await loadSystemConfig()
        _ = try await prepareInitImage(systemConfig: systemConfig)
        let imageObj = try await prepareImage(reference: "python:alpine", systemConfig: systemConfig)
        let (config, kernel) = try await makeContainerConfig(
            id: containerId,
            image: imageObj,
            command: ["/bin/sleep", "300"],
            systemConfig: systemConfig
        )
        let client = ContainerClient()
        try await client.create(configuration: config, options: .default, kernel: kernel)

        let nullOut = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
        let process = try await client.bootstrap(id: containerId, stdio: [nil, nullOut, nullOut])
        try await process.start()

        do {
            try await client.delete(id: containerId, force: false)
            print("FAIL delete.runningWithoutForce: expected error")
        } catch {
            printResult("delete.runningWithoutForce", formatError(error))
        }

        try await client.stop(id: containerId)
        try await client.delete(id: containerId, force: false)
        printResult("delete.stopped", "ok")

        do {
            _ = try await client.get(id: containerId)
            print("FAIL delete.verify: container still exists")
        } catch let err as ContainerizationError where err.isCode(.notFound) {
            printResult("delete.verify", err.message)
        }
    }
}

struct PauseProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #8: pause/unpause")

    func run() async throws {
        printResult("pause.publicAPI", "no pause/unpause methods on ContainerClient")
        printResult("pause.runtimeStatus", RuntimeStatus.allCases.map(\.rawValue).joined(separator: ", "))

        let client = XPCClient(service: "com.apple.container.apiserver")
        for route in ["containerPause", "containerUnpause", "pause", "unpause"] {
            let request = XPCMessage(route: route)
            request.set(key: .id, value: "spike-create")
            do {
                _ = try await client.send(request, responseTimeout: .seconds(5))
                printResult("pause.rawRoute.\(route)", "unexpected success")
            } catch {
                printResult("pause.rawRoute.\(route)", formatError(error))
            }
        }
    }
}

struct LogsProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #9: container logs")

    func run() async throws {
        let containerId = "spike-logs"
        _ = try await createAndStartContainer(
            id: containerId,
            imageRef: "python:alpine",
            command: ["/bin/sh", "-c", "echo spike-stdout; echo spike-stderr >&2; sleep 60"]
        )

        let client = ContainerClient()
        let handles = try await client.logs(id: containerId)
        printResult("logs.handleCount", handles.count)

        try await Task.sleep(for: .seconds(2))

        var combined = ""
        for (index, handle) in handles.enumerated() {
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                combined += "[fd\(index)]\(text)"
            }
        }
        printResult("logs.snapshot", combined.isEmpty ? "<empty>" : combined.prefix(200))

        do {
            _ = try await client.logs(id: "spike-nonexistent")
            print("FAIL logs.missing: expected error")
        } catch {
            printResult("logs.missing", formatError(error))
        }
    }
}

struct StatsProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #10: container stats")

    func run() async throws {
        let containerId = "spike-stats"
        _ = try await createAndStartContainer(id: containerId, imageRef: "python:alpine")

        let client = ContainerClient()
        let start = ContinuousClock.now
        let stats = try await client.stats(id: containerId)
        let elapsed = start.duration(to: .now)
        printResult("stats.oneshot.ms", Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000))
        printResult("stats.memoryUsageBytes", stats.memoryUsageBytes ?? 0)
        printResult("stats.cpuUsageUsec", stats.cpuUsageUsec ?? 0)
        printResult("stats.networkRxBytes", stats.networkRxBytes ?? 0)
        printResult("stats.numProcesses", stats.numProcesses ?? 0)

        let start2 = ContinuousClock.now
        _ = try await client.stats(id: containerId)
        let elapsed2 = start2.duration(to: .now)
        printResult("stats.secondSample.ms", Int(elapsed2.components.seconds * 1000 + elapsed2.components.attoseconds / 1_000_000_000_000_000))
    }
}

struct ExecProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #11: exec in container")

    func run() async throws {
        let containerId = "spike-exec"
        _ = try await createAndStartContainer(id: containerId, imageRef: "python:alpine")

        let client = ContainerClient()
        let readPipe = Pipe()
        let writePipe = Pipe()
        let errPipe = Pipe()

        let config = ProcessConfiguration(
            executable: "/bin/echo",
            arguments: ["spike-exec-ok"],
            environment: [],
            workingDirectory: "/",
            terminal: false
        )

        let process = try await client.createProcess(
            containerId: containerId,
            processId: "spike-exec-proc",
            configuration: config,
            stdio: [nil, writePipe.fileHandleForWriting, errPipe.fileHandleForWriting]
        )
        try await process.start()
        let code = try await process.wait()
        writePipe.fileHandleForWriting.closeFile()
        let stdoutData = writePipe.fileHandleForReading.readDataToEndOfFile()
        printResult("exec.exitCode", code)
        printResult("exec.stdout", String(data: stdoutData, encoding: .utf8) ?? "<binary>")

        // PTY / interactive probe
        let ttyConfig = ProcessConfiguration(
            executable: "/bin/sh",
            arguments: [],
            environment: [],
            workingDirectory: "/",
            terminal: true
        )
        let ttyProcess = try await client.createProcess(
            containerId: containerId,
            processId: "spike-exec-tty",
            configuration: ttyConfig,
            stdio: [nil, nil, nil]
        )
        do {
            try await ttyProcess.start()
            try await ttyProcess.resize(Terminal.Size(width: 80, height: 24))
            do {
                try await ttyProcess.kill(SIGTERM)
                printResult("exec.pty.kill", "ok")
            } catch {
                printResult("exec.pty.kill", formatError(error))
            }
            printResult("exec.pty", "create+resize ok")
        } catch {
            printResult("exec.pty", formatError(error))
        }
    }
}

struct ListImages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #12: list images")

    func run() async throws {
        let images = try await ClientImage.list()
        printResult("images.count", images.count)
        for image in images.prefix(5) {
            printResult("images.ref", image.reference)
        }
    }
}

struct PullImage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #13: pull image")

    func run() async throws {
        let reference = "alpine:3.22"
        let systemConfig = try await loadSystemConfig()
        final class ProgressCounter: @unchecked Sendable {
            var count = 0
        }
        let counter = ProgressCounter()
        let image = try await ClientImage.pull(
            reference: reference,
            containerSystemConfig: systemConfig,
            progressUpdate: { events in
                counter.count += events.count
            }
        )
        printResult("pull.reference", image.reference)
        printResult("pull.digest", image.digest.prefix(16))
        printResult("pull.progressEvents", counter.count)
    }
}

struct BuildProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #14: build image")

    func run() async throws {
        printResult("build.ContainerBuild", "no XPC references in ContainerBuild module")
        printResult("build.ContainerAPIClient", "no build methods exposed")
        let result = try runCLI(["build", "--help"])
        printResult("build.cli.help.exit", result.exitCode)
        printResult("build.cli.help.hasBuild", result.stdout.contains("Build an image"))
    }
}

struct ImageOpsProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #15: delete/tag/push image")

    func run() async throws {
        let systemConfig = try await loadSystemConfig()
        let source = try await ClientImage.get(reference: "python:alpine", containerSystemConfig: systemConfig)
        let tagged = try await source.tag(new: "spike-test:probe")
        printResult("image.tag.newRef", tagged.reference)

        do {
            try await ClientImage.delete(reference: "spike-nonexistent:missing", garbageCollect: false)
            print("FAIL image.delete.missing: expected error")
        } catch {
            printResult("image.delete.missing", formatError(error))
        }

        printResult("image.push", "XPC route imagePush exists; skipped live push to avoid registry side effects")
    }
}

struct RegistryProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #16: registry login")

    func run() async throws {
        printResult("registry.login", "CLI uses RegistryClient.ping + KeychainHelper.save — no XPC login route")
        let result = try runCLI(["registry", "list"])
        printResult("registry.list.cli.exit", result.exitCode)
        printResult("registry.list.cli.stdout", result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct VolumeProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #17: volumes")

    func run() async throws {
        let volumeName = "spike-volume"
        let created = try await ClientVolume.create(name: volumeName)
        printResult("volume.create.name", created.name)

        let all = try await ClientVolume.list()
        printResult("volume.list.count", all.count)

        let inspected = try await ClientVolume.inspect(volumeName)
        printResult("volume.inspect.driver", inspected.driver)

        let size = try await ClientVolume.volumeDiskUsage(name: volumeName)
        printResult("volume.diskUsage", size)

        try await ClientVolume.delete(name: volumeName)
        printResult("volume.delete", "ok")

        do {
            _ = try await ClientVolume.inspect("spike-nonexistent-volume")
            print("FAIL volume.inspect.missing: expected error")
        } catch {
            printResult("volume.inspect.missing", formatError(error))
        }
    }
}

struct MachineProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #18: machines")

    func run() async throws {
        let client = MachineClient()
        let machines = try await client.list()
        printResult("machine.list.count", machines.count)

        let defaultMachine = try await client.getDefault()
        printResult("machine.default", defaultMachine ?? "<none>")

        do {
            _ = try await client.inspect(id: "spike-nonexistent-machine")
            print("FAIL machine.inspect.missing: expected error")
        } catch {
            printResult("machine.inspect.missing", formatError(error))
        }
    }
}

struct SystemHealthProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #19: system health")

    func run() async throws {
        let health = try await ClientHealthCheck.ping()
        printResult("health.apiServerVersion", health.apiServerVersion)
        printResult("health.apiServerCommit", health.apiServerCommit.prefix(8))
        printResult("health.appRoot", health.appRoot.path())
        printResult("health.installRoot", health.installRoot.path())
    }
}

struct ExitStatusProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exit-status",
        abstract: "B1 manual check — init exit code via containerWait"
    )

    @Argument(help: "Stopped container IDs")
    var containerIDs: [String]

    func run() async throws {
        let client = XPCClient(service: "com.apple.container.apiserver")
        for id in containerIDs {
            let request = XPCMessage(route: .containerWait)
            request.set(key: .id, value: id)
            request.set(key: .processIdentifier, value: id)
            do {
                let response = try await client.send(request)
                let code = response.int64(key: .exitCode)
                printResult("exitStatus.\(id)", Int32(code))
            } catch {
                printResult("exitStatus.\(id)", formatError(error))
            }
        }
    }
}

struct EventsProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe #20: events/notifications")

    func run() async throws {
        printResult("events.publicAPI", "no subscription/watch methods on ContainerClient")

        let client = XPCClient(service: "com.apple.container.apiserver")
        for route in ["containerEvent", "containerState"] {
            let request = XPCMessage(route: route)
            request.set(key: .id, value: "spike-create")
            do {
                _ = try await client.send(request, responseTimeout: .seconds(5))
                printResult("events.rawRoute.\(route)", "unexpected success")
            } catch {
                printResult("events.rawRoute.\(route)", formatError(error))
            }
        }
    }
}

struct FailureModes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Probe daemon-down failure modes")

    func run() async throws {
        print("Stopping container services...")
        let stopResult = try runCLI(["system", "stop"])
        printResult("system.stop.exit", stopResult.exitCode)

        defer {
            print("Restarting container services...")
            let startResult = try? runCLI(["system", "start"])
            printResult("system.start.exit", startResult?.exitCode ?? -1)
        }

        // Probe 1: health ping
        do {
            _ = try await ClientHealthCheck.ping(timeout: .seconds(5))
            print("FAIL daemonDown.ping: expected error")
        } catch {
            print("VERBATIM daemonDown.ping: \(formatError(error))")
        }

        // Probe 2: list containers
        do {
            _ = try await ContainerClient().list()
            print("FAIL daemonDown.list: expected error")
        } catch {
            print("VERBATIM daemonDown.list: \(formatError(error))")
        }

        // Probe 3: get missing container (still daemon down)
        do {
            _ = try await ContainerClient().get(id: "spike-nonexistent")
            print("FAIL daemonDown.get: expected error")
        } catch {
            print("VERBATIM daemonDown.get: \(formatError(error))")
        }
    }
}

struct Cleanup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove spike-* artifacts")

    func run() async throws {
        let client = ContainerClient()
        let containers = try await client.list(filters: .all)
        for container in containers where container.id.hasPrefix("spike-") {
            await deleteContainerIfExists(container.id)
        }

        let volumes = try await ClientVolume.list()
        for volume in volumes where volume.name.hasPrefix("spike-") {
            await deleteVolumeIfExists(volume.name)
        }

        let images = try await ClientImage.list()
        for image in images where image.reference.contains("spike-") {
            do {
                try await ClientImage.delete(reference: image.reference, garbageCollect: false)
                print("CLEANUP deleted image \(image.reference)")
            } catch {
                print("CLEANUP skip image \(image.reference): \(formatError(error))")
            }
        }

        // Remove tagged probe image if present
        do {
            try await ClientImage.delete(reference: "spike-test:probe", garbageCollect: false)
            print("CLEANUP deleted image spike-test:probe")
        } catch {
            print("CLEANUP skip image spike-test:probe: \(formatError(error))")
        }
    }
}

struct CLIRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

func runCLI(_ args: [String]) throws -> CLIRunResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
    process.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()
    process.waitUntilExit()
    let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return CLIRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
}

@main
enum Main {
    static func main() async {
        do {
            try await ProbeCommands.main()
        } catch {
            fputs("xpc-probe error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
