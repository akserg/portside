// Services/XPCImageService.swift

import ContainerAPIClient
import ContainerPersistence
import Foundation
import TerminalProgress

actor XPCImageService: ImageServicing {
    private let connection = RuntimeConnection()

    func list() async throws -> [ImageSummary] {
        let systemConfig = try await ContainerCreateSupport.loadSystemConfig()
        let images = try await ClientImage.list().filter { image in
            !Utility.isInfraImage(
                name: image.reference,
                builderImage: systemConfig.build.image,
                initImage: systemConfig.vminit.image
            )
        }

        var summaries: [ImageSummary] = []
        summaries.reserveCapacity(images.count)
        for image in images {
            let resource = try await image.toImageResource(containerSystemConfig: systemConfig)
            summaries.append(RuntimeModelMapping.imageSummary(from: resource))
        }
        return summaries
    }

    func pull(
        reference: String,
        onProgress: (@Sendable (PullProgress) -> Void)?
    ) async throws -> ImageSummary {
        let systemConfig = try await ContainerCreateSupport.loadSystemConfig()
        let image = try await ClientImage.pull(
            reference: reference,
            containerSystemConfig: systemConfig,
            progressUpdate: { events in
                guard let onProgress else { return }
                for event in events {
                    if case .setDescription(let description) = event {
                        onProgress(PullProgress(description: description, completedUnits: 0, totalUnits: nil))
                    } else if case .addItems(let count) = event {
                        onProgress(PullProgress(description: "Pulling", completedUnits: count, totalUnits: nil))
                    } else if case .setItems(let count) = event {
                        onProgress(PullProgress(description: "Pulling", completedUnits: count, totalUnits: nil))
                    }
                }
            }
        )
        return RuntimeModelMapping.imageSummary(from: image)
    }

    func delete(reference: String) async throws {
        let images = try await ClientImage.list()
        let exists = images.contains { image in
            image.reference == reference
        }
        guard exists else {
            throw WharfsideError.notFound("Image not found: \(reference)")
        }

        try await ClientImage.delete(reference: reference, garbageCollect: false)
    }

    func tag(source: String, target: String) async throws -> ImageSummary {
        let systemConfig = try await ContainerCreateSupport.loadSystemConfig()
        let image = try await ClientImage.get(reference: source, containerSystemConfig: systemConfig)
        let tagged = try await image.tag(new: target)
        return RuntimeModelMapping.imageSummary(from: tagged)
    }
}
