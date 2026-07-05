// Services/CLIRunner.swift

import Foundation

struct CLIRunResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CLIRunnerError: LocalizedError, Equatable {
    case nonZeroExit(code: Int32, stderr: String)
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            "Command exited with status \(code): \(stderr)"
        case .launchFailed(let message):
            message
        case .timedOut:
            "Command timed out"
        }
    }
}

enum CLIRunner {
    nonisolated static let executablePath = "/usr/local/bin/container"

    nonisolated static func run(
        arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval? = nil,
        executableURL: URL = URL(fileURLWithPath: executablePath)
    ) async throws -> CLIRunResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            stdinPipe.fileHandleForWriting.write(stdin)
            try stdinPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        if let timeout {
            let finished = await waitUntilExit(process: process, timeout: timeout)
            guard finished else {
                process.terminate()
                throw CLIRunnerError.timedOut
            }
        } else {
            process.waitUntilExit()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw CLIRunnerError.nonZeroExit(code: process.terminationStatus, stderr: stderr)
        }

        return CLIRunResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func waitUntilExit(process: Process, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                continuation.resume(returning: !process.isRunning)
            }
        }
    }
}
