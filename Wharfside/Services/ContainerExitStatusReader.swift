// Services/ContainerExitStatusReader.swift

import ContainerAPIClient
import ContainerXPC
import Foundation

/// Reads init-process exit codes via the `containerWait` XPC route (apple/container 1.0).
///
/// `ContainerSnapshot` from `list`/`get` does not carry exit status; the runtime stores it
/// server-side and returns it through `containerWait` with `processIdentifier == containerID`
/// (the init process — same contract as `ClientProcess.wait()` after `bootstrap`).
enum ContainerExitStatusReader {
    static func fetchInitProcessExitCode(
        containerID: String,
        client: XPCClient
    ) async throws -> Int32 {
        let request = XPCMessage(route: .containerWait)
        request.set(key: .id, value: containerID)
        request.set(key: .processIdentifier, value: containerID)

        let response = try await client.send(request)
        let code = response.int64(key: .exitCode)
        return Int32(code)
    }

    nonisolated static func makeClient() -> XPCClient {
        XPCClient(service: "com.apple.container.apiserver")
    }
}
