// WharfsideTests/Mocks/MockImageService.swift

import Foundation
@testable import Wharfside

final class MockImageService: ImageServicing, @unchecked Sendable {
    var images: [ImageSummary] = []
    var deleteShouldFailNotFound = false

    private(set) var deleteCallCount = 0

    func list() async throws -> [ImageSummary] {
        images
    }

    func pull(reference: String, onProgress: (@Sendable (PullProgress) -> Void)?) async throws -> ImageSummary {
        ImageSummary(reference: reference, digest: "sha256:mock")
    }

    func delete(reference: String) async throws {
        deleteCallCount += 1
        if deleteShouldFailNotFound {
            throw WharfsideError.notFound("Image not found: \(reference)")
        }
    }

    func tag(source: String, target: String) async throws -> ImageSummary {
        ImageSummary(reference: target, digest: "sha256:mock")
    }
}
