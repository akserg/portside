// WharfsideTests/WharfsideTests.swift

import Testing
@testable import Wharfside

@MainActor
struct WharfsideTests {
    @Test func mockSystemServiceHealth() async throws {
        let mock = MockSystemService()
        let health = try await mock.health()
        #expect(health.apiServerVersion == "1.0.0")
        #expect(mock.healthCallCount == 1)
    }
}
