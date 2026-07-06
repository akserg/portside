// Services/CLIRegistryService.swift

import Foundation

struct CLIRegistryService: RegistryServicing, Sendable {
    typealias RunHandler = @Sendable ([String], Data?) async throws -> CLIRunResult

    private let run: RunHandler

    nonisolated init(run: @escaping RunHandler = CLIRegistryService.defaultRun) {
        self.run = run
    }

    nonisolated func list() async throws -> [RegistryEntry] {
        let result = try await run(["registry", "list", "--quiet"], nil)
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { RegistryEntry(hostname: $0, username: "") }
    }

    nonisolated func login(registry: String, username: String, password: String) async throws {
        _ = try await run(
            ["registry", "login", "--username", username, "--password-stdin", registry],
            Data(password.utf8)
        )
    }

    nonisolated func logout(registry: String) async throws {
        _ = try await run(["registry", "logout", registry], nil)
    }

    nonisolated private static let defaultRun: RunHandler = { arguments, stdin in
        try await CLIRunner.run(arguments: arguments, stdin: stdin)
    }
}

enum CLIRegistryCommandBuilder {
    nonisolated static func loginArguments(registry: String, username: String) -> [String] {
        ["registry", "login", "--username", username, "--password-stdin", registry]
    }
}
