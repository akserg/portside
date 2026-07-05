// WharfsideTests/XPCImageServiceTests.swift

import Testing
@testable import Wharfside

@MainActor
struct XPCImageServiceTests {
    @Test func deleteMissingReferenceThrowsNotFound() async {
        let mock = MockImageService()
        mock.deleteShouldFailNotFound = true

        do {
            try await mock.delete(reference: "spike-nonexistent:missing")
            Issue.record("Expected notFound")
        } catch let error as WharfsideError {
            #expect(error == .notFound("Image not found: spike-nonexistent:missing"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
