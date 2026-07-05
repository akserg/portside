// WharfsideTests/CLIRunnerTests.swift

import Foundation
import Testing
@testable import Wharfside

@MainActor
struct CLIRunnerTests {
    @Test func successWithEchoStandIn() async throws {
        let result = try await CLIRunner.run(
            arguments: ["hello"],
            executableURL: URL(fileURLWithPath: "/bin/echo")
        )
        #expect(result.stdout == "hello\n")
    }

    @Test func nonZeroExit() async {
        do {
            _ = try await CLIRunner.run(
                arguments: [],
                executableURL: URL(fileURLWithPath: "/usr/bin/false")
            )
            Issue.record("Expected non-zero exit")
        } catch let error as CLIRunnerError {
            #expect(error == .nonZeroExit(code: 1, stderr: ""))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func stdinDeliveryWithCatStandIn() async throws {
        let result = try await CLIRunner.run(
            arguments: [],
            stdin: Data("piped".utf8),
            executableURL: URL(fileURLWithPath: "/bin/cat")
        )
        #expect(result.stdout == "piped")
    }

    @Test func timeout() async {
        do {
            _ = try await CLIRunner.run(
                arguments: ["5"],
                timeout: 0.2,
                executableURL: URL(fileURLWithPath: "/bin/sleep")
            )
            Issue.record("Expected timeout")
        } catch let error as CLIRunnerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
