// WharfsideTests/CLIRegistryServiceTests.swift

import Foundation
import Testing
@testable import Wharfside

@MainActor
struct CLIRegistryServiceTests {
    @Test func loginUsesPasswordStdinAndOmitsPasswordFromArguments() async throws {
        let capture = CaptureBox()

        let service = CLIRegistryService { arguments, stdin in
            capture.arguments = arguments
            capture.stdin = stdin
            return CLIRunResult(exitCode: 0, stdout: "", stderr: "")
        }

        try await service.login(registry: "docker.io", username: "wharf", password: "super-secret")

        #expect(capture.arguments == ["registry", "login", "--username", "wharf", "--password-stdin", "docker.io"])
        #expect(capture.stdin == Data("super-secret".utf8))
        #expect(!capture.arguments.contains("super-secret"))
        #expect(capture.arguments.contains("--password-stdin"))
    }

    @Test func loginArgumentBuilderMatchesService() {
        let arguments = CLIRegistryCommandBuilder.loginArguments(registry: "ghcr.io", username: "user")
        #expect(arguments == ["registry", "login", "--username", "user", "--password-stdin", "ghcr.io"])
        #expect(!arguments.contains(where: { $0.contains("password") && $0 != "--password-stdin" }))
    }

    @Test func listParsesQuietOutput() async throws {
        let service = CLIRegistryService { arguments, _ in
            #expect(arguments == ["registry", "list", "--quiet"])
            return CLIRunResult(exitCode: 0, stdout: "docker.io\ngcr.io\n", stderr: "")
        }

        let registries = try await service.list()
        #expect(registries.map(\.hostname) == ["docker.io", "gcr.io"])
    }

    @Test func logoutPassesRegistryArgument() async throws {
        let capture = CaptureBox()

        let service = CLIRegistryService { arguments, _ in
            capture.arguments = arguments
            return CLIRunResult(exitCode: 0, stdout: "", stderr: "")
        }

        try await service.logout(registry: "docker.io")
        #expect(capture.arguments == ["registry", "logout", "docker.io"])
    }
}

private final class CaptureBox: @unchecked Sendable {
    var arguments: [String] = []
    var stdin: Data?
}
